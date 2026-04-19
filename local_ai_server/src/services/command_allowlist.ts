import { SafetyError } from './safety_policy.ts';

const ALLOWED_BINARIES = new Set([
  'flutter',
  'dart',
  'codex',
]);

const FORBIDDEN_SHELL_TOKENS = [
  '&&',
  '||',
  ';',
  '`',
  '$(',
  '|',
  '>',
  '<',
  '\n',
  '\r',
];

export function ensureAllowedBinary(command: string): void {
  if (!ALLOWED_BINARIES.has(command)) {
    throw new SafetyError({
      allowed: false,
      level: 'blocked',
      reasons: [`Binary "${command}" is not in the allowlist (${[...ALLOWED_BINARIES].join(', ')}).`],
    });
  }
}

export function ensureSafeShellCommand(command: string): void {
  for (const token of FORBIDDEN_SHELL_TOKENS) {
    if (command.includes(token)) {
      throw new SafetyError({
        allowed: false,
        level: 'blocked',
        reasons: [`Shell command contains forbidden token "${token}".`],
      });
    }
  }
  const head = command.trim().split(/\s+/, 1)[0];
  if (!head) {
    throw new SafetyError({
      allowed: false,
      level: 'blocked',
      reasons: ['Empty shell command.'],
    });
  }
  ensureAllowedBinary(head);
}

export function getAllowedBinaries(): string[] {
  return [...ALLOWED_BINARIES];
}
