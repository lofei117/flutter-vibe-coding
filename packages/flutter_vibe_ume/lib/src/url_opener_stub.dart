/// Stub used on platforms where there is no in-process way to open a URL
/// (mobile/desktop). Returns false so callers can fall back to clipboard.
Future<bool> openUrlInNewTab(String url) async => false;
