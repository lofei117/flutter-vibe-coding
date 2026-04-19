export type ClientMeta = {
  platform?: string;
  appName?: string;
  selectedWidget?: unknown;
  interactionTrace?: unknown[];
};

export type CommandRequest = {
  instruction: string;
  projectPath?: string;
  clientMeta?: ClientMeta;
};

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

export type ReloadResult = {
  reloadTriggered: boolean;
  reloadMessage: string;
};
