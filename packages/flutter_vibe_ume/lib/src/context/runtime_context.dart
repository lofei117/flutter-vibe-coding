import 'widget_runtime_descriptor.dart';

class ScreenSize {
  const ScreenSize({
    required this.width,
    required this.height,
    this.devicePixelRatio,
  });

  final double width;
  final double height;
  final double? devicePixelRatio;

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        if (devicePixelRatio != null) 'devicePixelRatio': devicePixelRatio,
      };
}

class WidgetTreeNode {
  const WidgetTreeNode({
    required this.summary,
    this.children = const [],
  });

  final WidgetNodeSummary summary;
  final List<WidgetTreeNode> children;

  Map<String, dynamic> toJson() => {
        ...summary.toJson(),
        if (children.isNotEmpty)
          'children': children.map((e) => e.toJson()).toList(),
      };
}

class WidgetTreeSnapshot {
  const WidgetTreeSnapshot({
    required this.mode,
    required this.maxDepth,
    required this.root,
  });

  /// One of: 'selected-subtree' | 'screen-summary' | 'full-tree'.
  final String mode;
  final int maxDepth;
  final WidgetTreeNode root;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'maxDepth': maxDepth,
        'root': root.toJson(),
      };
}

class RuntimeContext {
  const RuntimeContext({
    this.currentRoute,
    this.screenSize,
    this.widgetTree,
  });

  final String? currentRoute;
  final ScreenSize? screenSize;
  final WidgetTreeSnapshot? widgetTree;

  Map<String, dynamic> toJson() => {
        if (currentRoute != null) 'currentRoute': currentRoute,
        if (screenSize != null) 'screenSize': screenSize!.toJson(),
        if (widgetTree != null) 'widgetTree': widgetTree!.toJson(),
      };
}
