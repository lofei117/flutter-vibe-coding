import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_PREVIEW_ROOT = '.local-ai-server/preview/web';
const PREVIEW_BASE_HREF = process.env.PREVIEW_BASE_HREF ?? '/preview/';

export class PreviewPublisher {
  /** Filesystem location where the published web build lives. */
  getPreviewRoot(): string {
    return path.resolve(
      process.env.PREVIEW_ROOT ?? DEFAULT_PREVIEW_ROOT,
    );
  }

  /**
   * Copy `build/web` from the project to the preview root. Returns true if
   * the copy succeeded.
   */
  async publish(projectPath: string): Promise<{ ok: boolean; message: string; root: string }> {
    const source = path.resolve(projectPath, 'build', 'web');
    const target = this.getPreviewRoot();

    try {
      const sourceStat = await stat(source);
      if (!sourceStat.isDirectory()) {
        return {
          ok: false,
          message: `Expected build output directory at ${source}, got non-directory.`,
          root: target,
        };
      }
    } catch {
      return {
        ok: false,
        message: `No build/web directory at ${source}; did flutter build web run?`,
        root: target,
      };
    }

    try {
      await rm(target, { recursive: true, force: true });
      await mkdir(path.dirname(target), { recursive: true });
      await cp(source, target, { recursive: true });
      await rewritePreviewBaseHref(target);
      return {
        ok: true,
        message: `Published ${source} to ${target}.`,
        root: target,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        ok: false,
        message: `Failed to publish build to preview: ${message}`,
        root: target,
      };
    }
  }

  /**
   * Build the externally-visible URL the App / browser should open after
   * deployment. We append a cache-busting marker so refresh shows new bits
   * even when the static handler caches aggressively.
   *
   * `requestHost` should be the `Host` header the client used to reach this
   * server; it is the most reliable source of host:port that the client can
   * actually reach (server bind addr like `0.0.0.0` is useless to the
   * browser). `fallbackHost`/`fallbackPort` only kick in when no Host header
   * is available (e.g. internal calls).
   */
  buildPreviewUrl(
    requestHost: string | undefined,
    fallbackHost: string | undefined,
    fallbackPort: number,
    ticketId: string,
  ): string {
    let hostPort = (requestHost ?? '').trim();
    if (!hostPort) {
      const cleaned = (fallbackHost ?? 'localhost').replace(/^0\.0\.0\.0$/, 'localhost');
      hostPort = `${cleaned}:${fallbackPort}`;
    }
    return `http://${hostPort}/preview/?ticket=${encodeURIComponent(ticketId)}&t=${Date.now()}`;
  }
}

async function rewritePreviewBaseHref(previewRoot: string): Promise<void> {
  const indexPath = path.join(previewRoot, 'index.html');
  const html = await readFile(indexPath, 'utf8');
  const next = html.replace(
    /<base\s+href="[^"]*"\s*>/i,
    `<base href="${PREVIEW_BASE_HREF}">`,
  );
  await writeFile(indexPath, next, 'utf8');
}

let singleton: PreviewPublisher | null = null;

export function getPreviewPublisher(): PreviewPublisher {
  if (!singleton) singleton = new PreviewPublisher();
  return singleton;
}
