import { spawn } from 'node:child_process';
import path from 'node:path';
import { ensureSafeShellCommand } from './command_allowlist.ts';
import type {
  LocalCiResult,
  LocalCiStep,
  LocalCiStepName,
} from '../types/feedback.ts';

const DEFAULT_FLUTTER_BIN = process.env.FLUTTER_BIN ?? 'flutter';
const DEFAULT_BUILD_FLAVOR = process.env.LOCAL_CI_BUILD_FLAVOR ?? 'release';
const STEP_TIMEOUT_MS = Number(process.env.LOCAL_CI_STEP_TIMEOUT_MS ?? 10 * 60 * 1000);
const LOG_TAIL_BYTES = Number(process.env.LOCAL_CI_LOG_TAIL_BYTES ?? 8 * 1024);
const SKIP_TESTS = process.env.LOCAL_CI_SKIP_TESTS === '1';
export type CiStepEvent =
  | { type: 'step_started'; step: LocalCiStep }
  | { type: 'step_passed'; step: LocalCiStep }
  | { type: 'step_failed'; step: LocalCiStep };

export type CiOptions = {
  /** Skip running `flutter test`; useful when the demo project has no tests. */
  skipTests?: boolean;
  /** profile or release; defaults from env. */
  buildFlavor?: 'profile' | 'release';
  /** Called when a step starts/passes/fails so the caller can broadcast. */
  onStepEvent?: (event: CiStepEvent) => void;
};

export class LocalCiRunner {
  /**
   * Runs the minimal local CI pipeline:
   *   1. flutter analyze
   *   2. flutter test (optional)
   *   3. flutter build web --<flavor> --base-href /
   *
   * The `deploy_preview` step is run separately by the publisher.
   */
  async run(projectPath: string, options: CiOptions = {}): Promise<LocalCiResult> {
    const flavor = options.buildFlavor ?? (DEFAULT_BUILD_FLAVOR as 'profile' | 'release');
    const skipTests = options.skipTests ?? SKIP_TESTS;

    const stepDefs: Array<{ name: LocalCiStepName; cmd: string; skipped?: boolean }> = [
      { name: 'analyze', cmd: `${DEFAULT_FLUTTER_BIN} analyze --no-fatal-infos --no-fatal-warnings` },
      { name: 'test', cmd: `${DEFAULT_FLUTTER_BIN} test`, skipped: skipTests },
      {
        name: 'build_web',
        cmd: `${DEFAULT_FLUTTER_BIN} build web --${flavor} --base-href /`,
      },
    ];

    const result: LocalCiResult = {
      status: 'running',
      startedAt: new Date().toISOString(),
      steps: stepDefs.map(({ name, cmd, skipped }) => ({
        name,
        command: cmd,
        status: skipped ? 'skipped' : 'queued',
      })),
    };

    for (let i = 0; i < stepDefs.length; i += 1) {
      const def = stepDefs[i];
      const step = result.steps[i];
      if (step.status === 'skipped') continue;

      try {
        ensureSafeShellCommand(def.cmd);
      } catch (error) {
        step.status = 'failed';
        step.logSummary = `Command rejected by allowlist: ${(error as Error).message}`;
        options.onStepEvent?.({ type: 'step_failed', step });
        result.status = 'failed';
        result.finishedAt = new Date().toISOString();
        return result;
      }

      step.status = 'running';
      step.startedAt = new Date().toISOString();
      options.onStepEvent?.({ type: 'step_started', step });

      const exec = await runShell(def.cmd, projectPath);
      step.finishedAt = new Date().toISOString();
      step.durationMs = exec.durationMs;
      step.exitCode = exec.exitCode;
      step.logSummary = tailLog(exec.combined, LOG_TAIL_BYTES);

      if (exec.exitCode === 0) {
        step.status = 'passed';
        options.onStepEvent?.({ type: 'step_passed', step });
      } else {
        step.status = 'failed';
        options.onStepEvent?.({ type: 'step_failed', step });
        result.status = 'failed';
        result.finishedAt = new Date().toISOString();
        return result;
      }
    }

    result.status = 'passed';
    result.finishedAt = new Date().toISOString();
    return result;
  }
}

type ShellExecResult = {
  exitCode: number;
  combined: string;
  durationMs: number;
};

function runShell(command: string, cwd: string): Promise<ShellExecResult> {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(command, {
      cwd: path.resolve(cwd),
      shell: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env,
    });

    let combined = '';
    const pushChunk = (chunk: Buffer | string) => {
      const str = chunk.toString();
      combined += str;
      // Cap raw buffer to avoid uncontrolled memory growth on long builds.
      const cap = 1 * 1024 * 1024;
      if (combined.length > cap) combined = combined.slice(-cap);
    };
    child.stdout.on('data', pushChunk);
    child.stderr.on('data', pushChunk);

    const timer = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      combined += `\n[ci] timeout after ${STEP_TIMEOUT_MS}ms; killed.`;
    }, STEP_TIMEOUT_MS);

    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        exitCode: code ?? -1,
        combined,
        durationMs: Date.now() - startedAt,
      });
    });
    child.on('error', (error) => {
      clearTimeout(timer);
      combined += `\n[ci] spawn error: ${error.message}`;
      resolve({
        exitCode: -1,
        combined,
        durationMs: Date.now() - startedAt,
      });
    });
  });
}

function tailLog(text: string, maxBytes: number): string {
  if (Buffer.byteLength(text, 'utf8') <= maxBytes) return text;
  // Take roughly the last `maxBytes` worth of characters (1 byte per char approx.).
  const sliced = text.slice(-maxBytes);
  return `... (truncated)\n${sliced}`;
}
