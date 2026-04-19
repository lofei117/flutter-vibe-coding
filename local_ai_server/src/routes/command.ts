import type { ServerResponse } from 'node:http';
import type { CommandRequest } from '../types/command.ts';
import type { ApprovalDecision } from '../types/safety.ts';
import { getContainer } from '../services/container.ts';

export type RouteResult = {
  statusCode: number;
  body: Record<string, unknown>;
};

export async function handleCommand(
  rawBody: unknown,
  options: { wait: boolean } = { wait: false },
): Promise<RouteResult> {
  const body = (rawBody ?? {}) as CommandRequest;
  const instruction = body.instruction?.trim();

  if (!instruction) {
    return {
      statusCode: 400,
      body: {
        success: false,
        message: 'instruction is required',
        applied: false,
        reloadTriggered: false,
        changedFiles: [],
        agentOutput: '',
      },
    };
  }

  const { orchestrator } = getContainer();
  const enq = orchestrator.enqueue({ ...body, instruction });

  if (options.wait) {
    const response = await enq.promise;
    const statusCode = response.success ? 200 : (response.safety && !response.safety.allowed ? 403 : 500);
    return { statusCode, body: response as unknown as Record<string, unknown> };
  }

  return {
    statusCode: 202,
    body: {
      success: true,
      commandId: enq.commandId,
      message: 'queued',
      applied: false,
      reloadTriggered: false,
      changedFiles: [],
      agentOutput: '',
    },
  };
}

export function handleCommandConfirm(
  commandId: string,
  rawBody: unknown,
): RouteResult {
  const body = (rawBody ?? {}) as Partial<ApprovalDecision> & { approved?: boolean };
  const { orchestrator } = getContainer();
  const pending = orchestrator.getPendingApproval(commandId);
  if (!pending) {
    return {
      statusCode: 404,
      body: {
        success: false,
        message: `No pending approval for command ${commandId}.`,
      },
    };
  }
  const approvalId = body.approvalId ?? pending.approvalId;
  const decision: ApprovalDecision['decision'] =
    body.decision ?? (body.approved === false ? 'rejected' : 'approved');
  const resolved = orchestrator.confirm(commandId, {
    approvalId,
    decision,
    comment: body.comment,
  });
  if (!resolved) {
    return {
      statusCode: 409,
      body: {
        success: false,
        message: 'Approval id mismatch or approval already resolved.',
      },
    };
  }
  return {
    statusCode: 200,
    body: {
      success: true,
      commandId,
      approvalId,
      decision,
    },
  };
}

export function handleCommandStatus(commandId: string): RouteResult {
  const { sessionStore } = getContainer();
  const events = sessionStore.getEvents(commandId);
  if (events.length === 0) {
    return {
      statusCode: 404,
      body: { success: false, message: `Unknown commandId: ${commandId}` },
    };
  }
  const latest = events[events.length - 1];
  return {
    statusCode: 200,
    body: {
      success: true,
      commandId,
      stage: latest.stage,
      message: latest.message,
      events,
      finalResponse: sessionStore.getFinalResponse(commandId),
    },
  };
}

export function handleCommandEvents(
  commandId: string,
  res: ServerResponse,
): void {
  const { sessionStore } = getContainer();
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
    'X-Accel-Buffering': 'no',
  });
  res.write(`retry: 5000\n\n`);

  let lastSequence = 0;
  const writeEvent = (event: ReturnType<typeof sessionStore.getEvents>[number]) => {
    if (event.sequence <= lastSequence) return;
    lastSequence = event.sequence;
    res.write(`id: ${event.sequence}\n`);
    res.write(`event: ${event.stage}\n`);
    res.write(`data: ${JSON.stringify(event)}\n\n`);
  };

  for (const event of sessionStore.getEvents(commandId)) {
    writeEvent(event);
  }

  const finalAlready = sessionStore.getFinalResponse(commandId);
  if (finalAlready) {
    res.write(`event: final\n`);
    res.write(`data: ${JSON.stringify(finalAlready)}\n\n`);
    res.end();
    return;
  }

  const heartbeat = setInterval(() => {
    res.write(`: keep-alive\n\n`);
  }, 15000);

  const unsubscribeEvent = sessionStore.subscribeEvents(commandId, writeEvent);
  const unsubscribeFinal = sessionStore.subscribeFinal(commandId, (finalResponse) => {
    res.write(`event: final\n`);
    res.write(`data: ${JSON.stringify(finalResponse)}\n\n`);
    cleanup();
    res.end();
  });

  const cleanup = () => {
    clearInterval(heartbeat);
    unsubscribeEvent();
    unsubscribeFinal();
  };

  res.on('close', cleanup);
}
