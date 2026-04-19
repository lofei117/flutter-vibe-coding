import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_vibe_ume/flutter_vibe_ume.dart';

import 'app.dart';
import 'source_registry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    runApp(
      const FlutterVibeUme(
        appName: 'flutter_vibe_app',
        resolveSourceAnchor: lookupSourceAnchor,
        child: FlutterVibeApp(),
      ),
    );
    return;
  }

  runApp(const FlutterVibeApp());
}
