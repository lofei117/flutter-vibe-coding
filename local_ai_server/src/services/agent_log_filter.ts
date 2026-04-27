export type AgentLogStream = 'stdout' | 'stderr' | 'system' | 'codex';

export type AgentLogPayload = {
  stream: AgentLogStream;
  level: 'debug' | 'info' | 'warning' | 'error';
  category:
    | 'thinking'
    | 'context'
    | 'patch'
    | 'safety'
    | 'reload'
    | 'repair'
    | 'approval'
    | 'fallback'
    | 'raw';
  source: 'codex' | 'mock' | 'flutter' | 'server' | 'shell';
  chunkIndex: number;
  truncated?: boolean;
};

export type AgentLogEntry = {
  message: string;
  payload: AgentLogPayload;
};

const MAX_AGENT_LOG_CHARS = 1200;

const NOISE_PATTERNS = [
  /Codex prompt prepared\.?/i,
  /codex_core::plugins::manager/i,
  /failed to warm featured plugin ids cache/i,
  /remote plugin sync request/i,
  /backend-api\/plugins\/featured/i,
  /featured plugin ids cache/i,
  /403 Forbidden/i,
  /chatgpt\.com\/backend-api\/plugins/i,
  /^\s*<\/?(html|head|body|style|meta|script|svg|path|div|span)\b/i,
  /<html[\s>]/i,
  /<head[\s>]/i,
  /<style\b/i,
  /<meta\s+/i,
];

const LOW_VALUE_PATTERNS = [
  /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏.\-\s]+$/,
  /^[-=]{3,}$/,
];

const RELEVANT_RAW_PATTERNS = [
  /\blib\/[\w./-]+\.(?:dart|yaml|yml|json|gradle|kt|swift|plist|xml)\b/i,
  /\b(?:reading|analyzing|planning|updating|applying|modifying|writing|editing)\b/i,
  /\b(?:widget|selection|source|context|candidate|patch|diff|reload|restart|repair|approval|fallback)\b/i,
];

export function normalizeAgentLogLine(params: {
  line: string;
  stream: AgentLogStream;
  source?: AgentLogPayload['source'];
  chunkIndex: number;
}): AgentLogEntry | null {
  const cleaned = stripAnsi(params.line).trim();
  if (!cleaned) return null;
  if (LOW_VALUE_PATTERNS.some((pattern) => pattern.test(cleaned))) return null;
  if (NOISE_PATTERNS.some((pattern) => pattern.test(cleaned))) return null;

  const payload: AgentLogPayload = {
    stream: params.stream,
    level: inferLevel(cleaned, params.stream),
    category: inferCategory(cleaned),
    source: params.source ?? 'codex',
    chunkIndex: params.chunkIndex,
  };

  if (payload.category == 'raw' && !isRelevantRawLine(cleaned)) {
    return null;
  }

  if (cleaned.length <= MAX_AGENT_LOG_CHARS) {
    return { message: cleaned, payload };
  }

  payload.truncated = true;
  return {
    message: `${cleaned.slice(0, MAX_AGENT_LOG_CHARS)}\n... (filtered, ${cleaned.length - MAX_AGENT_LOG_CHARS} more chars)`,
    payload,
  };
}

function inferLevel(line: string, stream: AgentLogStream): AgentLogPayload['level'] {
  if (/\b(error|failed|failure|exception|fatal|panic)\b/i.test(line)) return 'error';
  if (/\b(warn|warning|deprecated)\b/i.test(line)) return 'warning';
  if (stream === 'stderr') return 'warning';
  return 'info';
}

function inferCategory(line: string): AgentLogPayload['category'] {
  if (/\b(safety|guard|blocked|risk|policy)\b/i.test(line)) return 'safety';
  if (/\b(approval|approve|confirm|human)\b/i.test(line)) return 'approval';
  if (/\b(repair|fix compile|self.?repair)\b/i.test(line)) return 'repair';
  if (/\b(reload|restart|flutter run|hot reload|hot restart)\b/i.test(line)) return 'reload';
  if (/\b(patch|diff|modified|changed|edited|write|file)\b/i.test(line)) return 'patch';
  if (/\b(context|selection|widget|source)\b/i.test(line)) return 'context';
  if (/\b(fallback|mock adapter|codex unavailable)\b/i.test(line)) return 'fallback';
  if (/\b(thinking|analyz|plan|reason)\b/i.test(line)) return 'thinking';
  return 'raw';
}

function stripAnsi(text: string): string {
  // eslint-disable-next-line no-control-regex
  return text.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '');
}

function isRelevantRawLine(line: string): boolean {
  return RELEVANT_RAW_PATTERNS.some((pattern) => pattern.test(line));
}
