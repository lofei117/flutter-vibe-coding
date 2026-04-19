class SourceAnchor {
  const SourceAnchor({
    required this.file,
    required this.symbol,
    required this.owner,
    this.line,
    this.method = 'build',
    required this.package,
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

typedef SourceAnchorResolver = SourceAnchor? Function(String? widgetKey);
