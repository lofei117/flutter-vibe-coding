import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'context/client_meta.dart';
import 'context/feedback_ticket.dart';
import 'server_config_store.dart';
import 'url_opener_stub.dart' if (dart.library.html) 'url_opener_web.dart'
    as url_opener;

typedef PageContextResolver = FeedbackPageContext Function(
    BuildContext context);

/// Maximum fraction of the viewport area a candidate Pick target may cover.
/// Anything larger is treated as a root-level container (Scaffold, Material,
/// page background) and skipped — picking those just paints the whole screen.
const double _kMaxPickAreaRatio = 0.6;

/// Wraps the host app and overlays a small floating "Send feedback" button.
///
/// Designed for profile/release builds. UME is debug-only, so non-engineering
/// roles use this panel to file feedback tickets that the server picks up,
/// runs through the agent + local CI, and publishes to a preview URL.
class FeedbackTicketLauncher extends StatefulWidget {
  const FeedbackTicketLauncher({
    super.key,
    required this.appName,
    required this.child,
    this.defaultServerUrl = 'http://127.0.0.1:8788',
    this.appVersion,
    this.gitSha,
    this.enabled = true,
    this.pageContextResolver,
    this.alignment = Alignment.bottomRight,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 16, 32),
  });

  final String appName;
  final Widget child;
  final String defaultServerUrl;
  final String? appVersion;
  final String? gitSha;
  final bool enabled;

  /// Optional hook so the host app can supply richer page context (e.g. the
  /// current route name from `GoRouter` / `Navigator`). When omitted we fall
  /// back to whatever `ModalRoute.of(context).settings.name` returns.
  final PageContextResolver? pageContextResolver;

  final Alignment alignment;
  final EdgeInsets padding;

  @override
  State<FeedbackTicketLauncher> createState() => _FeedbackTicketLauncherState();
}

/// Result returned by [FeedbackTicketSheet] when it is dismissed. The sheet
/// may pop with [requestPick] = true to ask the launcher to enter Pick mode
/// (and re-open the sheet afterwards with the preserved [instruction]).
class _SheetResult {
  const _SheetResult({this.requestPick = false, this.instruction});
  final bool requestPick;
  final String? instruction;
}

class _FeedbackTicketLauncherState extends State<FeedbackTicketLauncher> {
  final GlobalKey _captureKey = GlobalKey();

  /// Defers mounting the floating overlay until after the first frame so the
  /// underlying app's FocusScope has a real size. Without this, the View's
  /// initial focus traversal walks our overlay's `Focus` nodes before layout
  /// and crashes in `RenderSemanticsAnnotations.size`.
  bool _overlayReady = false;

  /// True while the user is picking an element. We render a transparent
  /// pointer-eating overlay that hit-tests through to the underlying widgets
  /// to capture text/bounds, then opens the sheet with that target.
  bool _pickMode = false;
  FeedbackRect? _pickHighlight;

  /// Re-entry guard: at most one sheet/pick flow can be active.
  bool _sheetOpen = false;

