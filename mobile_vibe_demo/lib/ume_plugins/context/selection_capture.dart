import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../source_registry.dart';
import 'runtime_context.dart';
import 'selected_component_context.dart';
import 'widget_runtime_descriptor.dart' as ctx;

class CaptureOutcome {
  const CaptureOutcome({this.selection, this.runtimeContext, this.reason});

  final SelectedComponentContext? selection;
  final RuntimeContext? runtimeContext;
  final String? reason;

  bool get hasSelection => selection != null;
}

class SelectionCapture {
  /// Read the current selection from
  /// [WidgetInspectorService.instance.selection] (shared with UME's
  /// WidgetInfoInspector / WidgetDetailInspector / HitTest / ShowCode) and
  /// turn it into a [SelectedComponentContext] + [RuntimeContext] pair that
  /// matches the server-side schema.
  static CaptureOutcome captureCurrent({
    String source = 'tap-select',
    String sourcePlugin = 'WidgetInfoInspector',
  }) {
    final selection = WidgetInspectorService.instance.selection;
    final element = selection.currentElement;
    if (element == null) {
      return const CaptureOutcome(
        reason: 'No UME inspector selection. Use WidgetInfo/WidgetDetail first.',
      );
    }

    final widgetDescriptor = _buildDescriptor(
      element,
      selection.current,
      sourcePlugin: sourcePlugin,
    );

    final keyString = widgetDescriptor.key;
    final anchor = lookupSourceAnchor(keyString);

    final ctx.SourceLocation sourceLocation = anchor != null
        ? ctx.SourceLocation.available(
            file: anchor.file,
            line: anchor.line ?? 1,
            className: anchor.owner,
            methodName: anchor.method,
            package: anchor.package,
          )
        : ctx.SourceLocation.unavailable(
            keyString == null
                ? 'Selected widget has no stable key; cannot map to source.'
                : 'No anchor in source registry for key=$keyString.',
          );

    final codeContext = anchor != null
        ? CodeContextHint(
            candidateFiles: [anchor.file],
            candidateSymbols: anchor.candidateSymbols,
          )
        : null;

    final selectionContext = SelectedComponentContext(
      selectionId: 'sel_${DateTime.now().microsecondsSinceEpoch}',
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      source: source,
      confidence: anchor != null ? 'high' : 'medium',
      widget: widgetDescriptor,
      sourceLocation: sourceLocation,
      codeContext: codeContext,
    );

    return CaptureOutcome(
      selection: selectionContext,
      runtimeContext: _buildRuntimeContext(element, widgetDescriptor),
    );
  }

