import { Buffer } from 'node:buffer';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { ServerResponse } from 'node:http';
import type {
  FeedbackTicketEvent,
  FeedbackTicketRequest,
} from '../types/feedback.ts';
import { getContainer } from '../services/container.ts';

export type RouteResult = {
  statusCode: number;
  body: Record<string, unknown>;
};

const SCREENSHOT_ROOT = '.local-ai-server/feedback/screenshots';
const MAX_SCREENSHOT_BYTES = 5 * 1024 * 1024; // 5MB

export async function handleCreateFeedbackTicket(
  rawBody: unknown,
): Promise<RouteResult> {
  const body = (rawBody ?? {}) as Partial<FeedbackTicketRequest>;
  const instruction = body.instruction?.trim();
  if (!instruction) {
    return {
      statusCode: 400,
      body: { success: false, message: 'instruction is required' },
    };
  }
  if (!body.clientMeta || !body.pageContext) {
    return {
      statusCode: 400,
      body: {
        success: false,
        message: 'clientMeta and pageContext are required',
      },
    };
  }

  const { feedbackStore } = getContainer();
  let screenshotPath: string | undefined;
  if (body.screenshot?.dataBase64) {
    try {
      screenshotPath = await persistScreenshot(body.screenshot);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        statusCode: 400,
        body: { success: false, message: `Screenshot save failed: ${message}` },
      };
    }
  } else if (body.screenshot?.localPath) {
    screenshotPath = body.screenshot.localPath;
  }

  const ticket = await feedbackStore.create(
    {
      instruction,
      clientMeta: body.clientMeta,
      pageContext: body.pageContext,
      target: body.target,
      runtimeContext: body.runtimeContext,
      screenshot: body.screenshot,
    },
    screenshotPath,
  );

  return {
    statusCode: 201,
    body: {
      success: true,
      ticket,
    },
  };
}

export function handleListFeedbackTickets(): RouteResult {
  const { feedbackStore } = getContainer();
  return {
    statusCode: 200,
    body: { success: true, tickets: feedbackStore.list() },
  };
}

export function handleGetFeedbackTicket(ticketId: string): RouteResult {
  const { feedbackStore } = getContainer();
  const ticket = feedbackStore.get(ticketId);
  if (!ticket) {
    return {
      statusCode: 404,
      body: { success: false, message: `Unknown ticketId ${ticketId}` },
    };
  }
  return {
    statusCode: 200,
    body: { success: true, ticket },
  };
}

export async function handleProcessFeedbackTicket(
  ticketId: string,
  rawBody: unknown,
  serverContext: { host?: string; port: number; requestHost?: string },
  options: { wait: boolean } = { wait: false },
): Promise<RouteResult> {
  const body = (rawBody ?? {}) as {
    buildFlavor?: 'profile' | 'release';
    skipTests?: boolean;
  };
  const { feedbackStore, feedbackPipeline } = getContainer();
  const ticket = feedbackStore.get(ticketId);
  if (!ticket) {
    return {
      statusCode: 404,
      body: { success: false, message: `Unknown ticketId ${ticketId}` },
    };
  }
  if (feedbackPipeline.isProcessing(ticketId)) {
    return {
      statusCode: 409,
      body: { success: false, message: `Ticket ${ticketId} is already being processed.` },
    };
  }

  const promise = feedbackPipeline.process(ticketId, {
    buildFlavor: body.buildFlavor,
    skipTests: body.skipTests,
    requestHost: serverContext.requestHost,
    serverHost: serverContext.host,
    serverPort: serverContext.port,
  });

  if (options.wait) {
    const final = await promise;
    return {
      statusCode: 200,
      body: { success: true, ticket: final ?? ticket },
    };
  }

  // Fire-and-forget; surface errors to console.
  promise.catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[feedback:${ticketId}] pipeline crashed: ${message}`);
  });
  return {
    statusCode: 202,
    body: { success: true, ticket, message: 'Pipeline started.' },
  };
}

export function handleFeedbackTicketEvents(
  ticketId: string,
  res: ServerResponse,
): void {
  const { feedbackStore } = getContainer();

  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
    'X-Accel-Buffering': 'no',
  });
  res.write(`retry: 5000\n\n`);

  const ticket = feedbackStore.get(ticketId);
  if (!ticket) {
    res.write(`event: error\n`);
    res.write(`data: ${JSON.stringify({ message: `Unknown ticketId ${ticketId}` })}\n\n`);
    res.end();
    return;
  }

  let lastSequence = 0;
  const writeEvent = (event: FeedbackTicketEvent) => {
    if (event.sequence <= lastSequence) return;
    lastSequence = event.sequence;
    res.write(`id: ${event.sequence}\n`);
    res.write(`event: ${event.stage}\n`);
    res.write(`data: ${JSON.stringify(event)}\n\n`);
  };

  for (const event of feedbackStore.getEvents(ticketId)) {
    writeEvent(event);
  }

  if (feedbackStore.isTerminal(ticketId)) {
    res.write(`event: final\n`);
    res.write(`data: ${JSON.stringify(feedbackStore.get(ticketId))}\n\n`);
    res.end();
    return;
  }

  const heartbeat = setInterval(() => {
    res.write(`: keep-alive\n\n`);
  }, 15000);

  const unsubscribe = feedbackStore.subscribeEvents(ticketId, (event) => {
    writeEvent(event);
    if (
      event.stage === 'deployed' ||
      event.stage === 'failed'
    ) {
      res.write(`event: final\n`);
      res.write(`data: ${JSON.stringify(feedbackStore.get(ticketId))}\n\n`);
      cleanup();
      res.end();
    }
  });

  const cleanup = () => {
    clearInterval(heartbeat);
    unsubscribe();
  };
  res.on('close', cleanup);
}

async function persistScreenshot(screenshot: {
  mimeType: 'image/png' | 'image/jpeg';
  dataBase64?: string;
}): Promise<string> {
  if (!screenshot.dataBase64) throw new Error('dataBase64 missing');
  const buffer = Buffer.from(screenshot.dataBase64, 'base64');
  if (buffer.byteLength === 0) throw new Error('Empty screenshot payload');
  if (buffer.byteLength > MAX_SCREENSHOT_BYTES) {
    throw new Error(`Screenshot exceeds ${MAX_SCREENSHOT_BYTES} bytes`);
  }
  const root = path.resolve(SCREENSHOT_ROOT);
  await mkdir(root, { recursive: true });
  const ext = screenshot.mimeType === 'image/jpeg' ? '.jpg' : '.png';
  const fileName = `shot_${Date.now()}_${Math.random().toString(36).slice(2, 8)}${ext}`;
  const target = path.join(root, fileName);
  await writeFile(target, buffer);
  return target;
}
