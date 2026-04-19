import type {
  RuntimeContext,
  SelectedComponentContext,
} from './context.ts';
import type {
  ApprovalDecision,
  ApprovalRequest,
  SafetyDecision,
} from './safety.ts';

export type ClientMeta = {
  platform?: 'flutter' | string;
  appName?: string;
  appVersion?: string;
  runtimeTarget?: 'web' | 'android' | 'ios' | 'macos' | 'unknown';
  debugMode?: boolean;
  umePluginVersion?: string;
  serverUrl?: string;
  appLaunchMode?: 'server-managed' | 'manual';
  // Legacy fields kept for backward compatibility with the very first thin spike.
  selectedWidget?: unknown;
  interactionTrace?: unknown[];
};

export type ConversationContext = {
  sessionId?: string;
  turnId?: string;
  previousTurns?: Array<{
    role: 'user' | 'agent' | 'system';
    text: string;
    createdAt?: string;
  }>;
};

export type CommandRequest = {
  instruction: string;
  projectPath?: string;
  appSessionId?: string;
  sessionId?: string;
  clientMeta?: ClientMeta;
  selection?: SelectedComponentContext;
  runtimeContext?: RuntimeContext;
  conversation?: ConversationContext;
  approvalDecision?: ApprovalDecision;
};

export type ContextSummary = {
  selectedWidget?: string;
  selectedText?: string;
  sourceLocationStatus?: 'available' | 'unavailable' | 'missing';
  candidateFiles: string[];
};

export type CommandDiagnostic = {
  level: 'info' | 'warning' | 'error';
  message: string;
};

export type CommandResponse = {
  success: boolean;
  commandId?: string;
  message: string;
  applied: boolean;
  reloadTriggered: boolean;
  reloadMessage?: string;
  changedFiles: string[];
  agentOutput: string;
  contextSummary?: ContextSummary;
  diagnostics?: CommandDiagnostic[];
  requiresApproval?: boolean;
  approvalRequest?: ApprovalRequest;
  safety?: SafetyDecision;
};

export type CommandStage =
  | 'queued'
  | 'context_collected'
  | 'safety_checked'
  | 'safety_blocked'
  | 'agent_started'
  | 'agent_log'
  | 'patch_generated'
  | 'patch_applied'
  | 'reload_started'
  | 'reload_completed'
  | 'approval_required'
  | 'completed'
  | 'failed';

export type CommandEvent = {
  commandId: string;
  sequence: number;
  stage: CommandStage;
  message: string;
  timestamp: string;
  payload?: Record<string, unknown>;
};
