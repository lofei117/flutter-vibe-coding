import { AgentService } from '../services/agent_service.ts';
import { FlutterReloadService } from '../services/flutter_reload_service.ts';
import { ProjectContextService } from '../services/project_context_service.ts';
import type { CommandRequest } from '../types/index.ts';

const projectContextService = new ProjectContextService();
const agentService = new AgentService();
const reloadService = new FlutterReloadService();

export async function handleCommand(rawBody: unknown): Promise<{
  statusCode: number;
  body: Record<string, unknown>;
}> {
  const body = rawBody as CommandRequest;
  const instruction = body.instruction?.trim();

  if (!instruction) {
    return {
      statusCode: 400,
      body: {
        success: false,
        message: 'instruction is required',
        applied: false,
        reloadTriggered: false,
      },
    };
  }

  try {
    console.log(`[command] instruction: ${instruction}`);
    console.log(`[command] clientMeta: ${JSON.stringify(body.clientMeta ?? {})}`);

    const context = await projectContextService.collect(body.projectPath);
    const patchResult = await agentService.applyInstruction(instruction, context);
    const reloadResult = patchResult.applied
      ? await reloadService.triggerReload(context.projectPath)
      : {
          reloadTriggered: false,
          reloadMessage: 'No code change was applied, so reload was skipped.',
        };

    console.log(`[command] changedFiles: ${patchResult.changedFiles.join(', ') || 'none'}`);
    console.log(`[command] reload: ${reloadResult.reloadMessage}`);

    return {
      statusCode: 200,
      body: {
        success: true,
        message: patchResult.message,
        applied: patchResult.applied,
        reloadTriggered: reloadResult.reloadTriggered,
        reloadMessage: reloadResult.reloadMessage,
        changedFiles: patchResult.changedFiles,
        agentOutput: patchResult.agentOutput,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[command] failed: ${message}`);
    return {
      statusCode: 500,
      body: {
        success: false,
        message,
        applied: false,
        reloadTriggered: false,
      },
    };
  }
}
