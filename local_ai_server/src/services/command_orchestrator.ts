import { writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import type {
  AgentContext,
  AgentEmit,
  FilePatch,
  ReloadResult,
} from '../types/agent.ts';
import type {
  CommandEvent,
  CommandRequest,
  CommandResponse,
  CommandStage,
  ContextSummary,
} from '../types/command.ts';
import type { ApprovalDecision, ApprovalRequest } from '../types/safety.ts';
import type { SessionTurn } from '../types/session.ts';
import type { AgentService } from './agent_service.ts';
import type { AppSessionManager } from './app_session_manager.ts';
import type { ContextAssembler } from './context_assembler.ts';
import type { FlutterReloadService } from './flutter_reload_service.ts';
import type { PatchGuardService } from './patch_guard_service.ts';
import type { ProjectContextService } from './project_context_service.ts';
import type { SessionStore } from './session_store.ts';
import { classifyRisk, type RiskAssessment } from './risk_classifier.ts';
import { evaluateInstruction, SafetyError } from './safety_policy.ts';

const MAX_REPAIR_ATTEMPTS = 2;
const APPROVAL_TIMEOUT_MS = 5 * 60 * 1000;

type PendingApproval = {
  commandId: string;
  approvalId: string;
  risk: RiskAssessment;
  /** Patches with final before/after; used to reapply after approval. */
  patches: FilePatch[];
  changedFiles: string[];
  agentOutput: string;
  contextSummary: ContextSummary;
  createdAt: string;
  resolve: (decision: ApprovalDecision) => void;
  timer: NodeJS.Timeout;
};

export type OrchestratorDeps = {
  projects: ProjectContextService;
  contextAssembler: ContextAssembler;
  agents: AgentService;
  patchGuard: PatchGuardService;
  reload: FlutterReloadService;
  appSessions: AppSessionManager;
  sessionStore: SessionStore;
};

export type EnqueueResult = {
  commandId: string;
  turnId: string;
  initialEvent: CommandEvent;
  promise: Promise<CommandResponse>;
};

export class CommandOrchestrator {
  private readonly deps: OrchestratorDeps;
  private readonly pending = new Map<string, PendingApproval>();

  constructor(deps: OrchestratorDeps) {
    this.deps = deps;
  }

  /**
   * Resolve a pending HITL approval (or rejection) for a command. Returns false
   * if no pending approval exists for the given commandId.
   */
  confirm(commandId: string, decision: ApprovalDecision): boolean {
    const pending = this.pending.get(commandId);
    if (!pending) return false;
    if (pending.approvalId !== decision.approvalId) return false;
    clearTimeout(pending.timer);
    this.pending.delete(commandId);
    pending.resolve(decision);
    return true;
  }

  getPendingApproval(commandId: string): ApprovalRequest | null {
    const pending = this.pending.get(commandId);
    if (!pending) return null;
    return this.buildApprovalRequest(pending);
  }

  enqueue(request: CommandRequest): EnqueueResult {
    const commandId = `cmd_${randomUUID().slice(0, 12)}`;
    const turnId = `turn_${randomUUID().slice(0, 12)}`;
    const now = new Date().toISOString();
    const turn: SessionTurn = {
      turnId,
      commandId,
      userInstruction: request.instruction,
      selectionSummary: summarizeSelection(request),
      events: [],
      createdAt: now,
      updatedAt: now,
    };
    this.deps.sessionStore.upsertTurn(turn);

    const initialEvent = this.recordEvent(commandId, 1, 'queued', 'Command queued.');

    const promise = this.run(commandId, request, 2).catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`[command:${commandId}] orchestrator crashed: ${message}`);
      const failResponse: CommandResponse = {
        success: false,
        commandId,
        message: `Orchestrator crashed: ${message}`,
        applied: false,
        reloadTriggered: false,
        changedFiles: [],
        agentOutput: '',
      };
      this.deps.sessionStore.setFinalResponse(commandId, failResponse);
      return failResponse;
    });

    return { commandId, turnId, initialEvent, promise };
  }

  private async run(
    commandId: string,
    request: CommandRequest,
    startSequence: number,
  ): Promise<CommandResponse> {
    let sequence = startSequence;
    const emit = (
      stage: CommandStage,
      message: string,
      payload?: Record<string, unknown>,
    ): CommandEvent => this.recordEvent(commandId, sequence++, stage, message, payload);

    const agentEmit: AgentEmit = (stage, message, payload) => {
      emit(stage, message, payload);
    };

    console.log(`[command:${commandId}] instruction: ${request.instruction}`);
    console.log(`[command:${commandId}] clientMeta: ${JSON.stringify(request.clientMeta ?? {})}`);

    const safety = evaluateInstruction(request.instruction);
    if (!safety.allowed) {
      emit('safety_blocked', safety.reasons.join(' '), { safety });
      const blockedResponse: CommandResponse = {
        success: false,
        commandId,
        message: `Instruction was blocked by safety policy: ${safety.reasons.join('; ')}`,
        applied: false,
        reloadTriggered: false,
        changedFiles: [],
        agentOutput: '',
        safety,
      };
      emit('failed', blockedResponse.message, { safety });
      this.deps.sessionStore.setFinalResponse(commandId, blockedResponse);
      return blockedResponse;
    }
    emit('safety_checked', 'Instruction passed safety policy.', { safety });

    let project;
    try {
      project = await this.deps.projects.collect(request.projectPath);
    } catch (error) {
      return this.failWith(commandId, emit, error, 'Failed to collect project context.');
    }

    let assembled;
    try {
      assembled = await this.deps.contextAssembler.assemble(request, project, agentEmit);
    } catch (error) {
      return this.failWith(commandId, emit, error, 'Failed to assemble context.');
    }

    const contextSummary: ContextSummary = assembled.summary;
    emit('context_collected', `Context collected (${contextSummary.candidateFiles.length} candidate files).`, {
      contextSummary,
    });

    emit('agent_started', 'Invoking agent adapter.');
    let runResult;
    try {
      runResult = await this.deps.agents.run(assembled.agentContext);
    } catch (error) {
      return this.failWith(commandId, emit, error, 'Agent adapter crashed.');
    }

    if (runResult.fellBackFromCodex) {
      emit('agent_log', `Codex unavailable, fell back to mock adapter: ${runResult.fallbackReason}`);
    }

    const patchResult = runResult.result;

    // Track original "before" per file so we can rollback all accumulated
    // changes from this command (including repair attempts) if anything fails.
    const originalBefore = new Map<string, { path: string; before: string }>();
    for (const patch of patchResult.patches) {
      if (!originalBefore.has(patch.relativePath)) {
        originalBefore.set(patch.relativePath, { path: patch.path, before: patch.before });
      }
    }

    let accumulatedAgentOutput = patchResult.agentOutput;
    let accumulatedChangedFiles = [...patchResult.changedFiles];
    let currentPatches = patchResult.patches;

    if (patchResult.applied) {
      try {
        await this.validateAndBackup(commandId, currentPatches, project.projectPath);
      } catch (error) {
        return await this.handleGuardFailure(
          commandId,
          emit,
          error,
          originalBefore,
          contextSummary,
          accumulatedAgentOutput,
          safety,
        );
      }
      emit('patch_applied', `Applied patches to ${accumulatedChangedFiles.join(', ')}.`, {
        changedFiles: accumulatedChangedFiles,
      });
    }

    if (!patchResult.applied) {
      const noopResponse = this.finalizeNoop(
        commandId,
        emit,
        patchResult.message,
        accumulatedAgentOutput,
        contextSummary,
        safety,
        runResult.fellBackFromCodex,
        runResult.fallbackReason,
      );
      return noopResponse;
    }

    // --- HITL gate for high-risk changes ------------------------------------
    const initialRisk = classifyRisk(accumulatedChangedFiles);
    if (initialRisk.requiresApproval) {
      emit('agent_log', `High-risk change detected: ${initialRisk.reasons.join('; ')}`);
      const rollbackErrors = await this.rollbackToBaseline(originalBefore);
      if (rollbackErrors.length > 0) {
        emit('agent_log', `Rollback warnings: ${rollbackErrors.join('; ')}`);
      } else {
        emit('agent_log', 'Rolled back edits; waiting for user approval.');
      }
      const decision = await this.requestApproval(commandId, emit, {
        risk: initialRisk,
        patches: currentPatches,
        changedFiles: accumulatedChangedFiles,
        agentOutput: accumulatedAgentOutput,
        contextSummary,
      });
      if (decision.decision !== 'approved') {
        const rejected: CommandResponse = {
          success: false,
          commandId,
          message: `User ${decision.decision} the high-risk change: ${decision.comment ?? ''}`.trim(),
          applied: false,
          reloadTriggered: false,
          changedFiles: [],
          agentOutput: accumulatedAgentOutput,
          contextSummary,
          safety,
        };
        emit('failed', rejected.message);
        this.deps.sessionStore.setFinalResponse(commandId, rejected);
        return rejected;
      }
      // Approved: re-apply patches, then full rebuild.
      emit('agent_log', 'User approved the high-risk change; re-applying patches.');
      try {
        await this.writePatches(commandId, currentPatches);
      } catch (error) {
        return this.failWith(commandId, emit, error, 'Failed to re-apply patches after approval.');
      }
      emit('patch_applied', `Re-applied patches after approval.`, {
        changedFiles: accumulatedChangedFiles,
      });
      const restartResult = await this.triggerRestart(emit, 'Approved full rebuild: restarting app.');
      if (!restartResult.reloadSucceeded) {
        const failResp: CommandResponse = {
          success: false,
          commandId,
          message: `Hot restart failed after approval: ${restartResult.reloadMessage}`,
          applied: true,
          reloadTriggered: restartResult.reloadTriggered,
          reloadMessage: restartResult.reloadMessage,
          changedFiles: accumulatedChangedFiles,
          agentOutput: accumulatedAgentOutput,
          contextSummary,
          safety,
        };
        emit('failed', failResp.message);
        this.deps.sessionStore.setFinalResponse(commandId, failResp);
        return failResp;
      }
      return this.finalizeSuccess(
        commandId,
        emit,
        restartResult,
        patchResult.message,
        accumulatedChangedFiles,
        accumulatedAgentOutput,
        contextSummary,
        safety,
        runResult.fellBackFromCodex,
        runResult.fallbackReason,
      );
    }

    // --- Normal reload / restart path + self-heal compile errors ------------
    let reloadResult = await this.triggerReloadOrRestart(emit, initialRisk);
    let lastRisk = initialRisk;

    for (
      let attempt = 1;
      !reloadResult.reloadSucceeded && reloadResult.errorText && attempt <= MAX_REPAIR_ATTEMPTS;
      attempt++
    ) {
      emit('agent_log', `Repair attempt ${attempt}/${MAX_REPAIR_ATTEMPTS}: compile errors detected.`);

      let repairResult;
      try {
        const repairContext = buildRepairContext(
          assembled.agentContext,
          request.instruction,
          reloadResult.errorText,
          attempt,
        );
        repairResult = await this.deps.agents.run(repairContext);
      } catch (error) {
        emit('agent_log', `Repair attempt ${attempt} crashed: ${(error as Error).message}`);
        break;
      }

      if (!repairResult.result.applied) {
        emit('agent_log', `Repair attempt ${attempt} made no changes; giving up.`);
        break;
      }

      for (const patch of repairResult.result.patches) {
        if (!originalBefore.has(patch.relativePath)) {
          originalBefore.set(patch.relativePath, { path: patch.path, before: patch.before });
        }
      }

      try {
        await this.validateAndBackup(`${commandId}_repair_${attempt}`, repairResult.result.patches, project.projectPath);
      } catch (error) {
        if (error instanceof SafetyError) {
          emit('safety_blocked', `Repair patch rejected: ${error.decision.reasons.join('; ')}`, {
            safety: error.decision,
          });
          await this.rollbackPatches(repairResult.result.patches);
          break;
        }
        return this.failWith(commandId, emit, error, 'Repair patch guard crashed.');
      }

      emit('patch_applied', `Repair ${attempt} applied to ${repairResult.result.changedFiles.join(', ')}.`, {
        changedFiles: repairResult.result.changedFiles,
      });
      accumulatedChangedFiles = mergeUnique(accumulatedChangedFiles, repairResult.result.changedFiles);
      accumulatedAgentOutput += `\n\n[repair ${attempt}]\n${repairResult.result.agentOutput}`;
      currentPatches = repairResult.result.patches;

      lastRisk = classifyRisk(accumulatedChangedFiles);
      if (lastRisk.requiresApproval) {
        emit('agent_log', 'Repair introduced high-risk file; rolling back and aborting repair loop.');
        break;
      }
      reloadResult = await this.triggerReloadOrRestart(emit, lastRisk);
    }

    if (!reloadResult.reloadSucceeded) {
      emit('agent_log', 'Reload did not succeed; rolling back all command edits.');
      const rollbackErrors = await this.rollbackToBaseline(originalBefore);
      const errSummary = reloadResult.errorText
        ? `\nCompile errors:\n${reloadResult.errorText}`
        : '';
      const warn =
        rollbackErrors.length > 0 ? ` Rollback warnings: ${rollbackErrors.join('; ')}` : '';
      const response: CommandResponse = {
        success: false,
        commandId,
        message: `Reload failed and auto-repair exhausted.${errSummary}${warn}`,
        applied: false,
        reloadTriggered: reloadResult.reloadTriggered,
        reloadMessage: reloadResult.reloadMessage,
        changedFiles: [],
        agentOutput: accumulatedAgentOutput,
        contextSummary,
        safety,
      };
      emit('failed', response.message);
      this.deps.sessionStore.setFinalResponse(commandId, response);
      return response;
    }

    return this.finalizeSuccess(
      commandId,
      emit,
      reloadResult,
      patchResult.message,
      accumulatedChangedFiles,
      accumulatedAgentOutput,
      contextSummary,
      safety,
      runResult.fellBackFromCodex,
      runResult.fallbackReason,
    );
  }

  private async triggerReloadOrRestart(
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    risk: RiskAssessment,
  ): Promise<ReloadResult> {
    const label = risk.kind === 'restart' ? 'hot restart' : 'hot reload';
    emit('reload_started', `Triggering ${label}.`, { riskKind: risk.kind });
    const result =
      risk.kind === 'restart'
        ? await this.deps.reload.triggerRestart()
        : await this.deps.reload.triggerReload('');
    emit('reload_completed', result.reloadMessage, {
      reloadTriggered: result.reloadTriggered,
      reloadSucceeded: result.reloadSucceeded ?? result.reloadTriggered,
      hasErrors: Boolean(result.errorText),
    });
    return result;
  }

  private async triggerRestart(
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    reason: string,
  ): Promise<ReloadResult> {
    emit('reload_started', reason, { riskKind: 'full_rebuild' });
    const result = await this.deps.reload.triggerRestart();
    emit('reload_completed', result.reloadMessage, {
      reloadTriggered: result.reloadTriggered,
      reloadSucceeded: result.reloadSucceeded ?? result.reloadTriggered,
    });
    return result;
  }

  private async validateAndBackup(
    commandId: string,
    patches: FilePatch[],
    projectPath: string,
  ): Promise<void> {
    await this.deps.patchGuard.validate(patches, projectPath);
    await this.deps.patchGuard.backup(commandId, patches);
    await this.writePatches(commandId, patches);
  }

  private async writePatches(commandId: string, patches: FilePatch[]): Promise<void> {
    for (const patch of patches) {
      if (patch.before === patch.after) continue;
      await writeFile(patch.path, patch.after, 'utf8');
      console.log(`[command:${commandId}] wrote ${patch.relativePath}`);
    }
  }

  private async handleGuardFailure(
    commandId: string,
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    error: unknown,
    originalBefore: Map<string, { path: string; before: string }>,
    contextSummary: ContextSummary,
    agentOutput: string,
    safety: ReturnType<typeof evaluateInstruction>,
  ): Promise<CommandResponse> {
    if (error instanceof SafetyError) {
      const rollbackErrors = await this.rollbackToBaseline(originalBefore);
      if (rollbackErrors.length > 0) {
        emit('agent_log', `Rollback warnings: ${rollbackErrors.join('; ')}`);
      } else {
        emit('agent_log', 'Rolled back in-place edits to pre-command state.');
      }
      emit('safety_blocked', `Patch rejected: ${error.decision.reasons.join('; ')}`, {
        safety: error.decision,
      });
      const blockedResponse: CommandResponse = {
        success: false,
        commandId,
        message: `Generated patch was blocked by safety policy: ${error.decision.reasons.join('; ')}`,
        applied: false,
        reloadTriggered: false,
        changedFiles: [],
        agentOutput,
        contextSummary,
        safety: error.decision,
      };
      emit('failed', blockedResponse.message, { safety: error.decision });
      this.deps.sessionStore.setFinalResponse(commandId, blockedResponse);
      return blockedResponse;
    }
    return this.failWith(commandId, emit, error, 'Patch guard crashed.');
  }

  private finalizeNoop(
    commandId: string,
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    message: string,
    agentOutput: string,
    contextSummary: ContextSummary,
    safety: ReturnType<typeof evaluateInstruction>,
    fellBackFromCodex: boolean,
    fallbackReason?: string,
  ): CommandResponse {
    const response: CommandResponse = {
      success: true,
      commandId,
      message,
      applied: false,
      reloadTriggered: false,
      reloadMessage: 'No code change was applied, so reload was skipped.',
      changedFiles: [],
      agentOutput,
      contextSummary,
      safety,
    };
    if (fellBackFromCodex) {
      response.diagnostics = [
        { level: 'warning', message: `Codex adapter fell back to mock: ${fallbackReason}` },
      ];
    }
    emit('completed', message, { applied: false, reloadTriggered: false });
    this.deps.sessionStore.setFinalResponse(commandId, response);
    return response;
  }

  private finalizeSuccess(
    commandId: string,
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    reloadResult: ReloadResult,
    agentMessage: string,
    changedFiles: string[],
    agentOutput: string,
    contextSummary: ContextSummary,
    safety: ReturnType<typeof evaluateInstruction>,
    fellBackFromCodex: boolean,
    fallbackReason?: string,
  ): CommandResponse {
    const response: CommandResponse = {
      success: true,
      commandId,
      message: agentMessage,
      applied: true,
      reloadTriggered: reloadResult.reloadTriggered,
      reloadMessage: reloadResult.reloadMessage,
      changedFiles,
      agentOutput,
      contextSummary,
      safety,
    };
    if (fellBackFromCodex) {
      response.diagnostics = [
        { level: 'warning', message: `Codex adapter fell back to mock: ${fallbackReason}` },
      ];
    }
    emit('completed', agentMessage, {
      applied: true,
      reloadTriggered: reloadResult.reloadTriggered,
      changedFiles,
    });
    this.deps.sessionStore.setFinalResponse(commandId, response);
    return response;
  }

  private async requestApproval(
    commandId: string,
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    input: {
      risk: RiskAssessment;
      patches: FilePatch[];
      changedFiles: string[];
      agentOutput: string;
      contextSummary: ContextSummary;
    },
  ): Promise<ApprovalDecision> {
    const approvalId = `appr_${randomUUID().slice(0, 12)}`;
    return new Promise<ApprovalDecision>((resolve) => {
      const timer = setTimeout(() => {
        if (this.pending.delete(commandId)) {
          resolve({
            approvalId,
            decision: 'rejected',
            comment: `Approval timed out after ${Math.round(APPROVAL_TIMEOUT_MS / 1000)}s.`,
          });
        }
      }, APPROVAL_TIMEOUT_MS);

      const pending: PendingApproval = {
        commandId,
        approvalId,
        risk: input.risk,
        patches: input.patches,
        changedFiles: input.changedFiles,
        agentOutput: input.agentOutput,
        contextSummary: input.contextSummary,
        createdAt: new Date().toISOString(),
        resolve,
        timer,
      };
      this.pending.set(commandId, pending);

      const approvalRequest = this.buildApprovalRequest(pending);
      emit('approval_required', `User approval required: ${input.risk.reasons.join('; ')}`, {
        approvalRequest,
      });
    });
  }

  private buildApprovalRequest(pending: PendingApproval): ApprovalRequest {
    const diffPreview = pending.patches
      .slice(0, 3)
      .map((p) => `--- ${p.relativePath} (before)\n+++ ${p.relativePath} (after)\n${truncate(p.after, 400)}`)
      .join('\n\n');
    return {
      approvalId: pending.approvalId,
      title: 'High-risk change needs confirmation',
      summary: pending.risk.reasons.join(' '),
      changedFiles: pending.changedFiles,
      diffPreview,
      risks: pending.risk.reasons,
    };
  }

  private failWith(
    commandId: string,
    emit: (stage: CommandStage, message: string, payload?: Record<string, unknown>) => CommandEvent,
    error: unknown,
    contextMessage: string,
  ): CommandResponse {
    const message = error instanceof Error ? error.message : String(error);
    const fullMessage = `${contextMessage} ${message}`;
    console.error(`[command:${commandId}] ${fullMessage}`);
    const response: CommandResponse = {
      success: false,
      commandId,
      message: fullMessage,
      applied: false,
      reloadTriggered: false,
      changedFiles: [],
      agentOutput: '',
    };
    emit('failed', fullMessage);
    this.deps.sessionStore.setFinalResponse(commandId, response);
    return response;
  }

  private async rollbackPatches(patches: FilePatch[]): Promise<string[]> {
    const errors: string[] = [];
    for (const patch of patches) {
      if (patch.before === patch.after) continue;
      try {
        await writeFile(patch.path, patch.before, 'utf8');
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        errors.push(`${patch.relativePath}: ${message}`);
      }
    }
    return errors;
  }

  private async rollbackToBaseline(
    originalBefore: Map<string, { path: string; before: string }>,
  ): Promise<string[]> {
    const errors: string[] = [];
    for (const { path: filePath, before } of originalBefore.values()) {
      try {
        await writeFile(filePath, before, 'utf8');
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        errors.push(`${filePath}: ${message}`);
      }
    }
    return errors;
  }

  private recordEvent(
    commandId: string,
    sequence: number,
    stage: CommandStage,
    message: string,
    payload?: Record<string, unknown>,
  ): CommandEvent {
    const event: CommandEvent = {
      commandId,
      sequence,
      stage,
      message,
      timestamp: new Date().toISOString(),
      payload,
    };
    console.log(`[command:${commandId}] [${stage}] ${message}`);
    this.deps.sessionStore.appendEvent(commandId, event);
    return event;
  }
}

function summarizeSelection(request: CommandRequest): string | undefined {
  const sel = request.selection;
  if (!sel) return undefined;
  const parts: string[] = [sel.widget.widgetType];
  if (sel.widget.text) parts.push(`"${sel.widget.text}"`);
  if (sel.widget.key) parts.push(`key=${sel.widget.key}`);
  return parts.join(' ');
}

function mergeUnique(a: string[], b: string[]): string[] {
  const set = new Set(a);
  for (const item of b) set.add(item);
  return Array.from(set);
}

function truncate(text: string, limit: number): string {
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}\n... (truncated, ${text.length - limit} more chars)`;
}

function buildRepairContext(
  base: AgentContext,
  originalInstruction: string,
  errorText: string,
  attempt: number,
): AgentContext {
  const repairInstruction = [
    originalInstruction,
    '',
    `[Self-repair attempt ${attempt}]`,
    'The previous edit produced compile errors from `flutter run` hot reload.',
    'Fix ONLY the compile errors below while keeping the original intent.',
    'Do not introduce new files or change pubspec dependencies.',
    '',
    'Compile errors:',
    errorText,
  ].join('\n');
  return {
    ...base,
    instruction: repairInstruction,
  };
}
