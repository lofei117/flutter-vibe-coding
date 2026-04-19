class SourceAnchor {
  const SourceAnchor({
    required this.file,
    required this.symbol,
    required this.owner,
    this.line,
    this.method = 'build',
    this.package = 'mobile_vibe_demo',
    this.additionalSymbols = const [],
  });

  final String file;
  final String symbol;
  final String owner;
  final int? line;
  final String method;
  final String package;
  final List<String> additionalSymbols;

  List<String> get candidateSymbols => [symbol, ...additionalSymbols, owner];
}

/// Maps stable widget keys to the file/symbol anchors the mock and Codex
/// adapters can edit. Keep this in sync with [mobile_vibe_demo/lib/home_page.dart].
const Map<String, SourceAnchor> sourceRegistry = <String, SourceAnchor>{
  'home.helloButton': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeButtonLabel',
    owner: 'HomePage',
    additionalSymbols: ['homeButtonColor'],
  ),
  'home.title': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeTitle',
    owner: 'HomePage',
  ),
  'home.description': SourceAnchor(
    file: 'lib/home_page.dart',
    symbol: 'homeDescription',
    owner: 'HomePage',
  ),
};

SourceAnchor? lookupSourceAnchor(String? widgetKey) {
  if (widgetKey == null || widgetKey.isEmpty) return null;
  return sourceRegistry[widgetKey];
}
