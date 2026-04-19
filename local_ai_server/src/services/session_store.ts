import { EventEmitter } from 'node:events';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type {
  CommandEvent,
  CommandResponse,
} from '../types/command.ts';
import type { SessionState, SessionTurn } from '../types/session.ts';

const DEFAULT_STORE_PATH = '.local-ai-server/session.json';
const FLUSH_DEBOUNCE_MS = 200;

export class SessionStore {
  private state: SessionState;
  private readonly storePath: string;
  private readonly emitter = new EventEmitter();
  private flushTimer: NodeJS.Timeout | null = null;
  private loaded = false;

  constructor(storePath?: string) {
    this.storePath = path.resolve(
      storePath ?? process.env.SESSION_STORE_PATH ?? DEFAULT_STORE_PATH,
    );
    this.state = createEmptySession();
  }

  async load(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await readFile(this.storePath, 'utf8');
      const parsed = JSON.parse(raw) as SessionState;
      if (parsed && typeof parsed === 'object' && Array.isArray(parsed.turns)) {
        this.state = parsed;
      }
    } catch {
      // Missing or unreadable file is fine; start with an empty session.
    }
    this.loaded = true;
  }

  getCurrent(): SessionState {
    return this.state;
  }

  upsertTurn(turn: SessionTurn): void {
    const idx = this.state.turns.findIndex((t) => t.turnId === turn.turnId);
    if (idx >= 0) {
      this.state.turns[idx] = turn;
    } else {
      this.state.turns.push(turn);
    }
    this.touch();
    this.scheduleFlush();
  }

  appendEvent(commandId: string, event: CommandEvent): void {
    const turn = this.findTurnByCommand(commandId);
    if (!turn) return;
    turn.events.push(event);
    turn.updatedAt = event.timestamp;
    this.touch();
    this.scheduleFlush();
    this.emitter.emit(`events:${commandId}`, event);
  }

  setFinalResponse(commandId: string, response: CommandResponse): void {
    const turn = this.findTurnByCommand(commandId);
    if (!turn) return;
    turn.finalResponse = response;
    turn.updatedAt = new Date().toISOString();
    this.touch();
    void this.flushNow();
    this.emitter.emit(`final:${commandId}`, response);
  }

  async flush(): Promise<void> {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flushNow();
  }

  getEvents(commandId: string): CommandEvent[] {
    const turn = this.findTurnByCommand(commandId);
    return turn?.events.slice() ?? [];
  }

  getFinalResponse(commandId: string): CommandResponse | undefined {
    return this.findTurnByCommand(commandId)?.finalResponse;
  }

  subscribeEvents(
    commandId: string,
    onEvent: (event: CommandEvent) => void,
  ): () => void {
    const channel = `events:${commandId}`;
    this.emitter.on(channel, onEvent);
    return () => this.emitter.off(channel, onEvent);
  }

  subscribeFinal(
    commandId: string,
    onFinal: (response: CommandResponse) => void,
  ): () => void {
    const channel = `final:${commandId}`;
    this.emitter.on(channel, onFinal);
    return () => this.emitter.off(channel, onFinal);
  }

  private findTurnByCommand(commandId: string): SessionTurn | undefined {
    return this.state.turns.find((turn) => turn.commandId === commandId);
  }

  private touch(): void {
    this.state.updatedAt = new Date().toISOString();
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      void this.flushNow();
    }, FLUSH_DEBOUNCE_MS);
  }

  private async flushNow(): Promise<void> {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    try {
      await mkdir(path.dirname(this.storePath), { recursive: true });
      await writeFile(
        this.storePath,
        JSON.stringify(this.state, null, 2),
        'utf8',
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[session-store] flush failed: ${message}`);
    }
  }
}

function createEmptySession(): SessionState {
  const now = new Date().toISOString();
  return {
    sessionId: 'current',
    createdAt: now,
    updatedAt: now,
    turns: [],
  };
}

let singleton: SessionStore | null = null;

export function getSessionStore(): SessionStore {
  if (!singleton) {
    singleton = new SessionStore();
  }
  return singleton;
}
