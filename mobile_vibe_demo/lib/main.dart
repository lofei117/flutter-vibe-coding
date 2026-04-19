import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ume_core/ume_core.dart';
import 'package:ume_kit_ui/ume_kit_ui.dart';
import 'package:ume_kit_show_code/ume_kit_show_code.dart';

import 'app.dart';
import 'ume_plugins/ai_vibe_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    PluginManager.instance
      ..register(AiVibePanel())
      ..register(const WidgetInfoInspector())
      ..register(const WidgetDetailInspector())
      ..register(const ShowCode());
    runApp(const UMEWidget(enable: true, child: MobileVibeApp()));
    return;
  }

  runApp(const MobileVibeApp());
}
