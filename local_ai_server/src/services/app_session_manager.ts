import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import type {
  AppSession,
  AppTarget,
  StartAppRequest,
  StartAppResponse,
} from '../types/app.ts';
import { ensureAllowedBinary } from './command_allowlist.ts';
import { ProjectContextService } from './project_context_service.ts';

const MAX_LOG_LINES = 200;
const LAUNCH_URL_REGEX = /(https?:\/\/[\w.\-:/]+)/i;
const RELOAD_TIMEOUT_MS = 8000;
const RESTART_TIMEOUT_MS = 15000;

const RELOAD_SUCCESS_REGEX = /Reloaded\s+\d+\s+(libraries?|of\s+\d+\s+libraries?)/i;
const RESTART_SUCCESS_REGEX = /Restarted application in\s+\d+/i;
const RELOAD_FAIL_REGEX =
  /(Hot reload (?:was |)rejected|Hot reload (?:was |)aborted|Hot reload failed|Try performing a hot restart|Hot restart failed|Unable to hot reload|Recompile complete\. \d+ errors)/i;
const DART_COMPILE_ERROR_REGEX = /^(?:[^\s].*?):\s*(?:Error:|error:)\s+/;

type LogListener = (line: string) => void;

type ManagedSession = {
  session: AppSession;
  process: ChildProcessWithoutNullStreams;
  logs: string[];
  logListeners: Set<LogListener>;
};

export type ReloadOutcome = {
  ok: boolean;
  message: string;
  output: string;
  errorText?: string;
};

export class AppSessionManager {
  private current: ManagedSession | null = null;
  private readonly projects: ProjectContextService;

  constructor(projects: ProjectContextService) {
    this.projects = projects;
  }

  async start(request: StartAppRequest): Promise<StartAppResponse> {
    if (
      this.current &&
      (this.current.session.status === 'running' ||
        this.current.session.status === 'starting')
    ) {
      return {
        success: false,
        message: `An app session ${this.current.session.appSessionId} is already ${this.current.session.status}. Stop it first.`,
        appSessionId: this.current.session.appSessionId,
        launchUrl: this.current.session.launchUrl,
        logs: this.current.logs.slice(-20),
      };
    }

    const target = (request.target ?? 'chrome') as AppTarget;
    const projectPath = this.projects.resolveProjectPath(request.projectPath);
    const args = ['--no-version-check', 'run'];
    if (target === 'chrome') {
      args.push('-d', 'chrome');
    } else if (request.deviceId) {
      args.push('-d', request.deviceId);
    } else {
      args.push('-d', target);
    }

    ensureAllowedBinary('flutter');

    console.log(`[app] starting flutter ${args.join(' ')} in ${projectPath}`);
    const child = spawn('flutter', args, {
      cwd: projectPath,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });

    const sessionId = `app_${target}_${randomUUID().slice(0, 8)}`;
    const session: AppSession = {
      appSessionId: sessionId,
      target,
      deviceId: request.deviceId,
      projectPath,
      pid: child.pid ?? -1,
      startedAt: new Date().toISOString(),
      status: 'starting',
    };
    const managed: ManagedSession = {
      session,
      process: child,
      logs: [],
      logListeners: new Set(),
    };
    this.current = managed;

    child.stdout.on('data', (chunk) => {
      this.appendLog(managed, chunk.toString(), 'stdout');
    });
    child.stderr.on('data', (chunk) => {
      this.appendLog(managed, chunk.toString(), 'stderr');
    });
    child.on('exit', (code) => {
      managed.session.status = 'exited';
      managed.session.exitCode = code;
      console.log(`[app] flutter run exited with ${code}`);
    });
    child.on('error', (error) => {
      console.error(`[app] flutter run failed: ${error.message}`);
      managed.session.status = 'exited';
      managed.session.exitCode = -1;
    });

    return {
      success: true,
      appSessionId: sessionId,
      message: 'flutter run started; tail logs via /app/session.',
      launchUrl: undefined,
      logs: [],
    };
  }

  getCurrent(): { session: AppSession; logs: string[] } | null {
    if (!this.current) return null;
    return {
      session: this.current.session,
      logs: this.current.logs.slice(),
    };
  }

  async reload(appSessionId: string): Promise<ReloadOutcome> {
    return this.signal(appSessionId, 'r', 'hot reload', RELOAD_TIMEOUT_MS, RELOAD_SUCCESS_REGEX);
  }

  async restart(appSessionId: string): Promise<ReloadOutcome> {
    return this.signal(appSessionId, 'R', 'hot restart', RESTART_TIMEOUT_MS, RESTART_SUCCESS_REGEX);
  }

