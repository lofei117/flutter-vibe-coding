import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import {
  handleAppReload,
  handleAppRestart,
  handleAppSession,
  handleAppStop,
  handleStartApp,
} from './routes/app.ts';
import {
  handleCommand,
  handleCommandConfirm,
  handleCommandEvents,
  handleCommandStatus,
  type RouteResult,
} from './routes/command.ts';
import { handleHealth } from './routes/health.ts';
import { handleCurrentSession } from './routes/session.ts';
import { buildContainer } from './services/container.ts';

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '0.0.0.0';

await buildContainer();

const server = createServer(async (req, res) => {
  addCorsHeaders(res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  console.log(`[${new Date().toISOString()}] ${req.method} ${url.pathname}${url.search}`);

  try {
    const handled = await dispatch(req, res, url);
    if (!handled) {
      sendJson(res, 404, { success: false, message: 'Not found' });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[server] failed: ${message}`);
    if (!res.headersSent) {
      sendJson(res, 500, {
        success: false,
        message,
        applied: false,
        reloadTriggered: false,
      });
    } else {
      try {
        res.end();
      } catch {
        // ignore
      }
    }
  }
});

server.listen(port, host, () => {
  console.log(`Local AI server listening on http://${host}:${port}`);
  console.log(`Default Flutter project path: ${process.env.FLUTTER_PROJECT_PATH ?? '../mobile_vibe_demo'}`);
  console.log(`Agent adapter: ${process.env.AGENT_ADAPTER ?? 'mock'}`);
});

async function dispatch(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
): Promise<boolean> {
  const method = req.method ?? 'GET';
  const pathname = url.pathname;

  if (method === 'GET' && pathname === '/health') {
    sendJson(res, 200, handleHealth());
    return true;
  }

  if (method === 'POST' && pathname === '/command') {
    const body = await readJson(req);
    const wait = url.searchParams.get('wait') === 'true';
    const result = await handleCommand(body, { wait });
    sendResult(res, result);
    return true;
  }

  const commandStatus = matchRoute('/command/:id/status', pathname);
  if (method === 'GET' && commandStatus) {
    sendResult(res, handleCommandStatus(commandStatus.id));
    return true;
  }

  const commandEvents = matchRoute('/command/:id/events', pathname);
  if (method === 'GET' && commandEvents) {
    handleCommandEvents(commandEvents.id, res);
    return true;
  }

  const commandConfirm = matchRoute('/command/:id/confirm', pathname);
  if (method === 'POST' && commandConfirm) {
    const body = await readJson(req);
    sendResult(res, handleCommandConfirm(commandConfirm.id, body));
    return true;
  }

  if (method === 'GET' && pathname === '/session/current') {
    sendResult(res, handleCurrentSession());
    return true;
  }

  if (method === 'POST' && pathname === '/app/start') {
    const body = await readJson(req);
    sendResult(res, await handleStartApp(body));
    return true;
  }

  if (method === 'GET' && pathname === '/app/session') {
    sendResult(res, handleAppSession());
    return true;
  }

  const appReload = matchRoute('/app/:id/reload', pathname);
  if (method === 'POST' && appReload) {
    sendResult(res, await handleAppReload(appReload.id));
    return true;
  }

  const appRestart = matchRoute('/app/:id/restart', pathname);
  if (method === 'POST' && appRestart) {
    sendResult(res, await handleAppRestart(appRestart.id));
    return true;
  }

  const appStop = matchRoute('/app/:id/stop', pathname);
  if (method === 'POST' && appStop) {
    sendResult(res, await handleAppStop(appStop.id));
    return true;
  }

  return false;
}

function matchRoute(template: string, pathname: string): Record<string, string> | null {
  const templateParts = template.split('/').filter(Boolean);
  const pathParts = pathname.split('/').filter(Boolean);
  if (templateParts.length !== pathParts.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < templateParts.length; i += 1) {
    const t = templateParts[i];
    const p = pathParts[i];
    if (t.startsWith(':')) {
      params[t.slice(1)] = decodeURIComponent(p);
    } else if (t !== p) {
      return null;
    }
  }
  return params;
}

function addCorsHeaders(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendResult(res: ServerResponse, result: RouteResult): void {
  sendJson(res, result.statusCode, result.body);
}

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  if (res.headersSent) return;
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function readJson(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk.toString();
      if (raw.length > 2 * 1024 * 1024) {
        reject(new Error('Request body is too large.'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!raw.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error('Invalid JSON body.'));
      }
    });
    req.on('error', reject);
  });
}
