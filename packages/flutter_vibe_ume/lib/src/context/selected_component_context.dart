import 'widget_runtime_descriptor.dart';

class CodeContextHint {
  const CodeContextHint({
    this.candidateFiles = const [],
    this.candidateSymbols,
    this.snippet,
  });

  final List<String> candidateFiles;
  final List<String>? candidateSymbols;
  final CodeSnippet? snippet;

  Map<String, dynamic> toJson() => {
        'candidateFiles': candidateFiles,
        if (candidateSymbols != null) 'candidateSymbols': candidateSymbols,
        if (snippet != null) 'snippet': snippet!.toJson(),
      };
}

class CodeSnippet {
  const CodeSnippet({
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.content,
  });

  final String file;
  final int startLine;
  final int endLine;
  final String content;

  Map<String, dynamic> toJson() => {
        'file': file,
        'startLine': startLine,
        'endLine': endLine,
        'content': content,
      };
}

class SelectedComponentContext {
  const SelectedComponentContext({
    required this.selectionId,
    required this.capturedAt,
    required this.source,
    required this.confidence,
    required this.widget,
    required this.sourceLocation,
    this.codeContext,
  });

  final String selectionId;
  final String capturedAt;

  /// One of: 'tap-select' | 'tree-picker' | 'manual' | 'unknown'.
  final String source;

  /// One of: 'high' | 'medium' | 'low'.
  final String confidence;

  final WidgetRuntimeDescriptor widget;
  final SourceLocation sourceLocation;
  final CodeContextHint? codeContext;

  Map<String, dynamic> toJson() => {
        'selectionId': selectionId,
        'capturedAt': capturedAt,
        'source': source,
        'confidence': confidence,
        'widget': widget.toJson(),
        'sourceLocation': sourceLocation.toJson(),
        if (codeContext != null) 'codeContext': codeContext!.toJson(),
      };

  String summarize() {
    final parts = <String>[widget.widgetType];
    if (widget.text != null && widget.text!.isNotEmpty) {
      parts.add('"${widget.text}"');
    }
    if (widget.key != null) {
      parts.add('key=${widget.key}');
    }
    if (sourceLocation is SourceLocationAvailable) {
      final s = sourceLocation as SourceLocationAvailable;
      parts.add('${s.file}:${s.line}');
    } else if (sourceLocation is SourceLocationUnavailable) {
      parts.add('source=unavailable');
    }
    return parts.join(' ');
  }
}
