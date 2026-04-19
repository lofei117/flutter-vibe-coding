import { getContainer } from '../services/container.ts';
import type { RouteResult } from './command.ts';

export function handleCurrentSession(): RouteResult {
  const session = getContainer().sessionStore.getCurrent();
  return {
    statusCode: 200,
    body: {
      success: true,
      session,
    },
  };
}
