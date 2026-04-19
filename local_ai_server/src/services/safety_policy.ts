import os from 'node:os';
import path from 'node:path';
import type { SafetyDecision } from '../types/safety.ts';

export class SafetyError extends Error {
  readonly decision: SafetyDecision;

  constructor(decision: SafetyDecision) {
    super(decision.reasons.join('; '));
    this.name = 'SafetyError';
    this.decision = decision;
  }
}

const INSTRUCTION_DENY_PATTERNS: Array<{ pattern: RegExp; reason: string }> = [
  { pattern: /\brm\s+-rf\b/i, reason: 'Destructive command "rm -rf" is not allowed.' },
  { pattern: /\brm\s+-fr\b/i, reason: 'Destructive command "rm -fr" is not allowed.' },
  { pattern: /\bgit\s+reset\s+--hard\b/i, reason: '"git reset --hard" is not allowed.' },
  { pattern: /\bgit\s+clean\s+-fdx\b/i, reason: '"git clean -fdx" is not allowed.' },
  { pattern: /\bformat\s+c:\b/i, reason: 'Disk format command is not allowed.' },
  { pattern: /\bchmod\s+-R\b/i, reason: 'Recursive chmod is not allowed.' },
  { pattern: /\bchown\s+-R\b/i, reason: 'Recursive chown is not allowed.' },
  { pattern: /\bmkfs\b/i, reason: 'Filesystem operations are not allowed.' },
  { pattern: /\bsudo\b/i, reason: 'sudo is not allowed.' },
  { pattern: /\bcurl\b[^\n]*\|\s*sh\b/i, reason: 'curl | sh is not allowed.' },
  { pattern: /\bwget\b[^\n]*\|\s*sh\b/i, reason: 'wget | sh is not allowed.' },
  { pattern: /删除整个项目/i, reason: '禁止删除整个项目。' },
  { pattern: /删除项目/i, reason: '禁止删除项目目录。' },
  { pattern: /清空(用户)?主目录/i, reason: '禁止清空主目录。' },
  { pattern: /清空磁盘/i, reason: '禁止清空磁盘。' },
  { pattern: /格式化磁盘/i, reason: '禁止格式化磁盘。' },
];

const FORBIDDEN_PATH_PREFIXES: string[] = [
  path.join(os.homedir(), '.ssh'),
  path.join(os.homedir(), '.aws'),
  path.join(os.homedir(), '.config', 'gcloud'),
  '/etc',
  '/usr',
  '/var',
  '/System',
  '/Library',
  '/private',
  '/bin',
  '/sbin',
];

export function evaluateInstruction(instruction: string): SafetyDecision {
  const reasons: string[] = [];
  const blocked: string[] = [];
  for (const { pattern, reason } of INSTRUCTION_DENY_PATTERNS) {
    if (pattern.test(instruction)) {
      reasons.push(reason);
      blocked.push(pattern.source);
    }
  }

  if (reasons.length === 0) {
    return { allowed: true, level: 'safe', reasons: ['Instruction passed safety policy.'] };
  }
  return {
    allowed: false,
    level: 'blocked',
    reasons,
    blockedOperations: blocked,
  };
}

export function evaluateProjectPath(
  projectPath: string,
  options: { allowedRoot?: string } = {},
): SafetyDecision {
  const resolved = path.resolve(projectPath);
  if (!resolved || resolved === '/') {
    return {
      allowed: false,
      level: 'blocked',
      reasons: ['Project path resolves to filesystem root.'],
    };
  }
  for (const prefix of FORBIDDEN_PATH_PREFIXES) {
    if (resolved === prefix || resolved.startsWith(prefix + path.sep)) {
      return {
        allowed: false,
        level: 'blocked',
        reasons: [`Project path "${resolved}" is inside forbidden directory "${prefix}".`],
      };
    }
  }
  if (resolved === os.homedir()) {
    return {
      allowed: false,
      level: 'blocked',
      reasons: ['Project path equals user home directory.'],
    };
  }
  if (options.allowedRoot) {
    const root = path.resolve(options.allowedRoot);
    if (resolved !== root && !resolved.startsWith(root + path.sep)) {
      return {
        allowed: false,
        level: 'blocked',
        reasons: [
          `Project path "${resolved}" is outside the configured FLUTTER_PROJECT_PATH "${root}".`,
        ],
      };
    }
  }
  return { allowed: true, level: 'safe', reasons: ['Project path passed safety policy.'] };
}

export function isForbiddenPath(targetPath: string): boolean {
  const resolved = path.resolve(targetPath);
  if (resolved === os.homedir()) return true;
  return FORBIDDEN_PATH_PREFIXES.some(
    (prefix) => resolved === prefix || resolved.startsWith(prefix + path.sep),
  );
}
