import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { handleCommand } from './routes/command.ts';
import { handleHealth } from './routes/health.ts';

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '0.0.0.0';

const server = createServer(async (req, res) => {
  addCorsHeaders(res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  console.log(`[${new Date().toISOString()}] ${req.method} ${url.pathname}`);

  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      sendJson(res, 200, handleHealth());
      return;
    }

    if (req.method === 'POST' && url.pathname === '/command') {
      const body = await readJson(req);
      const result = await handleCommand(body);
      sendJson(res, result.statusCode, result.body);
      return;
    }

    sendJson(res, 404, { success: false, message: 'Not found' });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[server] failed: ${message}`);
    sendJson(res, 500, {
      success: false,
      message,
      applied: false,
      reloadTriggered: false,
    });
  }
});

server.listen(port, host, () => {
  console.log(`Local AI server listening on http://${host}:${port}`);
  console.log(`Default Flutter project path: ${process.env.FLUTTER_PROJECT_PATH ?? '../mobile_vibe_demo'}`);
  console.log(`Agent adapter: ${process.env.AGENT_ADAPTER ?? 'mock'}`);
});

function addCorsHeaders(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function readJson(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk.toString();
      if (raw.length > 1024 * 1024) {
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
