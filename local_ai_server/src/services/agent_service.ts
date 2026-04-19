import { writeFile } from 'node:fs/promises';
import { CodexAdapter } from '../adapters/codex_adapter.ts';
import { MockAgentAdapter } from '../adapters/mock_agent_adapter.ts';
import type { AgentPatchResult, ProjectContext } from '../types/index.ts';

export interface AgentAdapter {
  applyInstruction(instruction: string, context: ProjectContext): Promise<AgentPatchResult>;
}

export class AgentService {
  private readonly mockAdapter = new MockAgentAdapter();
  private readonly codexAdapter = new CodexAdapter();

  async applyInstruction(instruction: string, context: ProjectContext): Promise<AgentPatchResult> {
    const preferredAdapter = process.env.AGENT_ADAPTER ?? 'mock';
    const adapter = preferredAdapter === 'codex' ? this.codexAdapter : this.mockAdapter;

    try {
      const result = await adapter.applyInstruction(instruction, context);
      await this.writePatches(result);
      return result;
    } catch (error) {
      if (preferredAdapter !== 'codex') {
        throw error;
      }

      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[agent] codex adapter failed, falling back to mock adapter: ${message}`);
      const result = await this.mockAdapter.applyInstruction(instruction, context);
      result.agentOutput = `Codex adapter failed: ${message}\n\nFallback mock output:\n${result.agentOutput}`;
      await this.writePatches(result);
      return result;
    }
  }

  private async writePatches(result: AgentPatchResult): Promise<void> {
    for (const patch of result.patches) {
      if (patch.before === patch.after) {
        continue;
      }
      await writeFile(patch.path, patch.after, 'utf8');
      console.log(`[agent] wrote ${patch.relativePath}`);
    }
  }
}
