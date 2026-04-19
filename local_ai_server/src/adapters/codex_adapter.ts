import { spawn } from 'node:child_process';
import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { ensureAllowedBinary, ensureSafeShellCommand } from '../services/command_allowlist.ts';
import type { AgentAdapter } from '../services/agent_service.ts';
import type {
  AgentContext,
  AgentEmit,
  AgentPatchResult,
} from '../types/agent.ts';

const IGNORED_DIRS = new Set([
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'Pods',
  'node_modules',
]);

const TRACKED_EXTENSIONS = new Set([
  '.dart',
  '.gradle',
  '.json',
  '.kt',
  '.lock',
  '.md',
  '.plist',
  '.properties',
  '.swift',
  '.txt',
  '.xml',
  '.yaml',
  '.yml',
]);

const MAX_TRACKED_FILE_BYTES = 512 * 1024;

/**
 * Codex adapter: directly edits the real project for fast feedback.
 *
 * Trade-off (intentional): codex modifies the real project files in place. The
 * orchestrator still runs patch_guard.validate() AFTER the edit by diffing
 * before/after snapshots; if guard fails, the orchestrator rolls back using the
 * before snapshot. This avoids the overhead of copying the whole Flutter
 * project on every request.
 *
 * TODO(HITL): For high-risk edits (large diff, non-lib files, hot-restart-only
 * changes) emit a confirmation event and pause until the user approves. Not
 * implemented in this iteration.
 */
export class CodexAdapter implements AgentAdapter {
  async applyInstruction(context: AgentContext): Promise<AgentPatchResult> {
    const projectPath = context.project.projectPath;
    const before = await snapshotProject(projectPath);
    const prompt = buildPrompt(context, projectPath);

    console.log('[codex] prompt begin');
    console.log(prompt);
    console.log('[codex] prompt end');
    context.emit('agent_log', 'Codex prompt prepared.');

    const output = process.env.CODEX_COMMAND
      ? await runShellCommand(process.env.CODEX_COMMAND, prompt, projectPath, context.emit)
      : await runCodexExec(prompt, projectPath, context.emit);

    const after = await snapshotProject(projectPath);
    const changedRelativePaths = diffSnapshots(before, after);
    const applied = changedRelativePaths.length > 0;

    const patches = changedRelativePaths.map((relativePath) => ({
      path: path.join(projectPath, relativePath),
      relativePath,
      before: before.get(relativePath) ?? '',
      after: after.get(relativePath) ?? '',
    }));

    if (applied) {
      context.emit('patch_generated', `Codex modified ${patches.length} file(s).`, {
        files: changedRelativePaths,
      });
    }

    return {
      applied,
      message: applied
        ? 'Codex applied the instruction.'
        : 'Codex completed, but no tracked project files changed.',
      changedFiles: changedRelativePaths,
      patches,
      agentOutput: output,
    };
  }
}

function buildPrompt(context: AgentContext, workspacePath: string): string {
  const lines: string[] = [
    'You are Codex running from a local HTTP bridge for a Flutter vibe-coding demo.',
    `Project path: ${workspacePath}`,
    '',
    'Task:',
    `Instruction: ${context.instruction}`,
    '',
  ];

  if (context.selection) {
    const w = context.selection.widget;
    lines.push('Selected component:');
    lines.push(`- widgetType: ${w.widgetType}`);
    if (w.key) lines.push(`- key: ${w.key}`);
    if (w.text) lines.push(`- text: ${w.text}`);
    if (w.semanticLabel) lines.push(`- semanticLabel: ${w.semanticLabel}`);
    if (context.selection.sourceLocation.status === 'available') {
      const loc = context.selection.sourceLocation;
      lines.push(`- sourceLocation: ${loc.file}:${loc.line}${loc.column ? ':' + loc.column : ''}`);
      if (loc.className) lines.push(`- className: ${loc.className}`);
      if (loc.methodName) lines.push(`- methodName: ${loc.methodName}`);
    } else {
      lines.push(`- sourceLocation: unavailable (${context.selection.sourceLocation.reason})`);
    }
    if (context.selection.codeContext?.candidateSymbols?.length) {
      lines.push(
        `- candidateSymbols: ${context.selection.codeContext.candidateSymbols.join(', ')}`,
      );
    }
    lines.push('');
  } else {
    lines.push('Selected component: none (legacy thin request).');
    lines.push('');
  }

  if (context.candidateFiles.length > 0) {
    lines.push('Candidate files (read these first):');
    for (const file of context.candidateFiles) {
      lines.push(`- ${file.relativePath}`);
    }
    lines.push('');
  }

  if (context.snippet) {
    lines.push(`Source snippet around selection (${context.snippet.file}:${context.snippet.startLine}-${context.snippet.endLine}):`);
    lines.push('```dart');
    lines.push(context.snippet.content);
    lines.push('```');
    lines.push('');
  }

  if (context.runtimeContext?.currentRoute) {
    lines.push(`Current route: ${context.runtimeContext.currentRoute}`);
  }

  lines.push('Rules:');
  lines.push('- Edit files inside the project path only. Do not touch any path outside it.');
  lines.push('- Make the minimum code changes needed.');
  lines.push('- Prefer the existing Flutter and Dart style in this project.');
  lines.push('- Do not start long-running dev servers.');
  lines.push('- When finished, briefly summarize what changed and mention any checks you ran.');

  return lines.join('\n');
}

