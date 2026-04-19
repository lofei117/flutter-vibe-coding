import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import type { ReloadResult } from '../types/index.ts';

export class FlutterReloadService {
  private flutterRunProcess: ChildProcessWithoutNullStreams | null = null;

  constructor() {
    if (process.env.AUTO_START_FLUTTER === 'true') {
      this.startManagedFlutterRun();
    }
  }

  async triggerReload(projectPath: string): Promise<ReloadResult> {
    if (this.flutterRunProcess?.stdin.writable) {
      this.flutterRunProcess.stdin.write('r');
      return {
        reloadTriggered: true,
        reloadMessage: 'Sent hot reload command "r" to the managed flutter run process.',
      };
    }

    const reloadCommand = process.env.FLUTTER_RELOAD_COMMAND;
    if (reloadCommand) {
      return runReloadCommand(reloadCommand, projectPath);
    }

    return {
      reloadTriggered: false,
      reloadMessage:
        'Code was changed. No managed flutter run process is attached, so press "r" in your flutter run terminal.',
    };
  }

  private startManagedFlutterRun(): void {
    const projectPath = process.env.FLUTTER_PROJECT_PATH;
    if (!projectPath) {
      console.warn('[reload] AUTO_START_FLUTTER=true requires FLUTTER_PROJECT_PATH.');
      return;
    }

    const args = ['run'];
    if (process.env.FLUTTER_DEVICE_ID) {
      args.push('-d', process.env.FLUTTER_DEVICE_ID);
    }

    console.log(`[reload] starting managed flutter ${args.join(' ')} in ${projectPath}`);
    this.flutterRunProcess = spawn('flutter', args, {
      cwd: projectPath,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });

    this.flutterRunProcess.stdout.on('data', (chunk) => {
      process.stdout.write(`[flutter] ${chunk}`);
    });
    this.flutterRunProcess.stderr.on('data', (chunk) => {
      process.stderr.write(`[flutter] ${chunk}`);
    });
    this.flutterRunProcess.on('exit', (code) => {
      console.log(`[reload] managed flutter run exited with ${code}`);
      this.flutterRunProcess = null;
    });
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
        reloadMessage:
          code === 0
            ? `FLUTTER_RELOAD_COMMAND completed. ${output.trim()}`
            : `FLUTTER_RELOAD_COMMAND exited with ${code}. ${output.trim()}`,
      });
    });
  });
}
