import type {
  RuntimeContext,
  SelectedComponentContext,
} from './context.ts';
import type { CommandStage } from './command.ts';

export type ProjectFile = {
  path: string;
  relativePath: string;
  content: string;
};

export type ProjectContext = {
  projectPath: string;
  files: ProjectFile[];
};

export type FilePatch = {
  path: string;
  relativePath: string;
  before: string;
  after: string;
};

export type AgentPatchResult = {
  applied: boolean;
  message: string;
  changedFiles: string[];
  patches: FilePatch[];
  agentOutput: string;
};

export type AgentEmit = (
  stage: CommandStage,
  message: string,
  payload?: Record<string, unknown>,
) => void;

export type AgentContext = {
  instruction: string;
  selection?: SelectedComponentContext;
  runtimeContext?: RuntimeContext;
  candidateFiles: ProjectFile[];
  snippet?: {
    file: string;
    startLine: number;
    endLine: number;
    content: string;
  };
  project: ProjectContext;
  emit: AgentEmit;
};

export type ReloadResult = {
  reloadTriggered: boolean;
  reloadMessage: string;
  /** True if a reload/restart signal was sent AND succeeded (e.g. "Reloaded N libraries"). */
  reloadSucceeded?: boolean;
  /** Raw compile/runtime error text extracted from the flutter run output, if any. */
  errorText?: string;
  /** Raw output captured during reload (truncated). */
  output?: string;
};
