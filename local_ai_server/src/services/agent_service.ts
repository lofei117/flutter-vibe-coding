import { CodexAdapter } from '../adapters/codex_adapter.ts';
import { MockAgentAdapter } from '../adapters/mock_agent_adapter.ts';
import type {
  AgentContext,
  AgentPatchResult,
} from '../types/agent.ts';

export interface AgentAdapter {
  applyInstruction(context: AgentContext): Promise<AgentPatchResult>;
}

export type AdapterRunResult = {
  result: AgentPatchResult;
  adapterUsed: 'codex' | 'mock';
  fellBackFromCodex: boolean;
  fallbackReason?: string;
};

export class AgentService {
  private readonly mockAdapter: AgentAdapter;
  private readonly codexAdapter: AgentAdapter;

  constructor(options?: { mock?: AgentAdapter; codex?: AgentAdapter }) {
    this.mockAdapter = options?.mock ?? new MockAgentAdapter();
    this.codexAdapter = options?.codex ?? new CodexAdapter();
  }

  async run(context: AgentContext): Promise<AdapterRunResult> {
    const preferredAdapter = process.env.AGENT_ADAPTER ?? 'mock';
    if (preferredAdapter === 'codex') {
      try {
        const result = await this.codexAdapter.applyInstruction(context);
        return { result, adapterUsed: 'codex', fellBackFromCodex: false };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.warn(`[agent] codex adapter failed, falling back to mock: ${message}`);
        context.emit('agent_log', `Codex unavailable, falling back to mock: ${message}`);
        const result = await this.mockAdapter.applyInstruction(context);
        result.agentOutput = `Codex adapter failed: ${message}\n\nFallback mock output:\n${result.agentOutput}`;
        return {
          result,
          adapterUsed: 'mock',
          fellBackFromCodex: true,
          fallbackReason: message,
        };
      }
    }

    const result = await this.mockAdapter.applyInstruction(context);
    return { result, adapterUsed: 'mock', fellBackFromCodex: false };
  }
}
