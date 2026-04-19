import { spawn } from 'node:child_process';
import type { ReloadResult } from '../types/agent.ts';
import type { AppSessionManager } from './app_session_manager.ts';
import { ensureSafeShellCommand } from './command_allowlist.ts';

export class FlutterReloadService {
  private readonly appSessions: AppSessionManager;

  constructor(appSessions: AppSessionManager) {
    this.appSessions = appSessions;
  }

  async triggerReload(projectPath: string): Promise<ReloadResult> {
    if (this.appSessions.hasManagedRunning()) {
      const result = await this.appSessions.signalCurrentReload();
      return {
        reloadTriggered: true,
        reloadSucceeded: result.ok,
        reloadMessage: result.message,
        errorText: result.errorText,
        output: result.output,
      };
    }

    const reloadCommand = process.env.FLUTTER_RELOAD_COMMAND;
    if (reloadCommand) {
      try {
        ensureSafeShellCommand(reloadCommand);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          reloadTriggered: false,
          reloadMessage: `FLUTTER_RELOAD_COMMAND rejected by allowlist: ${message}`,
        };
      }
      return runReloadCommand(reloadCommand, projectPath);
    }

    return {
      reloadTriggered: false,
      reloadMessage:
        'Code was changed. No managed flutter run process is attached, so press "r" in your flutter run terminal.',
    };
  }

  async triggerRestart(): Promise<ReloadResult> {
    if (this.appSessions.hasManagedRunning()) {
      const result = await this.appSessions.signalCurrentRestart();
      return {
        reloadTriggered: true,
        reloadSucceeded: result.ok,
        reloadMessage: result.message,
        errorText: result.errorText,
        output: result.output,
      };
    }
    return {
      reloadTriggered: false,
      reloadMessage:
        'Code was changed. No managed flutter run process is attached; please restart flutter run yourself.',
    };
  }
}

function runReloadCommand(command: string, cwd: string): Promise<ReloadResult> {
  return new Promise((resolve) => {
    const child = spawn(command, {
      cwd,
      shell: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env,
    });

    let output = '';
    child.stdout.on('data', (chunk) => {
      output += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      output += chunk.toString();
    });
    child.on('close', (code) => {
      resolve({
        reloadTriggered: code === 0,
        reloadSucceeded: code === 0,
        reloadMessage:
          code === 0
            ? `FLUTTER_RELOAD_COMMAND completed. ${output.trim()}`
            : `FLUTTER_RELOAD_COMMAND exited with ${code}. ${output.trim()}`,
        output,
      });
    });
  });
}
