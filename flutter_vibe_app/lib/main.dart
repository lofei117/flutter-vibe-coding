import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_vibe_ume/flutter_vibe_ume.dart';

import 'app.dart';
import 'source_registry.dart';

const String _kAppName = 'flutter_vibe_app';
const String _kDefaultServerUrl = 'http://127.0.0.1:8788';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    runApp(
      const FlutterVibeUme(
        appName: _kAppName,
        resolveSourceAnchor: lookupSourceAnchor,
        defaultServerUrl: _kDefaultServerUrl,
        child: FlutterVibeApp(),
      ),
    );
    return;
  }

  // Profile / release: UME is unavailable. Mount the FeedbackTicketLauncher
  // through MaterialApp.builder so it lives inside Theme/Material/Navigator
  // scope and can render its floating button + bottom sheet correctly.
  runApp(
    FlutterVibeApp(
      builder: (context, child) {
        return DraggableFeedbackTicketLauncher(
          appName: _kAppName,
          defaultServerUrl: _kDefaultServerUrl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

class DraggableFeedbackTicketLauncher extends StatefulWidget {
  const DraggableFeedbackTicketLauncher({
    super.key,
    required this.appName,
    required this.defaultServerUrl,
    required this.child,
  });

  final String appName;
  final String defaultServerUrl;
  final Widget child;

  @override
  State<DraggableFeedbackTicketLauncher> createState() =>
      _DraggableFeedbackTicketLauncherState();
}

class _DraggableFeedbackTicketLauncherState
    extends State<DraggableFeedbackTicketLauncher> {
  static const Size _buttonHitSize = Size(184, 48);
  static const double _edgePadding = 16;
  static const double _bottomPadding = 96;

  Offset? _offset;
  bool _dragging = false;

  Rect _launcherRect(Size size) {
    final offset = _offset ??
        Offset(
          size.width - _buttonHitSize.width - _edgePadding,
          size.height - _buttonHitSize.height - _bottomPadding,
        );
    return _clampOffset(offset, size) & _buttonHitSize;
  }

  Offset _clampOffset(Offset offset, Size size) {
    final maxX = (size.width - _buttonHitSize.width - _edgePadding)
        .clamp(_edgePadding, double.infinity);
    final maxY = (size.height - _buttonHitSize.height - _edgePadding)
        .clamp(_edgePadding, double.infinity);

    return Offset(
      offset.dx.clamp(_edgePadding, maxX).toDouble(),
      offset.dy.clamp(_edgePadding, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final launcherOffset = _offset ?? _launcherRect(size).topLeft;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _dragging = _launcherRect(size).contains(event.localPosition);
          },
          onPointerMove: (event) {
            if (!_dragging) return;
            setState(() {
              _offset =
                  _clampOffset((_offset ?? launcherOffset) + event.delta, size);
            });
          },
          onPointerUp: (_) => _dragging = false,
          onPointerCancel: (_) => _dragging = false,
          child: FeedbackTicketLauncher(
            appName: widget.appName,
            defaultServerUrl: widget.defaultServerUrl,
            alignment: Alignment.topLeft,
            padding: EdgeInsets.only(
              left: launcherOffset.dx,
              top: launcherOffset.dy,
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}
