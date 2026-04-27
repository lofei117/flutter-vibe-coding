library flutter_vibe_ume;

import 'package:flutter/widgets.dart';
import 'package:ume_core/ume_core.dart';
import 'package:ume_kit_show_code/ume_kit_show_code.dart';
import 'package:ume_kit_ui/ume_kit_ui.dart';

import 'src/ai_vibe_panel.dart';
import 'src/source_anchor.dart';

export 'src/ai_vibe_panel.dart' show AiVibePanel;
export 'src/feedback_ticket_panel.dart'
    show FeedbackTicketLauncher, FeedbackTicketSheet, PageContextResolver;
export 'src/context/feedback_ticket.dart';
export 'src/context/client_meta.dart';
export 'src/source_anchor.dart';

class FlutterVibeUme extends StatelessWidget {
  static bool _pluginsRegistered = false;

  const FlutterVibeUme({
    super.key,
    required this.child,
    required this.appName,
    required this.resolveSourceAnchor,
    this.defaultInstruction =
        'Make the button green and change the label to Start.',
    this.defaultServerUrl = 'http://127.0.0.1:8787',
  });

  final Widget child;
  final String appName;
  final SourceAnchorResolver resolveSourceAnchor;
  final String defaultInstruction;
  final String defaultServerUrl;

  @override
  Widget build(BuildContext context) {
    if (!_pluginsRegistered) {
      PluginManager.instance
        ..register(
          AiVibePanel(
            appName: appName,
            resolveSourceAnchor: resolveSourceAnchor,
            defaultInstruction: defaultInstruction,
            defaultServerUrl: defaultServerUrl,
          ),
        )
        ..register(const WidgetInfoInspector())
        ..register(const WidgetDetailInspector())
        ..register(const ShowCode());
      _pluginsRegistered = true;
    }

    return UMEWidget(enable: true, child: child);
  }
}