function runCodexExec(stdin: string, cwd: string, emit: AgentEmit): Promise<string> {
  const bin = process.env.CODEX_BIN ?? 'codex';
  ensureAllowedBinary(bin);
  const args = [
    'exec',
    '--full-auto',
    '--skip-git-repo-check',
    '--cd',
    cwd,
    '-',
  ];

  if (process.env.CODEX_MODEL) {
    args.splice(1, 0, '--model', process.env.CODEX_MODEL);
  }

  if (process.env.CODEX_PROFILE) {
    args.splice(1, 0, '--profile', process.env.CODEX_PROFILE);
  }

  console.log(`[codex] starting: ${formatCommand(bin, args)}`);
  return runCommand(bin, args, stdin, cwd, false, emit);
}

function runShellCommand(
  command: string,
  stdin: string,
  cwd: string,
  emit: AgentEmit,
): Promise<string> {
  ensureSafeShellCommand(command);
  console.log(`[codex] starting shell command: ${command}`);
  return runCommand(command, [], stdin, cwd, true, emit);
}

function runCommand(
  command: string,
  args: string[],
  stdin: string,
  cwd: string,
  shell: boolean,
  emit: AgentEmit,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      shell,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      const text = chunk.toString();
      stdout += text;
      writeProcessOutput('stdout', text, emit);
    });
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString();
      stderr += text;
      writeProcessOutput('stderr', text, emit);
    });
    child.on('error', (error) => {
      console.error(`[codex] failed to start: ${error.message}`);
      reject(error);
    });
    child.on('close', (code) => {
      const output = [stdout.trim(), stderr.trim()].filter(Boolean).join('\n');
      if (code === 0) {
        console.log('[codex] completed successfully');
        resolve(output);
      } else {
        console.error(`[codex] exited with ${code}`);
        reject(new Error(`Codex command exited with ${code}: ${output}`));
      }
    });

    child.stdin.write(stdin);
    child.stdin.end();
  });
}

function writeProcessOutput(
  stream: 'stdout' | 'stderr',
  text: string,
  emit: AgentEmit,
): void {
  for (const line of text.split(/\r?\n/)) {
    if (line.length === 0) continue;
    console.log(`[codex:${stream}] ${line}`);
    emit('agent_log', line, { stream });
  }
}

function formatCommand(command: string, args: string[]): string {
  return [command, ...args].map(quoteArg).join(' ');
}

function quoteArg(arg: string): string {
  if (/^[a-zA-Z0-9_./:=@-]+$/.test(arg)) {
    return arg;
  }
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

type FileSnapshot = Map<string, string>;

async function snapshotProject(projectPath: string): Promise<FileSnapshot> {
  const snapshot: FileSnapshot = new Map();
  await collectSnapshotFiles(projectPath, projectPath, snapshot);
  return snapshot;
}

async function collectSnapshotFiles(
  root: string,
  current: string,
  snapshot: FileSnapshot,
): Promise<void> {
  let entries;
  try {
    entries = await readdir(current, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!IGNORED_DIRS.has(entry.name)) {
        await collectSnapshotFiles(root, path.join(current, entry.name), snapshot);
      }
      continue;
    }

    if (!entry.isFile()) {
      continue;
    }

    const fullPath = path.join(current, entry.name);
    const relativePath = path.relative(root, fullPath);
    if (!shouldTrackFile(fullPath)) {
      continue;
    }

    try {
      const fileStat = await stat(fullPath);
      if (fileStat.size > MAX_TRACKED_FILE_BYTES) {
        continue;
      }
      snapshot.set(relativePath, await readFile(fullPath, 'utf8'));
    } catch {
      // Files may disappear while Codex is editing. The next snapshot will catch the final state.
    }
  }
}

function shouldTrackFile(filePath: string): boolean {
  const extension = path.extname(filePath);
  return TRACKED_EXTENSIONS.has(extension);
}

function diffSnapshots(before: FileSnapshot, after: FileSnapshot): string[] {
  const changed = new Set<string>();

  for (const [relativePath, beforeContent] of before) {
    if (!after.has(relativePath) || after.get(relativePath) !== beforeContent) {
      changed.add(relativePath);
    }
  }

  for (const relativePath of after.keys()) {
    if (!before.has(relativePath)) {
      changed.add(relativePath);
    }
  }

  return [...changed].sort();
}
