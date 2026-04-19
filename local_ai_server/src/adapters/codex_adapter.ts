import { spawn } from 'node:child_process';
import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import type { AgentAdapter } from '../services/agent_service.ts';
import type { AgentPatchResult, ProjectContext } from '../types/index.ts';

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

export class CodexAdapter implements AgentAdapter {
  async applyInstruction(instruction: string, context: ProjectContext): Promise<AgentPatchResult> {
    const before = await snapshotProject(context.projectPath);
    const prompt = [
      'You are Codex running from a local HTTP bridge for a Flutter vibe-coding demo.',
      `Project path: ${context.projectPath}`,
      '',
      'Task:',
      `Instruction: ${instruction}`,
      '',
      'Rules:',
      '- Edit files directly in the project path.',
      '- Make the minimum code changes needed.',
      '- Prefer the existing Flutter and Dart style in this project.',
      '- Do not start long-running dev servers.',
      '- When finished, briefly summarize what changed and mention any checks you ran.',
    ].join('\n');

    console.log('[codex] prompt begin');
    console.log(prompt);
    console.log('[codex] prompt end');

    const output = process.env.CODEX_COMMAND
      ? await runShellCommand(process.env.CODEX_COMMAND, prompt, context.projectPath)
      : await runCodexExec(prompt, context.projectPath);
    const after = await snapshotProject(context.projectPath);
    const changedFiles = diffSnapshots(before, after);
    const applied = changedFiles.length > 0;

    return {
      applied,
      message: applied
        ? 'Codex applied the instruction.'
        : 'Codex completed, but no tracked project files changed.',
      changedFiles,
      patches: [],
      agentOutput: output,
    };
  }
}

function runCodexExec(stdin: string, cwd: string): Promise<string> {
  const bin = process.env.CODEX_BIN ?? 'codex';
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
  return runCommand(bin, args, stdin, cwd, false);
}

function runShellCommand(command: string, stdin: string, cwd: string): Promise<string> {
  console.log(`[codex] starting shell command: ${command}`);
  return runCommand(command, [], stdin, cwd, true);
}

function runCommand(
  command: string,
  args: string[],
  stdin: string,
  cwd: string,
  shell: boolean,
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
      writeProcessOutput('stdout', text);
    });
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString();
      stderr += text;
      writeProcessOutput('stderr', text);
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

function writeProcessOutput(stream: 'stdout' | 'stderr', text: string): void {
  for (const line of text.split(/\r?\n/)) {
    if (line.length > 0) {
      console.log(`[codex:${stream}] ${line}`);
    }
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
