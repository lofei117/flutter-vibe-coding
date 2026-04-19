import 'package:flutter_vibe_ume/flutter_vibe_ume.dart';

/// Maps stable widget keys to the file/symbol anchors the mock and Codex
/// adapters can edit. Keep this in sync with [flutter_vibe_app/lib/home_page.dart].
const Map<String, SourceAnchor> sourceRegistry = <String, SourceAnchor>{
  'home.helloButton': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeButtonLabel',
    owner: 'HomePage',
    package: 'flutter_vibe_app',
    additionalSymbols: ['homeButtonColor'],
  ),
  'home.title': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeTitle',
    owner: 'HomePage',
    package: 'flutter_vibe_app',
  ),
  'home.description': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeDescription',
    owner: 'HomePage',
    package: 'flutter_vibe_app',
  ),
};

SourceAnchor? lookupSourceAnchor(String? widgetKey) {
  if (widgetKey == null || widgetKey.isEmpty) return null;
  return sourceRegistry[widgetKey];
}
