import { getContainer } from '../services/container.ts';
import type { StartAppRequest } from '../types/app.ts';
import type { RouteResult } from './command.ts';
import { SafetyError } from '../services/safety_policy.ts';

export async function handleStartApp(rawBody: unknown): Promise<RouteResult> {
  const body = (rawBody ?? {}) as StartAppRequest;
  if (!body.target) {
    return {
      statusCode: 400,
      body: { success: false, message: 'target is required (chrome|android|ios|macos)' },
    };
  }
  try {
    const result = await getContainer().appSessions.start(body);
    return {
      statusCode: result.success ? 200 : 409,
      body: result as unknown as Record<string, unknown>,
    };
  } catch (error) {
    if (error instanceof SafetyError) {
      return {
        statusCode: 403,
        body: {
          success: false,
          message: `Blocked by safety policy: ${error.decision.reasons.join('; ')}`,
          safety: error.decision,
        },
      };
    }
    const message = error instanceof Error ? error.message : String(error);
    return { statusCode: 500, body: { success: false, message } };
  }
}

export function handleAppSession(): RouteResult {
  const current = getContainer().appSessions.getCurrent();
  if (!current) {
    return {
      statusCode: 200,
      body: { success: true, session: null, message: 'No managed app session.' },
    };
  }
  return {
    statusCode: 200,
    body: {
      success: true,
      session: current.session,
      logs: current.logs.slice(-50),
    },
  };
}

export async function handleAppReload(appSessionId: string): Promise<RouteResult> {
  const result = await getContainer().appSessions.reload(appSessionId);
  return {
    statusCode: result.ok ? 200 : 404,
    body: { success: result.ok, message: result.message },
  };
}

export async function handleAppRestart(appSessionId: string): Promise<RouteResult> {
  const result = await getContainer().appSessions.restart(appSessionId);
  return {
    statusCode: result.ok ? 200 : 404,
    body: { success: result.ok, message: result.message },
  };
}

export async function handleAppStop(appSessionId: string): Promise<RouteResult> {
  const result = await getContainer().appSessions.stop(appSessionId);
  return {
    statusCode: result.ok ? 200 : 404,
    body: { success: result.ok, message: result.message },
  };
}