  static ctx.WidgetRuntimeDescriptor _buildDescriptor(
    Element element,
    RenderObject? renderObject, {
    required String sourcePlugin,
  }) {
    final widget = element.widget;
    final widgetType = widget.runtimeType.toString();
    final elementType = element.runtimeType.toString();
    final renderObjectType = renderObject?.runtimeType.toString();

    final keyString = _describeKey(widget.key);
    final text = _extractText(element);
    final tooltip = _extractTooltip(widget);
    final semanticLabel = _extractSemanticLabel(widget);
    final enabled = _extractEnabled(widget);

    final bounds = _extractBounds(renderObject);
    final depth = element.depth;
    final ancestorChain = _collectAncestors(element, maxDepth: 8);
    final children = _collectChildren(element, maxChildren: 6);

    final diagnostics = <String, dynamic>{
      'toStringShort': element.toStringShort(),
      'widgetRuntimeType': widgetType,
      if (renderObject != null)
        'paintBoundsSize': {
          'width': renderObject.paintBounds.size.width,
          'height': renderObject.paintBounds.size.height,
        },
    };

    return ctx.WidgetRuntimeDescriptor(
      widgetType: widgetType,
      elementType: elementType,
      renderObjectType: renderObjectType,
      key: keyString,
      text: text,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      enabled: enabled,
      bounds: bounds,
      depth: depth,
      ancestorChain: ancestorChain,
      children: children,
      diagnostics: diagnostics,
      umeInspector: ctx.UmeInspectorContext(
        sourcePlugin: sourcePlugin,
        inspectorSelectionId:
            'inspector_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
  }

  static RuntimeContext _buildRuntimeContext(
    Element element,
    ctx.WidgetRuntimeDescriptor descriptor,
  ) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final size = view?.physicalSize;
    final dpr = view?.devicePixelRatio ?? 1.0;

    final screenSize = size == null
        ? null
        : ScreenSize(
            width: size.width / dpr,
            height: size.height / dpr,
            devicePixelRatio: dpr,
          );

    final rootSummary = ctx.WidgetNodeSummary(
      widgetType: descriptor.widgetType,
      key: descriptor.key,
      text: descriptor.text,
      semanticLabel: descriptor.semanticLabel,
    );

    final childrenNodes = descriptor.children
        .map((c) => WidgetTreeNode(summary: c))
        .toList();

    return RuntimeContext(
      screenSize: screenSize,
      widgetTree: WidgetTreeSnapshot(
        mode: 'selected-subtree',
        maxDepth: 3,
        root: WidgetTreeNode(summary: rootSummary, children: childrenNodes),
      ),
    );
  }

  static String? _describeKey(Key? key) {
    if (key == null) return null;
    if (key is ValueKey<String>) return key.value;
    if (key is ValueKey) return key.value?.toString();
    return key.toString();
  }

  static String? _extractText(Element element) {
    String? found;
    void visit(Element child) {
      if (found != null) return;
      final widget = child.widget;
      if (widget is Text) {
        found = widget.data ?? widget.textSpan?.toPlainText();
        return;
      }
      if (widget is RichText) {
        found = widget.text.toPlainText();
        return;
      }
      child.visitChildren(visit);
    }

    final widget = element.widget;
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    try {
      element.visitChildren(visit);
    } catch (_) {
      // visit may not be safe in every lifecycle moment; ignore.
    }
    return found;
  }

  static String? _extractTooltip(Widget widget) {
    if (widget is Tooltip) return widget.message;
    return null;
  }

  static String? _extractSemanticLabel(Widget widget) {
    if (widget is Semantics) return widget.properties.label;
    if (widget is Image) return widget.semanticLabel;
    return null;
  }

  static bool? _extractEnabled(Widget widget) {
    try {
      final dynamic w = widget;
      // Most Material buttons expose onPressed; null => disabled.
      final onPressed = w.onPressed;
      if (onPressed == null) return false;
      return true;
    } catch (_) {
      return null;
    }
  }

  static ctx.Rect? _extractBounds(RenderObject? renderObject) {
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    try {
      final offset = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      return ctx.Rect(
        left: offset.dx,
        top: offset.dy,
        width: size.width,
        height: size.height,
      );
    } catch (_) {
      return null;
    }
  }

  static List<ctx.WidgetNodeSummary> _collectAncestors(
    Element element, {
    int maxDepth = 8,
  }) {
    final result = <ctx.WidgetNodeSummary>[];
    try {
      element.visitAncestorElements((ancestor) {
        result.add(_summarize(ancestor));
        return result.length < maxDepth;
      });
    } catch (_) {
      // ignore: ancestor traversal may be unsafe during some lifecycle states.
    }
    return result;
  }

  static List<ctx.WidgetNodeSummary> _collectChildren(
    Element element, {
    int maxChildren = 6,
  }) {
    final result = <ctx.WidgetNodeSummary>[];
    try {
      element.visitChildren((child) {
        if (result.length >= maxChildren) return;
        result.add(_summarize(child));
      });
    } catch (_) {
      // ignore.
    }
    return result;
  }

  static ctx.WidgetNodeSummary _summarize(Element element) {
    final widget = element.widget;
    final widgetType = widget.runtimeType.toString();
    final keyString = _describeKey(widget.key);
    final text = widget is Text
        ? (widget.data ?? widget.textSpan?.toPlainText())
        : null;

    ctx.SourceLocation? sourceLocation;
    final anchor = lookupSourceAnchor(keyString);
    if (anchor != null) {
      sourceLocation = ctx.SourceLocation.available(
        file: anchor.file,
        line: anchor.line ?? 1,
        className: anchor.owner,
        methodName: anchor.method,
        package: anchor.package,
      );
    }

    return ctx.WidgetNodeSummary(
      widgetType: widgetType,
      key: keyString,
      text: text,
      semanticLabel: _extractSemanticLabel(widget),
      sourceLocation: sourceLocation,
    );
  }
}

// Keep flutter/foundation imported (kDebugMode is referenced elsewhere).
// ignore: unused_element
bool _debugOnlySanityCheck() => kDebugMode;
