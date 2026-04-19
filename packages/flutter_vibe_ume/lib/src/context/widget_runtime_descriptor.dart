class Rect {
  const Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory Rect.fromJson(Map<String, dynamic> json) => Rect(
        left: (json['left'] as num).toDouble(),
        top: (json['top'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );
}

abstract class SourceLocation {
  const SourceLocation();

  String get status;

  Map<String, dynamic> toJson();

  factory SourceLocation.available({
    required String file,
    required int line,
    int? column,
    String? package,
    String? className,
    String? methodName,
  }) =>
      SourceLocationAvailable(
        file: file,
        line: line,
        column: column,
        package: package,
        className: className,
        methodName: methodName,
      );

  factory SourceLocation.unavailable(String reason) =>
      SourceLocationUnavailable(reason: reason);

  factory SourceLocation.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status == 'available') {
      return SourceLocationAvailable(
        file: json['file'] as String,
        line: json['line'] as int,
        column: json['column'] as int?,
        package: json['package'] as String?,
        className: json['className'] as String?,
        methodName: json['methodName'] as String?,
      );
    }
    return SourceLocationUnavailable(
      reason: (json['reason'] as String?) ?? 'unknown',
    );
  }
}

class SourceLocationAvailable extends SourceLocation {
  const SourceLocationAvailable({
    required this.file,
    required this.line,
    this.column,
    this.package,
    this.className,
    this.methodName,
  });

  final String file;
  final int line;
  final int? column;
  final String? package;
  final String? className;
  final String? methodName;

  @override
  String get status => 'available';

  @override
  Map<String, dynamic> toJson() => {
        'status': 'available',
        'file': file,
        'line': line,
        if (column != null) 'column': column,
        if (package != null) 'package': package,
        if (className != null) 'className': className,
        if (methodName != null) 'methodName': methodName,
      };
}

class SourceLocationUnavailable extends SourceLocation {
  const SourceLocationUnavailable({required this.reason});

  final String reason;

  @override
  String get status => 'unavailable';

  @override
  Map<String, dynamic> toJson() => {
        'status': 'unavailable',
        'reason': reason,
      };
}

class WidgetNodeSummary {
  const WidgetNodeSummary({
    required this.widgetType,
    this.key,
    this.text,
    this.semanticLabel,
    this.sourceLocation,
  });

  final String widgetType;
  final String? key;
  final String? text;
  final String? semanticLabel;
  final SourceLocation? sourceLocation;

  Map<String, dynamic> toJson() => {
        'widgetType': widgetType,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (semanticLabel != null) 'semanticLabel': semanticLabel,
        if (sourceLocation != null) 'sourceLocation': sourceLocation!.toJson(),
      };

  factory WidgetNodeSummary.fromJson(Map<String, dynamic> json) =>
      WidgetNodeSummary(
        widgetType: json['widgetType'] as String,
        key: json['key'] as String?,
        text: json['text'] as String?,
        semanticLabel: json['semanticLabel'] as String?,
        sourceLocation: json['sourceLocation'] is Map<String, dynamic>
            ? SourceLocation.fromJson(
                json['sourceLocation'] as Map<String, dynamic>,
              )
            : null,
      );
}

class UmeInspectorContext {
  const UmeInspectorContext({
    this.sourcePlugin,
    this.inspectorSelectionId,
    this.rawSummary,
  });

  /// One of: 'WidgetInfoInspector', 'WidgetDetailInspector', 'ShowCode',
  /// 'HitTest', 'unknown'.
  final String? sourcePlugin;
  final String? inspectorSelectionId;
  final Map<String, dynamic>? rawSummary;

  Map<String, dynamic> toJson() => {
        if (sourcePlugin != null) 'sourcePlugin': sourcePlugin,
        if (inspectorSelectionId != null)
          'inspectorSelectionId': inspectorSelectionId,
        if (rawSummary != null) 'rawSummary': rawSummary,
      };
}

class WidgetRuntimeDescriptor {
  const WidgetRuntimeDescriptor({
    required this.widgetType,
    this.elementType,
    this.renderObjectType,
    this.key,
    this.text,
    this.semanticLabel,
    this.tooltip,
    this.enabled,
    this.bounds,
    this.depth,
    this.ancestorChain = const [],
    this.children = const [],
    this.diagnostics,
    this.umeInspector,
  });

  final String widgetType;
  final String? elementType;
  final String? renderObjectType;
  final String? key;
  final String? text;
  final String? semanticLabel;
  final String? tooltip;
  final bool? enabled;
  final Rect? bounds;
  final int? depth;
  final List<WidgetNodeSummary> ancestorChain;
  final List<WidgetNodeSummary> children;
  final Map<String, dynamic>? diagnostics;
  final UmeInspectorContext? umeInspector;

  Map<String, dynamic> toJson() => {
        'widgetType': widgetType,
        if (elementType != null) 'elementType': elementType,
        if (renderObjectType != null) 'renderObjectType': renderObjectType,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (semanticLabel != null) 'semanticLabel': semanticLabel,
        if (tooltip != null) 'tooltip': tooltip,
        if (enabled != null) 'enabled': enabled,
        if (bounds != null) 'bounds': bounds!.toJson(),
        if (depth != null) 'depth': depth,
        'ancestorChain': ancestorChain.map((e) => e.toJson()).toList(),
        'children': children.map((e) => e.toJson()).toList(),
        if (diagnostics != null) 'diagnostics': diagnostics,
        if (umeInspector != null) 'umeInspector': umeInspector!.toJson(),
      };
}