  async stop(appSessionId: string): Promise<{ ok: boolean; message: string }> {
    if (!this.current || this.current.session.appSessionId !== appSessionId) {
      return { ok: false, message: `App session ${appSessionId} not found.` };
    }
    const managed = this.current;
    if (managed.session.status === 'exited') {
      this.current = null;
      return { ok: true, message: 'App session already exited.' };
    }
    if (managed.process.stdin.writable) {
      managed.process.stdin.write('q');
    }
    managed.process.kill('SIGTERM');
    managed.session.status = 'exited';
    this.current = null;
    return { ok: true, message: 'App session stop signal sent.' };
  }

  hasManagedRunning(): boolean {
    return this.current?.session.status === 'running' || this.current?.session.status === 'starting';
  }

  async signalCurrentReload(): Promise<ReloadOutcome> {
    if (!this.current) {
      return { ok: false, message: 'No managed flutter app session.', output: '' };
    }
    return this.reload(this.current.session.appSessionId);
  }

  async signalCurrentRestart(): Promise<ReloadOutcome> {
    if (!this.current) {
      return { ok: false, message: 'No managed flutter app session.', output: '' };
    }
    return this.restart(this.current.session.appSessionId);
  }

  private async signal(
    appSessionId: string,
    key: 'r' | 'R',
    label: string,
    timeoutMs: number,
    successRegex: RegExp,
  ): Promise<ReloadOutcome> {
    const managed = this.current;
    if (!managed || managed.session.appSessionId !== appSessionId) {
      return { ok: false, message: `App session ${appSessionId} not found.`, output: '' };
    }
    if (!managed.process.stdin.writable) {
      return { ok: false, message: 'flutter run stdin is not writable.', output: '' };
    }

    return await new Promise<ReloadOutcome>((resolve) => {
      const collected: string[] = [];
      const errorLines: string[] = [];
      let settled = false;

      const listener: LogListener = (line) => {
        collected.push(line);
        if (DART_COMPILE_ERROR_REGEX.test(stripStreamPrefix(line))) {
          errorLines.push(stripStreamPrefix(line));
        }
        if (successRegex.test(line)) {
          finish({
            ok: true,
            message: `${label} succeeded.`,
            output: collected.join('\n'),
          });
          return;
        }
        if (RELOAD_FAIL_REGEX.test(line)) {
          finish({
            ok: false,
            message: `${label} reported failure.`,
            output: collected.join('\n'),
            errorText: buildErrorText(errorLines, collected),
          });
        }
      };

      const finish = (outcome: ReloadOutcome) => {
        if (settled) return;
        settled = true;
        managed.logListeners.delete(listener);
        clearTimeout(timer);
        resolve(outcome);
      };

      managed.logListeners.add(listener);
      managed.process.stdin.write(key);

      const timer = setTimeout(() => {
        finish({
          ok: errorLines.length === 0,
          message:
            errorLines.length > 0
              ? `${label} timed out with compile errors.`
              : `${label} did not emit a result within ${timeoutMs}ms.`,
          output: collected.join('\n'),
          errorText:
            errorLines.length > 0 ? buildErrorText(errorLines, collected) : undefined,
        });
      }, timeoutMs);
    });
  }

  private appendLog(
    managed: ManagedSession,
    text: string,
    stream: 'stdout' | 'stderr',
  ): void {
    for (const line of text.split(/\r?\n/)) {
      if (!line) continue;
      const tagged = `[${stream}] ${line}`;
      managed.logs.push(tagged);
      if (managed.logs.length > MAX_LOG_LINES) {
        managed.logs.shift();
      }
      process.stdout.write(`[flutter] ${line}\n`);

      if (managed.session.status === 'starting' && /to quit, press "q"|Flutter run key commands/i.test(line)) {
        managed.session.status = 'running';
      }
      if (!managed.session.launchUrl) {
        const match = line.match(LAUNCH_URL_REGEX);
        if (match && /serv|debug|launch|local|chrome/i.test(line)) {
          managed.session.launchUrl = match[1];
        }
      }

      for (const listener of managed.logListeners) {
        try {
          listener(tagged);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          console.warn(`[app] log listener error: ${msg}`);
        }
      }
    }
  }
}

function stripStreamPrefix(line: string): string {
  return line.replace(/^\[(stdout|stderr)\]\s*/, '');
}

function buildErrorText(errorLines: string[], allLines: string[]): string {
  if (errorLines.length > 0) {
    return errorLines.slice(0, 12).join('\n');
  }
  return allLines.slice(-12).join('\n');
}

let singleton: AppSessionManager | null = null;

export function getAppSessionManager(
  projects: ProjectContextService,
): AppSessionManager {
  if (!singleton) {
    singleton = new AppSessionManager(projects);
  }
  return singleton;
}
