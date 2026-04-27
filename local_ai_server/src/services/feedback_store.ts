import { EventEmitter } from 'node:events';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import type {
  FeedbackTicket,
  FeedbackTicketEvent,
  FeedbackTicketEventStage,
  FeedbackTicketRequest,
  FeedbackTicketStatus,
  LocalCiResult,
} from '../types/feedback.ts';

const DEFAULT_STORE_PATH = '.local-ai-server/feedback/tickets.json';
const FLUSH_DEBOUNCE_MS = 200;
const MAX_EVENTS_PER_TICKET = 500;

type Persistable = {
  version: 1;
  updatedAt: string;
  tickets: FeedbackTicket[];
};

export class FeedbackStore {
  private tickets: Map<string, FeedbackTicket> = new Map();
  private readonly storePath: string;
  private readonly emitter = new EventEmitter();
  private flushTimer: NodeJS.Timeout | null = null;
  private loaded = false;

  constructor(storePath?: string) {
    this.storePath = path.resolve(
      storePath ?? process.env.FEEDBACK_STORE_PATH ?? DEFAULT_STORE_PATH,
    );
    this.emitter.setMaxListeners(50);
  }

  async load(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await readFile(this.storePath, 'utf8');
      const parsed = JSON.parse(raw) as Persistable;
      if (parsed && Array.isArray(parsed.tickets)) {
        for (const ticket of parsed.tickets) {
          this.tickets.set(ticket.ticketId, ticket);
        }
      }
    } catch {
      // first run, no store yet
    }
    this.loaded = true;
  }

  async create(
    request: FeedbackTicketRequest,
    screenshotPath?: string,
  ): Promise<FeedbackTicket> {
    const ticketId = `tkt_${randomUUID().slice(0, 12)}`;
    const now = new Date().toISOString();
    const ticket: FeedbackTicket = {
      ticketId,
      status: 'queued',
      instruction: request.instruction,
      clientMeta: request.clientMeta,
      pageContext: request.pageContext,
      target: request.target,
      runtimeContext: request.runtimeContext,
      screenshotPath,
      changedFiles: [],
      events: [],
      createdAt: now,
      updatedAt: now,
    };
    this.tickets.set(ticketId, ticket);
    this.appendEvent(ticketId, 'created', 'Feedback ticket created and queued.', {
      pageContext: request.pageContext,
      target: request.target,
    });
    return this.get(ticketId)!;
  }

  list(): FeedbackTicket[] {
    return Array.from(this.tickets.values()).sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    );
  }

  get(ticketId: string): FeedbackTicket | undefined {
    const ticket = this.tickets.get(ticketId);
    if (!ticket) return undefined;
    // Return a structural clone to avoid mutation by callers.
    return JSON.parse(JSON.stringify(ticket)) as FeedbackTicket;
  }

  setStatus(
    ticketId: string,
    status: FeedbackTicketStatus,
    message?: string,
    payload?: Record<string, unknown>,
  ): void {
    const ticket = this.tickets.get(ticketId);
    if (!ticket) return;
    ticket.status = status;
    ticket.updatedAt = new Date().toISOString();
    if (status === 'failed' && message) ticket.failureReason = message;
    this.scheduleFlush();
    this.emitter.emit(`status:${ticketId}`, ticket.status);
    if (message) {
      const stage: FeedbackTicketEventStage =
        status === 'failed'
          ? 'failed'
          : status === 'deployed'
            ? 'deployed'
            : 'log';
      this.appendEvent(ticketId, stage, message, payload);
    }
  }

  patch(
    ticketId: string,
    update: Partial<
      Pick<
        FeedbackTicket,
        | 'changedFiles'
        | 'agentOutput'
        | 'agentCommandId'
        | 'ci'
        | 'previewUrl'
        | 'failureReason'
      >
    >,
  ): void {
    const ticket = this.tickets.get(ticketId);
    if (!ticket) return;
    Object.assign(ticket, update);
    ticket.updatedAt = new Date().toISOString();
    this.scheduleFlush();
  }

  setCi(ticketId: string, ci: LocalCiResult): void {
    const ticket = this.tickets.get(ticketId);
    if (!ticket) return;
    ticket.ci = ci;
    ticket.updatedAt = new Date().toISOString();
    this.scheduleFlush();
  }

  appendEvent(
    ticketId: string,
    stage: FeedbackTicketEventStage,
    message: string,
    payload?: Record<string, unknown>,
  ): FeedbackTicketEvent {
    const ticket = this.tickets.get(ticketId);
    const event: FeedbackTicketEvent = {
      ticketId,
      sequence: (ticket?.events.length ?? 0) + 1,
      stage,
      message,
      timestamp: new Date().toISOString(),
      payload,
    };
    if (ticket) {
      ticket.events.push(event);
      if (ticket.events.length > MAX_EVENTS_PER_TICKET) {
        ticket.events = ticket.events.slice(-MAX_EVENTS_PER_TICKET);
      }
      ticket.updatedAt = event.timestamp;
      this.scheduleFlush();
    }
    this.emitter.emit(`events:${ticketId}`, event);
    return event;
  }

  getEvents(ticketId: string): FeedbackTicketEvent[] {
    return this.tickets.get(ticketId)?.events.slice() ?? [];
  }

  subscribeEvents(
    ticketId: string,
    onEvent: (event: FeedbackTicketEvent) => void,
  ): () => void {
    const channel = `events:${ticketId}`;
    this.emitter.on(channel, onEvent);
    return () => this.emitter.off(channel, onEvent);
  }

  isTerminal(ticketId: string): boolean {
    const ticket = this.tickets.get(ticketId);
    if (!ticket) return true;
    return ticket.status === 'deployed' || ticket.status === 'failed';
  }

  async flush(): Promise<void> {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flushNow();
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      void this.flushNow();
    }, FLUSH_DEBOUNCE_MS);
  }

  private async flushNow(): Promise<void> {
    try {
      await mkdir(path.dirname(this.storePath), { recursive: true });
      const data: Persistable = {
        version: 1,
        updatedAt: new Date().toISOString(),
        tickets: Array.from(this.tickets.values()),
      };
      await writeFile(this.storePath, JSON.stringify(data, null, 2), 'utf8');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(`[feedback-store] flush failed: ${message}`);
    }
  }
}

let singleton: FeedbackStore | null = null;

export function getFeedbackStore(): FeedbackStore {
  if (!singleton) singleton = new FeedbackStore();
  return singleton;
}
