import { mkdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { FilePatch } from '../types/agent.ts';
import { SafetyError, isForbiddenPath } from './safety_policy.ts';

const DEFAULT_WRITABLE_EXTENSIONS = new Set([
  '.dart',
  '.yaml',
  '.yml',
  '.json',
  '.md',
  '.txt',
]);

const DEFAULT_WRITABLE_BASENAMES = new Set([
  'pubspec.yaml',
  'analysis_options.yaml',
]);

function loadWritableExtensions(): Set<string> {
  const env = process.env.WRITABLE_EXTENSIONS;
  if (!env) return DEFAULT_WRITABLE_EXTENSIONS;
  const set = new Set<string>();
  for (const raw of env.split(',')) {
    const ext = raw.trim();
    if (!ext) continue;
    set.add(ext.startsWith('.') ? ext : '.' + ext);
  }
  return set.size > 0 ? set : DEFAULT_WRITABLE_EXTENSIONS;
}

const MAX_PATCH_FILES = Number(process.env.MAX_PATCH_FILES ?? 8);
const MAX_PATCH_BYTES = Number(process.env.MAX_PATCH_BYTES ?? 256 * 1024);
const MAX_PATCH_LINES = Number(process.env.MAX_PATCH_LINES ?? 800);

export class PatchGuardService {
  private readonly writableExtensions = loadWritableExtensions();

  async validate(patches: FilePatch[], projectPath: string): Promise<void> {
    if (patches.length === 0) return;
    if (patches.length > MAX_PATCH_FILES) {
      throw new SafetyError({
        allowed: false,
        level: 'blocked',
        reasons: [
          `Patch touches ${patches.length} files which exceeds MAX_PATCH_FILES=${MAX_PATCH_FILES}.`,
        ],
      });
    }

    const projectRoot = path.resolve(projectPath);
    const realProjectRoot = await safeRealpath(projectRoot);
    let totalLines = 0;
    for (const patch of patches) {
      const resolved = path.resolve(patch.path);
      if (!isWithin(resolved, projectRoot)) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [`Patch target "${resolved}" is outside the project directory.`],
        });
      }
      if (isForbiddenPath(resolved)) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [`Patch target "${resolved}" is in a forbidden path.`],
        });
      }

      const realResolved = await safeRealpathForTarget(resolved);
      if (!isWithin(realResolved, realProjectRoot)) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [
            `Patch target "${patch.relativePath}" resolves via symlink to "${realResolved}" outside project root "${realProjectRoot}".`,
          ],
        });
      }
      if (isForbiddenPath(realResolved)) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [`Patch target "${patch.relativePath}" resolves to forbidden path "${realResolved}".`],
        });
      }

      const ext = path.extname(resolved);
      const base = path.basename(resolved);
      if (!this.writableExtensions.has(ext) && !DEFAULT_WRITABLE_BASENAMES.has(base)) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [`File extension "${ext}" of "${patch.relativePath}" is not in the writable allowlist.`],
        });
      }
      if (Buffer.byteLength(patch.after, 'utf8') > MAX_PATCH_BYTES) {
        throw new SafetyError({
          allowed: false,
          level: 'blocked',
          reasons: [`File "${patch.relativePath}" exceeds MAX_PATCH_BYTES=${MAX_PATCH_BYTES}.`],
        });
      }
      totalLines += diffLineCount(patch.before, patch.after);
    }
    if (totalLines > MAX_PATCH_LINES) {
      throw new SafetyError({
        allowed: false,
        level: 'blocked',
        reasons: [`Total changed lines ${totalLines} exceeds MAX_PATCH_LINES=${MAX_PATCH_LINES}.`],
      });
    }
  }

  async backup(commandId: string, patches: FilePatch[]): Promise<void> {
    if (patches.length === 0) return;
    const root = path.resolve('.local-ai-server', 'backups', commandId);
    await mkdir(root, { recursive: true });
    for (const patch of patches) {
      const target = path.join(root, patch.relativePath);
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, patch.before, 'utf8');
    }
  }
}

function isWithin(target: string, root: string): boolean {
  return target === root || target.startsWith(root + path.sep);
}

async function safeRealpath(target: string): Promise<string> {
  try {
    return await realpath(target);
  } catch {
    return path.resolve(target);
  }
}

async function safeRealpathForTarget(target: string): Promise<string> {
  try {
    return await realpath(target);
  } catch {
    // File may not exist yet (new file). Resolve realpath of the closest existing parent.
    let cur = path.dirname(target);
    while (cur !== path.dirname(cur)) {
      try {
        const real = await realpath(cur);
        return path.join(real, path.relative(cur, target));
      } catch {
        cur = path.dirname(cur);
      }
    }
    return path.resolve(target);
  }
}

function diffLineCount(before: string, after: string): number {
  const beforeLines = before.split(/\r?\n/);
  const afterLines = after.split(/\r?\n/);
  return Math.abs(afterLines.length - beforeLines.length) + countDifferingLines(beforeLines, afterLines);
}

function countDifferingLines(a: string[], b: string[]): number {
  const len = Math.min(a.length, b.length);
  let diff = 0;
  for (let i = 0; i < len; i += 1) {
    if (a[i] !== b[i]) diff += 1;
  }
  return diff;
}
