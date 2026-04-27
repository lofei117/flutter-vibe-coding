import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../source_anchor.dart';
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
    required SourceAnchorResolver resolveSourceAnchor,
  }) {
    final selection = WidgetInspectorService.instance.selection;
    final element = selection.currentElement;
    if (element == null) {
      return const CaptureOutcome(
        reason:
            'No UME inspector selection. Use WidgetInfo/WidgetDetail first.',
      );
    }

    final inspectorSummary = _readInspectorSummary(
      currentRenderObject: selection.current,
      currentElement: element,
      candidates: selection.candidates,
    );

    final widgetDescriptor = _buildDescriptor(
      element,
      selection.current,
      sourcePlugin: sourcePlugin,
      resolveSourceAnchor: resolveSourceAnchor,
      inspectorSummary: inspectorSummary,
    );

    final resolvedAnchor = _resolveNearestAnchor(
      element,
      resolveSourceAnchor: resolveSourceAnchor,
    );
    final anchor = resolvedAnchor?.anchor;

    final inspectorLocation = _readInspectorCreationLocation(inspectorSummary);

    final ctx.SourceLocation sourceLocation = inspectorLocation != null
        ? inspectorLocation
        : anchor != null
            ? ctx.SourceLocation.available(
                file: anchor.file,
                line: anchor.line ?? 1,
                className: anchor.owner,
                methodName: anchor.method,
                package: anchor.package,
              )
            : ctx.SourceLocation.unavailable(
                widgetDescriptor.key == null
                    ? 'Selected widget has no matching keyed ancestor/descendant; cannot map to source.'
                    : 'No anchor in source registry for selected widget or nearby keyed widgets.',
              );

    final codeContext = inspectorLocation is ctx.SourceLocationAvailable
        ? CodeContextHint(
            candidateFiles: [inspectorLocation.file],
            candidateSymbols: anchor?.candidateSymbols,
          )
        : anchor != null
            ? CodeContextHint(
                candidateFiles: [anchor.file],
                candidateSymbols: anchor.candidateSymbols,
              )
            : null;

    final selectionContext = SelectedComponentContext(
      selectionId: 'sel_${DateTime.now().microsecondsSinceEpoch}',
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      source: source,
      confidence: switch (resolvedAnchor?.kind) {
        _AnchorMatchKind.direct => 'high',
        _AnchorMatchKind.descendant || _AnchorMatchKind.ancestor => 'medium',
        null => 'low',
      },
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
    required SourceAnchorResolver resolveSourceAnchor,
    required Map<String, dynamic>? inspectorSummary,
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
    final ancestorChain = _collectAncestors(
      element,
      maxDepth: 8,
      resolveSourceAnchor: resolveSourceAnchor,
    );
    final children = _collectChildren(
      element,
      maxChildren: 6,
      resolveSourceAnchor: resolveSourceAnchor,
    );

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
        rawSummary: inspectorSummary,
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

    final childrenNodes =
        descriptor.children.map((c) => WidgetTreeNode(summary: c)).toList();

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
    required SourceAnchorResolver resolveSourceAnchor,
  }) {
    final result = <ctx.WidgetNodeSummary>[];
    try {
      element.visitAncestorElements((ancestor) {
        result.add(
          _summarize(ancestor, resolveSourceAnchor: resolveSourceAnchor),
        );
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
    required SourceAnchorResolver resolveSourceAnchor,
  }) {
    final result = <ctx.WidgetNodeSummary>[];
    try {
      element.visitChildren((child) {
        if (result.length >= maxChildren) return;
        result.add(_summarize(child, resolveSourceAnchor: resolveSourceAnchor));
      });
    } catch (_) {
      // ignore.
    }
    return result;
  }

  static ctx.WidgetNodeSummary _summarize(
    Element element, {
    required SourceAnchorResolver resolveSourceAnchor,
  }) {
    final widget = element.widget;
    final widgetType = widget.runtimeType.toString();
    final keyString = _describeKey(widget.key);
    final text =
        widget is Text ? (widget.data ?? widget.textSpan?.toPlainText()) : null;

    ctx.SourceLocation? sourceLocation;
    final anchor = resolveSourceAnchor(keyString);
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

  static _ResolvedAnchor? _resolveNearestAnchor(
    Element element, {
    required SourceAnchorResolver resolveSourceAnchor,
  }) {
    final directKey = _describeKey(element.widget.key);
    final directAnchor = resolveSourceAnchor(directKey);
    if (directAnchor != null) {
      return _ResolvedAnchor(
        anchor: directAnchor,
        kind: _AnchorMatchKind.direct,
      );
    }

    final descendantAnchor = _searchNearbyElements(
      roots: _collectDescendants(element, maxNodes: 24),
      resolveSourceAnchor: resolveSourceAnchor,
      kind: _AnchorMatchKind.descendant,
    );
    if (descendantAnchor != null) return descendantAnchor;

    return _searchNearbyElements(
      roots: _collectAncestorsRaw(element, maxNodes: 12),
      resolveSourceAnchor: resolveSourceAnchor,
      kind: _AnchorMatchKind.ancestor,
    );
  }

  static List<Element> _collectDescendants(Element element,
      {int maxNodes = 24}) {
    final out = <Element>[];
    final queue = <Element>[];
    try {
      element.visitChildren(queue.add);
      while (queue.isNotEmpty && out.length < maxNodes) {
        final next = queue.removeAt(0);
        out.add(next);
        if (out.length >= maxNodes) break;
        next.visitChildren(queue.add);
      }
    } catch (_) {
      // ignore.
    }
    return out;
  }

  static List<Element> _collectAncestorsRaw(Element element,
      {int maxNodes = 12}) {
    final out = <Element>[];
    try {
      element.visitAncestorElements((ancestor) {
        out.add(ancestor);
        return out.length < maxNodes;
      });
    } catch (_) {
      // ignore.
    }
    return out;
  }

  static _ResolvedAnchor? _searchNearbyElements({
    required List<Element> roots,
    required SourceAnchorResolver resolveSourceAnchor,
    required _AnchorMatchKind kind,
  }) {
    for (final candidate in roots) {
      final key = _describeKey(candidate.widget.key);
      final anchor = resolveSourceAnchor(key);
      if (anchor != null) {
        return _ResolvedAnchor(anchor: anchor, kind: kind);
      }
    }
    return null;
  }

  static Map<String, dynamic>? _readInspectorSummary({
    required RenderObject? currentRenderObject,
    required Element currentElement,
    required List<RenderObject> candidates,
  }) {
    final tried = <RenderObject?>[
      currentRenderObject,
      currentElement.renderObject,
      ...candidates,
    ];
    for (final renderObject in tried) {
      final summary = _readSummaryForRenderObject(renderObject);
      if (summary == null) continue;
      if (summary.containsKey('creationLocation')) {
        return summary;
      }
    }
    for (final renderObject in tried) {
      final summary = _readSummaryForRenderObject(renderObject);
      if (summary != null) return summary;
    }
    return null;
  }

  static Map<String, dynamic>? _readSummaryForRenderObject(
    RenderObject? renderObject,
  ) {
    if (renderObject == null) return null;
    try {
      final widgetId = WidgetInspectorService.instance
          // ignore: invalid_use_of_protected_member
          .toId(renderObject.toDiagnosticsNode(), '');
      if (widgetId == null) return null;
      final infoStr = WidgetInspectorService.instance.getSelectedSummaryWidget(
        widgetId,
        '',
      );
      final raw = json.decode(infoStr);
      if (raw is! Map<String, dynamic>) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  static ctx.SourceLocation? _readInspectorCreationLocation(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return null;
    try {
      final creation = raw['creationLocation'];
      if (creation is! Map) return null;
      final file = creation['file'];
      final line = creation['line'];
      final column = creation['column'];
      final lineNumber = line is num ? line.toInt() : null;
      final columnNumber = column is num ? column.toInt() : null;
      if (file is! String ||
          file.isEmpty ||
          lineNumber == null ||
          lineNumber <= 0) {
        return null;
      }
      return ctx.SourceLocation.available(
        file: _normalizeCreationLocationFile(file),
        line: lineNumber,
        column: columnNumber,
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalizeCreationLocationFile(String file) {
    final packageMatch = RegExp(r'^package:([^/]+)/(.+)$').firstMatch(file);
    if (packageMatch != null) {
      final packagePath = packageMatch.group(2)!;
      if (packagePath.startsWith('lib/')) {
        return packagePath;
      }
      return 'lib/$packagePath';
    }
    const packageToken = '/packages/';
    final packageIndex = file.lastIndexOf(packageToken);
    if (packageIndex >= 0) {
      return file.substring(packageIndex + 1);
    }
    const libToken = '/lib/';
    final libIndex = file.lastIndexOf(libToken);
    if (libIndex >= 0) {
      return 'lib/${file.substring(libIndex + libToken.length)}';
    }
    return file;
  }
}

// Keep flutter/foundation imported (kDebugMode is referenced elsewhere).
// ignore: unused_element
bool _debugOnlySanityCheck() => kDebugMode;

enum _AnchorMatchKind { direct, descendant, ancestor }

class _ResolvedAnchor {
  const _ResolvedAnchor({required this.anchor, required this.kind});

  final SourceAnchor anchor;
  final _AnchorMatchKind kind;
}
