import { writeFile } from 'node:fs/promises';
import type { AgentContext, AgentEmit, FilePatch } from '../types/agent.ts';
import type {
  FeedbackTicket,
  FeedbackTicketEventStage,
  FeedbackTarget,
} from '../types/feedback.ts';
import type { CommandRequest } from '../types/command.ts';
import type { SelectedComponentContext } from '../types/context.ts';
import type { AgentService } from './agent_service.ts';
import type { ContextAssembler } from './context_assembler.ts';
import type { FeedbackStore } from './feedback_store.ts';
import type { LocalCiRunner } from './local_ci_runner.ts';
import type { PatchGuardService } from './patch_guard_service.ts';
import type { PreviewPublisher } from './preview_publisher.ts';
import type { ProjectContextService } from './project_context_service.ts';
import { evaluateInstruction, SafetyError } from './safety_policy.ts';

export type FeedbackPipelineDeps = {
  projects: ProjectContextService;
  contextAssembler: ContextAssembler;
  agents: AgentService;
  patchGuard: PatchGuardService;
  store: FeedbackStore;
  ci: LocalCiRunner;
  publisher: PreviewPublisher;
};

export type ProcessOptions = {
  /** Build mode override (defaults to release for ticket mode). */
  buildFlavor?: 'profile' | 'release';
  skipTests?: boolean;
  /**
   * `Host` header from the client request (e.g. `localhost:8788`); preferred
   * source for building an absolute preview URL the browser can reach.
   */
  requestHost?: string;
  /** Server bind host (used as fallback only when requestHost is absent). */
  serverHost?: string;
  /** Server bind port (used as fallback only when requestHost is absent). */
  serverPort: number;
};

export class FeedbackPipeline {
  private readonly deps: FeedbackPipelineDeps;
  /** Tickets currently being processed; prevents double-processing. */
  private readonly inFlight = new Set<string>();

  constructor(deps: FeedbackPipelineDeps) {
    this.deps = deps;
  }

  isProcessing(ticketId: string): boolean {
    return this.inFlight.has(ticketId);
  }

  /**
   * Run the full ticket pipeline: agent → patch guard → write → CI → publish.
   *
   * Returns the final ticket snapshot. The caller can `await` this for tests
   * or fire-and-forget for HTTP requests.
   */
  async process(ticketId: string, options: ProcessOptions): Promise<FeedbackTicket | undefined> {
    if (this.inFlight.has(ticketId)) {
      return this.deps.store.get(ticketId);
    }
    this.inFlight.add(ticketId);
    try {
      return await this.runPipeline(ticketId, options);
    } finally {
      this.inFlight.delete(ticketId);
    }
  }

