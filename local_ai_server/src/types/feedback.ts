import type { ClientMeta } from './command.ts';
import type { Rect, RuntimeContext, SourceLocation } from './context.ts';

export type FeedbackTarget = {
  semanticId?: string;
  widgetKey?: string;
  text?: string;
  semanticLabel?: string;
  bounds?: Rect;
  sourceLocation?: SourceLocation;
};

export type FeedbackPageContext = {
  route?: string;
  pageId?: string;
  title?: string;
};

export type FeedbackScreenshot = {
  mimeType: 'image/png' | 'image/jpeg';
  /** Inline base64; preferred for MVP. */
  dataBase64?: string;
  /** Optional pre-uploaded path. */
  localPath?: string;
};

export type FeedbackTicketRequest = {
  instruction: string;
  clientMeta: ClientMeta;
  pageContext: FeedbackPageContext;
  target?: FeedbackTarget;
  screenshot?: FeedbackScreenshot;
  runtimeContext?: RuntimeContext;
};

export type FeedbackTicketStatus =
  | 'queued'
  | 'planned'
  | 'applied'
  | 'ci_running'
  | 'deployed'
  | 'failed';

export type LocalCiStepName =
  | 'analyze'
  | 'test'
  | 'build_web'
  | 'deploy_preview';

export type LocalCiStepStatus =
  | 'queued'
  | 'running'
  | 'passed'
  | 'failed'
  | 'skipped';

export type LocalCiStep = {
  name: LocalCiStepName;
  command: string;
  status: LocalCiStepStatus;
  startedAt?: string;
  finishedAt?: string;
  durationMs?: number;
  logSummary?: string;
  exitCode?: number;
};

export type LocalCiResult = {
  status: 'queued' | 'running' | 'passed' | 'failed';
  startedAt?: string;
  finishedAt?: string;
  steps: LocalCiStep[];
};

export type FeedbackTicketEventStage =
  | 'created'
  | 'processing_started'
  | 'agent_started'
  | 'patch_applied'
  | 'agent_failed'
  | 'ci_started'
  | 'ci_step_started'
  | 'ci_step_passed'
  | 'ci_step_failed'
  | 'ci_completed'
  | 'deploy_started'
  | 'deploy_completed'
  | 'deployed'
  | 'failed'
  | 'log';

export type FeedbackTicketEvent = {
  ticketId: string;
  sequence: number;
  stage: FeedbackTicketEventStage;
  message: string;
  timestamp: string;
  payload?: Record<string, unknown>;
};

export type FeedbackTicket = {
  ticketId: string;
  status: FeedbackTicketStatus;
  instruction: string;
  clientMeta: ClientMeta;
  pageContext: FeedbackPageContext;
  target?: FeedbackTarget;
  runtimeContext?: RuntimeContext;
  screenshotPath?: string;
  changedFiles: string[];
  agentOutput?: string;
  agentCommandId?: string;
  ci?: LocalCiResult;
  previewUrl?: string;
  failureReason?: string;
  events: FeedbackTicketEvent[];
  createdAt: string;
  updatedAt: string;
};