  /// Instruction text the user had typed in the sheet before requesting Pick;
  /// re-fed into the sheet that re-opens after a successful pick so input is
  /// not lost across the round trip.
  String? _pendingInstruction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _overlayReady = true);
    });
  }

  String _detectBuildMode() {
    if (kDebugMode) return 'debug';
    if (kProfileMode) return 'profile';
    if (kReleaseMode) return 'release';
    return 'unknown';
  }

  String _detectRuntimeTarget() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  ClientMeta _buildClientMeta(String serverUrl) => ClientMeta(
        appName: widget.appName,
        appVersion: widget.appVersion,
        gitSha: widget.gitSha,
        runtimeTarget: _detectRuntimeTarget(),
        buildMode: _detectBuildMode(),
        debugMode: kDebugMode,
        appLaunchMode: 'manual',
        serverUrl: serverUrl,
      );

  Future<FeedbackScreenshot?> _captureScreenshot() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();
      // Cap inline size at ~3MB to stay under the server limit.
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        return null;
      }
      return FeedbackScreenshot(
        mimeType: 'image/png',
        dataBase64: base64Encode(bytes),
      );
    } catch (_) {
      return null;
    }
  }

  FeedbackPageContext _capturePageContext(BuildContext sheetCtx) {
    if (widget.pageContextResolver != null) {
      try {
        return widget.pageContextResolver!(sheetCtx);
      } catch (_) {
        // Fall through to default lookup.
      }
    }
    String? routeName;
    final hostCtx = _captureKey.currentContext;
    if (hostCtx != null) {
      final modal = ModalRoute.of(hostCtx);
      routeName = modal?.settings.name;
    }
    return FeedbackPageContext(
      route: routeName,
      pageId: routeName,
      title: routeName,
    );
  }

  /// When mounted via [MaterialApp.builder], the [Navigator] sits inside the
  /// `child` we wrap, which makes it a *descendant* of our floating button —
  /// not an ancestor. Walking up from the button context will not find it,
  /// so we walk down from [_captureKey] (which is the [RepaintBoundary]
  /// directly above the navigator) to grab the live [NavigatorState].
  NavigatorState? _findNavigator() {
    final element = _captureKey.currentContext as Element?;
    if (element == null) return null;
    NavigatorState? found;
    void visit(Element child) {
      if (found != null) return;
      if (child is StatefulElement && child.state is NavigatorState) {
        found = child.state as NavigatorState;
        return;
      }
      child.visitChildren(visit);
    }

    element.visitChildren(visit);
    return found;
  }

  Future<void> _openSheet(
    BuildContext anchorCtx, {
    FeedbackTarget? target,
    String? presetInstruction,
  }) async {
    if (_sheetOpen || _pickMode) return;
    setState(() => _sheetOpen = true);
    try {
      final store =
          ServerConfigStore(defaultServerUrl: widget.defaultServerUrl);
      String serverUrl;
      try {
        serverUrl = await store.loadServerUrl();
      } catch (_) {
        serverUrl = widget.defaultServerUrl;
      }
      if (!mounted) return;
      final pageContext = _capturePageContext(anchorCtx);
      final screenshot = await _captureScreenshot();
      if (!mounted) return;

      final navigator = _findNavigator();
      final sheetContext = navigator?.context ?? anchorCtx;

      _SheetResult? result;
      try {
        result = await showModalBottomSheet<_SheetResult>(
          context: sheetContext,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Theme.of(sheetContext).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (modalCtx) {
            return FeedbackTicketSheet(
              serverUrl: serverUrl,
              clientMeta: _buildClientMeta(serverUrl),
              pageContext: pageContext,
              target: target,
              screenshot: screenshot,
              initialInstruction: presetInstruction,
            );
          },
        );
      } catch (error, stack) {
        debugPrint(
            '[FeedbackTicketLauncher] failed to open sheet: $error\n$stack');
      }

      if (!mounted) return;
      final pickResult = result;
      if (pickResult != null && pickResult.requestPick) {
        // The sheet's pop animation has already advanced by the time we
        // resume here, so the pick overlay can mount on the very next frame
        // without the bottom-sheet barrier eating the tap.
        final preset = pickResult.instruction;
        setState(() {
          _pendingInstruction = preset;
          _pickMode = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sheetOpen = false);
      } else {
        _sheetOpen = false;
      }
    }
  }

  /// Best-effort element capture: walk the hit-test path under the press to
  /// pick up the topmost paragraph text. Falls back to page-level feedback
  /// when nothing useful is found.
  FeedbackTarget? _captureLongPress(LongPressStartDetails details) {
    return _captureTargetAt(details.globalPosition) ??
        FeedbackTarget(
          bounds: FeedbackRect(
            left: details.globalPosition.dx - 12,
            top: details.globalPosition.dy - 12,
            width: 24,
            height: 24,
          ),
        );
  }

  /// Hit-test at [globalPosition] and synthesize a [FeedbackTarget] that
  /// includes the element's text (when available) and its on-screen bounds.
  /// Used by both long-press capture and the dedicated Pick mode.
  ///
  /// Selection rules:
  /// 1. Prefer the topmost [RenderParagraph] in the hit-test path (gives us
  ///    real text + tight bounds).
  /// 2. Otherwise pick the smallest sized [RenderBox] under the tap that is
  ///    big enough to be a real interactive element (>= 4x4) but smaller than
  ///    [_kMaxPickAreaRatio] of the screen — root-level Scaffold/Material
  ///    fills the whole viewport and is useless as a "target".
  FeedbackTarget? _captureTargetAt(Offset globalPosition) {
    try {
      final selected = _renderObjectsUnder(globalPosition);

      final mq = MediaQuery.maybeOf(context);
      final viewportArea =
          mq == null ? double.infinity : mq.size.width * mq.size.height;
      final maxArea = viewportArea * _kMaxPickAreaRatio;

      String? text;
      Rect? rect;
      for (final ro in selected) {
        if (ro is RenderParagraph) {
          final t = ro.text.toPlainText().trim();
          if (t.isEmpty) continue;
          text = t;
          rect = _renderRectGlobal(ro);
          break;
        }
      }

      if (rect == null) {
        RenderBox? best;
        double bestArea = double.infinity;
        for (final ro in selected) {
          if (ro is! RenderBox) continue;
          if (!ro.hasSize) continue;
          final size = ro.size;
          if (size.width < 4 || size.height < 4) continue;
          final area = size.width * size.height;
          if (area > maxArea) continue;
          if (area < bestArea) {
            best = ro;
            bestArea = area;
          }
        }
        if (best != null) rect = _renderRectGlobal(best);
      }

      if (text == null && rect == null) return null;
      final semantic = _findSemanticLabel(selected);
      return FeedbackTarget(
        text: text ?? semantic,
        semanticLabel: semantic ?? text,
        bounds: rect == null
            ? null
            : FeedbackRect(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
              ),
      );
    } catch (_) {
      return null;
    }
  }

  List<RenderObject> _renderObjectsUnder(Offset globalPosition) {
    final root = _captureKey.currentContext?.findRenderObject();
    if (root == null) return const [];

    final hits = <_RenderObjectHit>[];

    void visit(RenderObject object, int depth) {
      if (object is RenderBox && object.hasSize) {
        final rect = _renderRectGlobal(object);
        if (rect != null && rect.contains(globalPosition)) {
          hits.add(_RenderObjectHit(object, rect, depth));
        }
      }
      object.visitChildren((child) => visit(child, depth + 1));
    }

    visit(root, 0);
    hits.sort((a, b) {
      final depthCompare = b.depth.compareTo(a.depth);
      if (depthCompare != 0) return depthCompare;
      return a.area.compareTo(b.area);
    });
    return hits.map((hit) => hit.object).toList(growable: false);
  }

  String? _findSemanticLabel(List<RenderObject> selected) {
    for (final ro in selected) {
      final label = ro.debugSemantics?.label.trim();
      if (label != null && label.isNotEmpty) return label;
    }
    return null;
  }

  Rect? _renderRectGlobal(RenderBox box) {
    try {
      final transform = box.getTransformTo(null);
      return MatrixUtils.transformRect(transform, Offset.zero & box.size);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handlePickPointer(Offset globalPosition) async {
    final target = _captureTargetAt(globalPosition);
    if (target?.bounds != null) {
      setState(() => _pickHighlight = target!.bounds);
    }
    // Brief flash so the user sees what they picked, then open the sheet.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    final preset = _pendingInstruction;
    setState(() {
      _pickMode = false;
      _pickHighlight = null;
      _pendingInstruction = null;
    });
    if (!mounted) return;
    _openSheet(context, target: target, presetInstruction: preset);
  }

  @override
  Widget build(BuildContext context) {
    final wrappedChild = RepaintBoundary(
      key: _captureKey,
      child: widget.child,
    );

    // Hide the overlay until enabled AND first layout is done so initial focus
    // traversal doesn't crash on unsized FocusScopes inside our Stack.
    if (!widget.enabled || !_overlayReady) return wrappedChild;

    return Stack(
      fit: StackFit.expand,
      children: [
        wrappedChild,
        // ExcludeFocus keeps the floating buttons out of the global focus
        // tree so the View's reading-order traversal never has to compute
        // their semantic bounds. Pointer events still hit them normally.
        Positioned.fill(
          child: ExcludeFocus(
            excluding: true,
            child: IgnorePointer(
              ignoring: _pickMode,
              child: SafeArea(
                child: Align(
                  alignment: widget.alignment,
                  child: Padding(
                    padding: widget.padding,
                    child: _buildToolbar(),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_pickMode) _buildPickLayer(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Colors.transparent,
      elevation: 6,
      shape: const StadiumBorder(),
      child: Builder(
        builder: (anchorCtx) {
          return GestureDetector(
            onLongPressStart: (details) {
              if (_sheetOpen || _pickMode) return;
              final target = _captureLongPress(details);
              _openSheet(anchorCtx, target: target);
            },
            child: FilledButton.tonalIcon(
              onPressed:
                  _sheetOpen || _pickMode ? null : () => _openSheet(anchorCtx),
              icon: const Icon(Icons.feedback_outlined, size: 18),
              label: const Text('Send feedback'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPickLayer() {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _handlePickPointer(event.position),
              child: Container(color: Colors.black.withValues(alpha: 0.04)),
            ),
          ),
          if (_pickHighlight != null)
            Positioned(
              left: _pickHighlight!.left,
              top: _pickHighlight!.top,
              width: _pickHighlight!.width,
              height: _pickHighlight!.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.25),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Material(
                color: Colors.green.shade700,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tap an element to pick',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _pickMode = false;
                          _pickHighlight = null;
                          _pendingInstruction = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenderObjectHit {
  const _RenderObjectHit(this.object, this.rect, this.depth);

  final RenderObject object;
  final Rect rect;
  final int depth;

  double get area => rect.width * rect.height;
}

/// Stateful bottom sheet that shows the form, submits the ticket, and
/// streams events back from the server until a terminal state is reached.
class FeedbackTicketSheet extends StatefulWidget {
  const FeedbackTicketSheet({
    super.key,
    required this.serverUrl,
    required this.clientMeta,
    required this.pageContext,
    this.target,
    this.screenshot,
    this.initialInstruction,
  });

  final String serverUrl;
  final ClientMeta clientMeta;
  final FeedbackPageContext pageContext;
  final FeedbackTarget? target;
  final FeedbackScreenshot? screenshot;

  /// Restores user-typed instruction text after a Pick round-trip.
  final String? initialInstruction;

  @override
  State<FeedbackTicketSheet> createState() => _FeedbackTicketSheetState();
}

enum _SheetStage { form, submitting, tracking, done }

class _FeedbackTicketSheetState extends State<FeedbackTicketSheet> {
  late final TextEditingController _instructionController;
  late final TextEditingController _serverUrlController;
  late final AiVibeApiClient _api;
  StreamSubscription<FeedbackTicketEvent>? _eventSub;

  _SheetStage _stage = _SheetStage.form;
  final List<FeedbackTicketEvent> _events = [];
  FeedbackTicket? _ticket;
  String? _errorMessage;
  bool _includeScreenshot = true;
  bool _skipTests = true;
  String _buildFlavor = 'release';

  @override
  void initState() {
    super.initState();
    _instructionController = TextEditingController(
      text: widget.initialInstruction ?? '',
    );
    _serverUrlController = TextEditingController(text: widget.serverUrl);
    _api = AiVibeApiClient();
  }

  void _requestPick() {
    Navigator.of(context).pop(
      _SheetResult(
        requestPick: true,
        instruction: _instructionController.text,
      ),
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _instructionController.dispose();
    _serverUrlController.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _submit() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) {
      setState(() => _errorMessage = '请填写需要 AI 修改的内容。');
      return;
    }
    final serverUrl = _serverUrlController.text.trim();
    if (serverUrl.isEmpty) {
      setState(() => _errorMessage = '请填写服务端地址。');
      return;
    }

    setState(() {
      _stage = _SheetStage.submitting;
      _errorMessage = null;
      _events.clear();
      _ticket = null;
    });

    try {
      await ServerConfigStore(defaultServerUrl: serverUrl)
          .saveServerUrl(serverUrl);
    } catch (_) {
      // Best effort; persistence failures should not block the ticket flow.
    }

    try {
      final request = FeedbackTicketRequest(
        instruction: instruction,
        clientMeta: widget.clientMeta,
        pageContext: widget.pageContext,
        target: widget.target,
        screenshot: _includeScreenshot ? widget.screenshot : null,
      );
      final created = await _api.createFeedbackTicket(
        serverUrl: serverUrl,
        request: request,
      );
      if (!mounted) return;
      setState(() {
        _ticket = created;
        _stage = _SheetStage.tracking;
      });

      // Fire-and-forget process trigger; events stream owns the lifecycle.
      unawaited(
        _api
            .processFeedbackTicket(
          serverUrl: serverUrl,
          ticketId: created.ticketId,
          buildFlavor: _buildFlavor,
          skipTests: _skipTests,
        )
            .catchError((Object error) {
          if (!mounted) return created;
          setState(() => _errorMessage = '$error');
          return created;
        }),
      );

      _eventSub = _api
          .streamFeedbackEvents(
        serverUrl: serverUrl,
        ticketId: created.ticketId,
      )
          .listen(
        (event) {
          if (!mounted) return;
          setState(() => _events.add(event));
        },
        onDone: () async {
          if (!mounted) return;
          try {
            final finalTicket = await _api.fetchFeedbackTicket(
              serverUrl: serverUrl,
              ticketId: created.ticketId,
            );
            if (!mounted) return;
            setState(() {
              _ticket = finalTicket;
              _stage = _SheetStage.done;
            });
          } catch (error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = '$error';
              _stage = _SheetStage.done;
            });
          }
        },
        onError: (Object error, StackTrace _) {
          if (!mounted) return;
          setState(() {
            _errorMessage = '$error';
            _stage = _SheetStage.done;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$error';
        _stage = _SheetStage.form;
      });
    }
  }

  Future<void> _copyPreviewUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preview URL copied to clipboard.')),
    );
  }

  Future<void> _openPreviewUrl(String url) async {
    final ok = await url_opener.openUrlInNewTab(url);
    if (!mounted) return;
    if (!ok) {
      // Fall back to clipboard on platforms where we can't open URLs directly
      // (mobile/desktop builds, or popup blockers on web).
      await _copyPreviewUrl(url);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Send feedback',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '提交后会触发 AI 修改 + 本地 CI + Web 预览。仅 Profile/Release 包推荐使用。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (_stage == _SheetStage.form ||
                    _stage == _SheetStage.submitting)
                  _buildForm()
                else
                  _buildTrackingView(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final route = widget.pageContext.route ?? '(unknown)';
    final hasShot = widget.screenshot != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TargetPanel(
          target: widget.target,
          onPickPressed: _stage == _SheetStage.submitting ? null : _requestPick,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instructionController,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '描述需要 AI 修改的内容',
            border: OutlineInputBorder(),
            hintText: '例：把首页按钮改成绿色，并把文案改成 Start',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serverUrlController,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            border: OutlineInputBorder(),
            hintText: 'http://127.0.0.1:8788',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _Chip(label: 'route: $route'),
            _Chip(label: 'mode: ${widget.clientMeta.buildMode ?? "?"}'),
            _Chip(label: 'platform: ${widget.clientMeta.runtimeTarget ?? "?"}'),
            if (hasShot) const _Chip(label: 'screenshot: yes'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _includeScreenshot && hasShot,
                onChanged: hasShot
                    ? (v) => setState(() => _includeScreenshot = v)
                    : null,
                title: const Text('携带截图'),
                subtitle: !hasShot ? const Text('截图不可用（页面较大或权限受限）') : null,
              ),
            ),
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _skipTests,
                onChanged: (v) => setState(() => _skipTests = v),
                title: const Text('跳过 flutter test'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Build:'),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('release'),
              selected: _buildFlavor == 'release',
              onSelected: (_) => setState(() => _buildFlavor = 'release'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('profile'),
              selected: _buildFlavor == 'profile',
              onSelected: (_) => setState(() => _buildFlavor = 'profile'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _stage == _SheetStage.submitting
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _stage == _SheetStage.submitting ? null : _submit,
              icon: _stage == _SheetStage.submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('提交'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrackingView() {
    final ticket = _ticket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ticket != null) ...[
          Row(
            children: [
              Text(
                '#${ticket.ticketId}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: ticket.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(ticket.instruction),
          const SizedBox(height: 12),
        ],
        Container(
          height: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            itemCount: _events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final e = _events[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      e.stage,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.message,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (_stage == _SheetStage.done && ticket != null) ...[
          if (ticket.previewUrl != null) ...[
            Text(
              'Preview URL',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      ticket.previewUrl!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy preview URL',
                    onPressed: () => _copyPreviewUrl(ticket.previewUrl!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: 'Open preview in new tab',
                    onPressed: () => _openPreviewUrl(ticket.previewUrl!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tip: open in a new browser tab. The preview lives on the AI '
              'server (port 8788), not on the dev server (port 8090).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ],
          if (ticket.changedFiles.isNotEmpty) ...[
            Text(
              'Changed files',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            ...ticket.changedFiles.map(
              (f) => Text(
                '· $f',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ),
        ],
      ],
    );
  }
}

class _TargetPanel extends StatelessWidget {
  const _TargetPanel({required this.target, required this.onPickPressed});

  final FeedbackTarget? target;
  final VoidCallback? onPickPressed;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final hasTarget = t != null;
    final text = t?.text?.trim();
    final bounds = t?.bounds;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: hasTarget
            ? Colors.green.withValues(alpha: 0.06)
            : Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasTarget
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasTarget ? Icons.crop_free : Icons.info_outline,
                size: 16,
                color:
                    hasTarget ? Colors.green.shade700 : Colors.amber.shade800,
              ),
              const SizedBox(width: 6),
              Text(
                hasTarget ? '已选中元素' : '未选中元素（整页修改）',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      hasTarget ? Colors.green.shade800 : Colors.amber.shade900,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPickPressed,
                icon: const Icon(Icons.ads_click, size: 16),
                label: Text(hasTarget ? '重新选取' : '选取元素'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          if (hasTarget) ...[
            const SizedBox(height: 4),
            if (text != null && text.isNotEmpty)
              Text(
                'text: $text',
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            else
              const Text(
                'text: (无文本，命中的是图标/容器)',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (bounds != null) ...[
              const SizedBox(height: 2),
              Text(
                'bounds: '
                '(${bounds.left.toStringAsFixed(0)}, ${bounds.top.toStringAsFixed(0)}) '
                '${bounds.width.toStringAsFixed(0)}×${bounds.height.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.black54,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 2),
            const Text(
              '不选取也可以提交，但 AI 会按整页或描述定位代码。',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color _color() {
    switch (status) {
      case 'deployed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'ci_running':
      case 'applied':
      case 'planned':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