  private async runPipeline(
    ticketId: string,
    options: ProcessOptions,
  ): Promise<FeedbackTicket | undefined> {
    const initial = this.deps.store.get(ticketId);
    if (!initial) return undefined;
    if (initial.status === 'deployed') {
      this.emit(ticketId, 'log', 'Ticket already deployed; nothing to do.');
      return initial;
    }

    this.deps.store.setStatus(ticketId, 'planned', 'Pipeline started.');
    this.emit(ticketId, 'processing_started', `Processing ticket ${ticketId}.`, {
      instruction: initial.instruction,
    });

    // 1. Instruction safety
    const safety = evaluateInstruction(initial.instruction);
    if (!safety.allowed) {
      const reason = safety.reasons.join('; ');
      this.deps.store.setStatus(ticketId, 'failed', `Instruction blocked: ${reason}`, { safety });
      this.emit(ticketId, 'failed', `Instruction blocked by safety policy: ${reason}`);
      return this.deps.store.get(ticketId);
    }

    // 2. Resolve project + agent context
    let project;
    try {
      project = await this.deps.projects.collect(undefined);
    } catch (error) {
      return this.fail(ticketId, error, 'Failed to collect project context.');
    }

    const syntheticRequest = this.buildSyntheticCommandRequest(initial);

    const agentEmit: AgentEmit = (stage, message, payload) => {
      this.emit(ticketId, mapAgentStage(stage), message, payload);
    };

    let assembled;
    try {
      assembled = await this.deps.contextAssembler.assemble(syntheticRequest, project, agentEmit);
    } catch (error) {
      return this.fail(ticketId, error, 'Failed to assemble agent context.');
    }

    const agentContext: AgentContext = {
      ...assembled.agentContext,
      // Augment instruction with ticket page/target info so the agent has the
      // location even when there's no live debug selection.
      instruction: composeAgentInstruction(initial),
    };

    // 3. Run agent
    this.emit(ticketId, 'agent_started', 'Invoking agent adapter for ticket.', {
      candidateFiles: assembled.summary.candidateFiles,
    });

    let runResult;
    try {
      runResult = await this.deps.agents.run(agentContext);
    } catch (error) {
      return this.fail(ticketId, error, 'Agent adapter crashed.');
    }

    if (runResult.fellBackFromCodex) {
      this.emit(ticketId, 'log', `Codex unavailable, fell back to mock: ${runResult.fallbackReason}`);
    }

    const patchResult = runResult.result;
    this.deps.store.patch(ticketId, {
      agentOutput: patchResult.agentOutput,
      changedFiles: patchResult.changedFiles,
    });

    if (!patchResult.applied) {
      this.deps.store.setStatus(ticketId, 'failed', patchResult.message || 'Agent produced no changes.');
      this.emit(ticketId, 'agent_failed', patchResult.message || 'Agent produced no changes.');
      return this.deps.store.get(ticketId);
    }

    // 4. Patch guard + write
    try {
      await this.deps.patchGuard.validate(patchResult.patches, project.projectPath);
      await this.deps.patchGuard.backup(`feedback_${ticketId}`, patchResult.patches);
      await this.writePatches(patchResult.patches);
    } catch (error) {
      // Roll back any partial writes by restoring originals.
      await this.rollbackPatches(patchResult.patches).catch(() => undefined);
      if (error instanceof SafetyError) {
        const reasons = error.decision.reasons.join('; ');
        this.deps.store.setStatus(ticketId, 'failed', `Patch blocked by safety policy: ${reasons}`, {
          safety: error.decision,
        });
        this.emit(ticketId, 'agent_failed', `Patch blocked: ${reasons}`);
        return this.deps.store.get(ticketId);
      }
      return this.fail(ticketId, error, 'Patch guard crashed.');
    }

    this.deps.store.setStatus(ticketId, 'applied', `Patch applied to ${patchResult.changedFiles.join(', ')}.`);
    this.emit(ticketId, 'patch_applied', `Applied patch to ${patchResult.changedFiles.join(', ')}.`, {
      changedFiles: patchResult.changedFiles,
    });

    // 5. Local CI
    this.deps.store.setStatus(ticketId, 'ci_running', 'Local CI started.');
    this.emit(ticketId, 'ci_started', 'Local CI started: analyze → test → build_web.');
    const ciResult = await this.deps.ci.run(project.projectPath, {
      skipTests: options.skipTests,
      buildFlavor: options.buildFlavor,
      onStepEvent: (event) => {
        const step = event.step;
        if (event.type === 'step_started') {
          this.emit(ticketId, 'ci_step_started', `[ci] ${step.name} started`, { step });
        } else if (event.type === 'step_passed') {
          this.emit(ticketId, 'ci_step_passed', `[ci] ${step.name} passed (${step.durationMs}ms)`, {
            step,
          });
        } else {
          this.emit(ticketId, 'ci_step_failed', `[ci] ${step.name} failed`, { step });
        }
        // Persist after each step so HTTP polling reflects partial state.
        const current = this.deps.store.get(ticketId)?.ci ?? {
          status: 'running' as const,
          steps: [],
        };
        const stepsCopy = current.steps.slice();
        const idx = stepsCopy.findIndex((s) => s.name === step.name);
        if (idx >= 0) stepsCopy[idx] = step;
        else stepsCopy.push(step);
        this.deps.store.setCi(ticketId, { ...current, steps: stepsCopy });
      },
    });
    this.deps.store.setCi(ticketId, ciResult);
    this.emit(ticketId, 'ci_completed', `Local CI finished with status ${ciResult.status}.`, { ci: ciResult });

    if (ciResult.status !== 'passed') {
      this.deps.store.setStatus(ticketId, 'failed', `Local CI failed at one or more steps.`);
      this.emit(ticketId, 'failed', 'Local CI failed; ticket stays in failed state for review.');
      return this.deps.store.get(ticketId);
    }

    // 6. Publish to preview
    this.emit(ticketId, 'deploy_started', 'Publishing build/web to local preview.');
    const publishResult = await this.deps.publisher.publish(project.projectPath);
    if (!publishResult.ok) {
      this.deps.store.setStatus(ticketId, 'failed', `Deploy failed: ${publishResult.message}`);
      this.emit(ticketId, 'failed', publishResult.message);
      return this.deps.store.get(ticketId);
    }

    const previewUrl = this.deps.publisher.buildPreviewUrl(
      options.requestHost,
      options.serverHost,
      options.serverPort,
      ticketId,
    );
    this.deps.store.patch(ticketId, { previewUrl });
    this.emit(ticketId, 'deploy_completed', `Deployed to ${previewUrl}`, { previewUrl });
    this.deps.store.setStatus(ticketId, 'deployed', `Ticket deployed: ${previewUrl}`, { previewUrl });
    return this.deps.store.get(ticketId);
  }

