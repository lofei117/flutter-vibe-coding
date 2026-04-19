export function handleHealth(): Record<string, unknown> {
  return {
    ok: true,
    service: 'local-ai-server',
    time: new Date().toISOString(),
  };
}
