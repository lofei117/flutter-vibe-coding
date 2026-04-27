// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation: opens the given URL in a new browser tab.
/// Returns false if the browser blocked the popup.
Future<bool> openUrlInNewTab(String url) async {
  final win = html.window.open(url, '_blank');
  // window.open returns null when blocked by popup blockers.
  // ignore: unnecessary_null_comparison
  return win != null;
}