  private buildSyntheticCommandRequest(ticket: FeedbackTicket): CommandRequest {
    const selection = this.buildSyntheticSelection(ticket.target);
    return {
      instruction: ticket.instruction,
      clientMeta: ticket.clientMeta,
      selection,
      runtimeContext: ticket.runtimeContext,
    };
  }

  private buildSyntheticSelection(
    target?: FeedbackTarget,
  ): SelectedComponentContext | undefined {
    if (!target) return undefined;
    const { widgetKey, text, semanticLabel, sourceLocation, bounds } = target;
    if (!widgetKey && !text && !semanticLabel && !sourceLocation) return undefined;

    const candidateFiles: string[] = [];
    if (sourceLocation && sourceLocation.status === 'available') {
      candidateFiles.push(sourceLocation.file);
    }

    return {
      selectionId: `feedback_${Date.now()}`,
      capturedAt: new Date().toISOString(),
      source: 'manual',
      confidence: sourceLocation?.status === 'available' ? 'medium' : 'low',
      widget: {
        widgetType: 'FeedbackTarget',
        text,
        semanticLabel,
        key: widgetKey,
        bounds,
        ancestorChain: [],
        children: [],
      },
      sourceLocation: sourceLocation ?? {
        status: 'unavailable',
        reason: 'Profile/release ticket without inspector source location.',
      },
      codeContext: {
        candidateFiles,
        candidateSymbols: [
          ...(widgetKey ? [widgetKey] : []),
          ...(text ? [text] : []),
        ],
      },
    };
  }

  private async writePatches(patches: FilePatch[]): Promise<void> {
    for (const patch of patches) {
      if (patch.before === patch.after) continue;
      await writeFile(patch.path, patch.after, 'utf8');
    }
  }

  private async rollbackPatches(patches: FilePatch[]): Promise<void> {
    for (const patch of patches) {
      if (patch.before === patch.after) continue;
      try {
        await writeFile(patch.path, patch.before, 'utf8');
      } catch {
        // best effort
      }
    }
  }

  private fail(
    ticketId: string,
    error: unknown,
    contextMessage: string,
  ): FeedbackTicket | undefined {
    const message = error instanceof Error ? error.message : String(error);
    const full = `${contextMessage} ${message}`;
    console.error(`[feedback:${ticketId}] ${full}`);
    this.deps.store.setStatus(ticketId, 'failed', full);
    this.emit(ticketId, 'failed', full);
    return this.deps.store.get(ticketId);
  }

  private emit(
    ticketId: string,
    stage: FeedbackTicketEventStage,
    message: string,
    payload?: Record<string, unknown>,
  ): void {
    this.deps.store.appendEvent(ticketId, stage, message, payload);
  }
}

function mapAgentStage(stage: string): FeedbackTicketEventStage {
  // Coerce CommandStage → FeedbackTicketEventStage for log noise; we keep the
  // semantic stages and force everything else into 'log'.
  switch (stage) {
    case 'agent_started':
      return 'agent_started';
    case 'patch_applied':
    case 'patch_generated':
      return 'patch_applied';
    case 'failed':
      return 'agent_failed';
    default:
      return 'log';
  }
}

function composeAgentInstruction(ticket: FeedbackTicket): string {
  const lines = [ticket.instruction.trim()];
  const ctx: string[] = [];
  if (ticket.pageContext.route) ctx.push(`route=${ticket.pageContext.route}`);
  if (ticket.pageContext.pageId) ctx.push(`pageId=${ticket.pageContext.pageId}`);
  if (ticket.pageContext.title) ctx.push(`title="${ticket.pageContext.title}"`);
  if (ticket.target?.widgetKey) ctx.push(`widgetKey=${ticket.target.widgetKey}`);
  if (ticket.target?.text) ctx.push(`text="${ticket.target.text}"`);
  if (ticket.target?.semanticLabel) ctx.push(`semanticLabel="${ticket.target.semanticLabel}"`);
  if (ticket.target?.sourceLocation?.status === 'available') {
    ctx.push(
      `source=${ticket.target.sourceLocation.file}:${ticket.target.sourceLocation.line}`,
    );
  }
  if (ctx.length > 0) {
    lines.push('', '[Ticket context]', ctx.join(' | '));
  }
  return lines.join('\n');
}
