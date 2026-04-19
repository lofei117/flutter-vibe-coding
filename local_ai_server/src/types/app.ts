export type AppTarget = 'chrome' | 'android' | 'ios' | 'macos';

export type StartAppRequest = {
  projectPath?: string;
  target: AppTarget;
  deviceId?: string;
  mode?: 'debug';
};

export type StartAppResponse = {
  success: boolean;
  appSessionId?: string;
  message: string;
  launchUrl?: string;
  logs?: string[];
};

export type AppSession = {
  appSessionId: string;
  target: AppTarget;
  deviceId?: string;
  projectPath: string;
  pid: number;
  startedAt: string;
  launchUrl?: string;
  status: 'starting' | 'running' | 'exited';
  exitCode?: number | null;
};
