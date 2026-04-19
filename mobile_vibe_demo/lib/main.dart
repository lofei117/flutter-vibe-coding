import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ume_core/ume_core.dart';

import 'app.dart';
import 'ume_plugins/ai_vibe_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    PluginManager.instance.register(AiVibePanel());
    runApp(const UMEWidget(enable: true, child: MobileVibeApp()));
    return;
  }

  runApp(const MobileVibeApp());
}
