import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';
import type { ServerResponse } from 'node:http';
import { getPreviewPublisher } from '../services/preview_publisher.ts';

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.map': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
};

/**
 * Serve files from the preview root.
 *
 * `pathname` looks like `/preview/...rest`. Returns true if handled (or
 * intentionally rejected with a 404), false if the prefix didn't match.
 */
export async function handlePreview(
  pathname: string,
  res: ServerResponse,
): Promise<boolean> {
  if (pathname !== '/preview' && !pathname.startsWith('/preview/')) {
    return false;
  }

  const publisher = getPreviewPublisher();
  const root = publisher.getPreviewRoot();

  let relative = pathname === '/preview' || pathname === '/preview/' ? 'index.html' : pathname.slice('/preview/'.length);
  // Strip query string – Node already gave us pathname without it, but defensively.
  relative = relative.split('?')[0];
  // Disallow path traversal.
  if (relative.includes('..')) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Bad path');
    return true;
  }

  let target = path.resolve(root, relative);
  if (!target.startsWith(root + path.sep) && target !== root) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Bad path');
    return true;
  }

  let stats;
  try {
    stats = await stat(target);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Preview not built yet. Submit a feedback ticket and process it first.');
    return true;
  }

  if (stats.isDirectory()) {
    target = path.join(target, 'index.html');
    try {
      stats = await stat(target);
    } catch {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Preview index.html not found.');
      return true;
    }
  }

  const ext = path.extname(target).toLowerCase();
  const contentType = MIME_TYPES[ext] ?? 'application/octet-stream';
  res.writeHead(200, {
    'Content-Type': contentType,
    'Content-Length': String(stats.size),
    // Disable caching so QA always sees the latest build after redeploy.
    'Cache-Control': 'no-store',
  });
  createReadStream(target).pipe(res);
  return true;
}
