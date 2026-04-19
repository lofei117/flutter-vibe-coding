import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ume_core/ume_core.dart';
import 'package:ume_kit_ui/components/hit_test.dart';

import 'api_client.dart';
import 'context/agent_log_payload.dart';
import 'context/approval.dart';
import 'context/client_meta.dart';
import 'context/command_event.dart';
import 'context/command_response.dart';
import 'context/runtime_context.dart';
import 'context/selected_component_context.dart';
import 'context/selection_capture.dart';
import 'context/session_state.dart';
import 'context/widget_runtime_descriptor.dart';
import 'server_config_store.dart';
import 'source_anchor.dart';

const String _umePluginVersion = '0.2.0';

class AiVibePanel implements Pluggable {
  const AiVibePanel({
    required this.appName,
    required this.resolveSourceAnchor,
    this.defaultInstruction =
        'Make the button green and change the label to Start.',
    this.defaultServerUrl = 'http://127.0.0.1:8787',
  });

  final String appName;
  final SourceAnchorResolver resolveSourceAnchor;
  final String defaultInstruction;
  final String defaultServerUrl;

  @override
  Widget? buildWidget(BuildContext? context) => AiVibeFloatingPanel(
        appName: appName,
        resolveSourceAnchor: resolveSourceAnchor,
        defaultInstruction: defaultInstruction,
        defaultServerUrl: defaultServerUrl,
      );

  @override
  String get displayName => 'AI Vibe Panel';

  @override
  ImageProvider<Object> get iconImageProvider =>
      MemoryImage(Uint8List.fromList(_iconPng));

  @override
  String get name => 'ai_vibe_panel';

  @override
  void onTrigger() {}
}

class AiVibeFloatingPanel extends StatefulWidget {
  const AiVibeFloatingPanel({
    super.key,
    required this.appName,
    required this.resolveSourceAnchor,
    required this.defaultInstruction,
    required this.defaultServerUrl,
  });

  final String appName;
  final SourceAnchorResolver resolveSourceAnchor;
  final String defaultInstruction;
  final String defaultServerUrl;

  @override
  State<AiVibeFloatingPanel> createState() => _AiVibeFloatingPanelState();
}

class _AiVibeFloatingPanelState extends State<AiVibeFloatingPanel> {
  final GlobalKey<AiVibePanelPageState> _panelKey =
      GlobalKey<AiVibePanelPageState>();
  bool _picking = false;

  void _startPicking() {
    setState(() => _picking = true);
  }

  void _cancelPicking() {
    setState(() => _picking = false);
    _panelKey.currentState?.reportPickCancelled();
  }

  void _handlePick(Offset position) {
    try {
      final hits = HitTest.hitTest(position, edgeHitMargin: 2.0);
      if (hits.isEmpty) {
        setState(() => _picking = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _panelKey.currentState
              ?.reportPickFailure('No widget was hit at that location.');
        });
        return;
      }
      WidgetInspectorService.instance.selection.candidates = hits;
      setState(() => _picking = false);
      // The panel was kept alive via Offstage, so currentState is valid.
      _panelKey.currentState?.applyPickerSelection();
    } catch (error) {
      setState(() => _picking = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _panelKey.currentState
            ?.reportPickFailure('Hit-test failed: $error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelWidth = size.width < 560 ? size.width - 24 : 460.0;
    final panelHeight = size.height < 780 ? size.height - 112 : 680.0;

    return Stack(
      children: [
        Positioned(
          right: 12,
          top: 72,
          width: panelWidth,
          height: panelHeight,
          child: Offstage(
            offstage: _picking,
            child: Material(
              color: Colors.white,
              elevation: 12,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: AiVibePanelPage(
                key: _panelKey,
                onPickTarget: _startPicking,
                appName: widget.appName,
                resolveSourceAnchor: widget.resolveSourceAnchor,
                defaultInstruction: widget.defaultInstruction,
                defaultServerUrl: widget.defaultServerUrl,
              ),
            ),
          ),
        ),
        if (_picking)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _handlePick(details.globalPosition),
              child: Container(color: const Color(0x332563EB)),
            ),
          ),
        if (_picking)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _PickingHintBar(onCancel: _cancelPicking),
          ),
      ],
    );
  }
}

class _PickingHintBar extends StatelessWidget {
  const _PickingHintBar({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.ads_click, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Tap any widget on the screen to select it as the AI edit target.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class AiVibePanelPage extends StatefulWidget {
  const AiVibePanelPage({
    super.key,
    this.onPickTarget,
    required this.appName,
    required this.resolveSourceAnchor,
    required this.defaultInstruction,
    required this.defaultServerUrl,
  });

  final VoidCallback? onPickTarget;
  final String appName;
  final SourceAnchorResolver resolveSourceAnchor;
  final String defaultInstruction;
  final String defaultServerUrl;

  @override
  State<AiVibePanelPage> createState() => AiVibePanelPageState();
}

class AiVibePanelPageState extends State<AiVibePanelPage>
    with SingleTickerProviderStateMixin {
  late final ServerConfigStore _configStore;
  final _apiClient = AiVibeApiClient();
  final _serverController = TextEditingController();
  late final TextEditingController _instructionController;

  late final TabController _tabController;

  String _status = 'idle';
  String _statusDetail = 'No response yet.';
  String _sessionStatus = 'not loaded';
  String? _sessionId;
  String? _appSessionId;
  String _appLaunchMode = 'manual';

  SelectedComponentContext? _selection;
  RuntimeContext? _runtimeContext;
  String? _selectionError;

  String? _currentCommandId;
  final List<CommandEvent> _events = [];
  CommandResponse? _lastResponse;
  StreamSubscription<CommandEvent>? _eventSub;

  ApprovalRequest? _pendingApproval;
  bool _submittingDecision = false;
  final _reviseController = TextEditingController();

  /// True while a manual `Hot Reload` / `Hot Restart` request is in flight,
  /// to disable both buttons and show their loading state.
  bool _appActionPending = false;

  /// Per-group expand state for `agent_log` and other long-message cards.
  /// Key = `_EventGroup.id`. A non-existent entry means "use default rule"
  /// (collapse if content exceeds threshold, otherwise show inline).
  final Map<String, bool> _groupExpanded = <String, bool>{};

  SessionState? _session;
  bool _sessionFromCache = false;

  @override
  void initState() {
    super.initState();
    _configStore = ServerConfigStore(defaultServerUrl: widget.defaultServerUrl);
    _instructionController = TextEditingController(
      text: widget.defaultInstruction,
    );
    _tabController = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _serverController.dispose();
    _instructionController.dispose();
    _reviseController.dispose();
    _tabController.dispose();
    _apiClient.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final serverUrl = await _configStore.loadServerUrl();
    final cachedSessionId = await _configStore.loadSessionId();
    final cachedAppSessionId = await _configStore.loadAppSessionId();
    if (!mounted) return;
    setState(() {
      _serverController.text = serverUrl;
      _sessionId = cachedSessionId;
      _appSessionId = cachedAppSessionId;
      _appLaunchMode = cachedAppSessionId != null ? 'server-managed' : 'manual';
    });
    await _refreshSessionFromServer();
    await _refreshAppSession();
  }

  Future<void> _refreshSessionFromServer() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) return;
    try {
      final session = await _apiClient.fetchCurrentSession(url);
      if (session == null) {
        await _restoreFromCache(reason: 'server returned empty session');
        return;
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionId = session.sessionId;
        _sessionStatus = 'online (${session.turns.length} turns)';
        _sessionFromCache = false;
      });
      await _configStore.saveSessionId(session.sessionId);
      await _configStore.saveCachedSessionJson(
        jsonEncode(session.toJson()),
      );
    } catch (error) {
      await _restoreFromCache(reason: 'server disconnected: $error');
    }
  }

  Future<void> _restoreFromCache({required String reason}) async {
    final cached = await _configStore.loadCachedSessionJson();
    if (cached == null) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionStatus = reason;
        _sessionFromCache = false;
      });
      return;
    }
    try {
      final map = jsonDecode(cached) as Map<String, dynamic>;
      final session = SessionState.fromJson(map);
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionId = session.sessionId;
        _sessionStatus = '$reason (showing cached history)';
        _sessionFromCache = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionStatus = '$reason (cache unreadable)';
        _sessionFromCache = false;
      });
    }
  }

  Future<void> _refreshAppSession() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) return;
    try {
      final appSessionId = await _apiClient.fetchAppSessionId(url);
      if (!mounted) return;
      setState(() {
        _appSessionId = appSessionId;
        _appLaunchMode = appSessionId != null ? 'server-managed' : 'manual';
      });
      await _configStore.saveAppSessionId(appSessionId);
    } catch (_) {
      // ignore; handled by session status.
    }
  }

  Future<void> _saveServerUrl() async {
    await _configStore.saveServerUrl(_serverController.text);
    await _refreshSessionFromServer();
    await _refreshAppSession();
    if (!mounted) return;
    setState(() {
      _status = 'idle';
      _statusDetail = 'Saved server URL: ${_serverController.text.trim()}';
    });
  }

  Future<void> _useDefaultServerUrl() async {
    _serverController.text = widget.defaultServerUrl;
    await _saveServerUrl();
  }

  void _captureSelection({String source = 'tap-select'}) {
    final outcome = SelectionCapture.captureCurrent(
      source: source,
      resolveSourceAnchor: widget.resolveSourceAnchor,
    );
    setState(() {
      _selection = outcome.selection;
      _runtimeContext = outcome.runtimeContext;
      _selectionError = outcome.hasSelection ? null : outcome.reason;
    });
  }

  /// Called by [_AiVibeFloatingPanelState] after the user taps a widget in
  /// picking mode. At this point [WidgetInspectorService.instance.selection]
  /// has been updated with the new candidates.
  void applyPickerSelection() {
    _captureSelection(source: 'tap-picker');
  }

  void reportPickFailure(String message) {
    setState(() {
      _selectionError = message;
    });
  }

  void reportPickCancelled() {
    setState(() {
      _selectionError = 'Picking cancelled.';
    });
  }

  void _clearSelection() {
    setState(() {
      _selection = null;
      _runtimeContext = null;
      _selectionError = null;
    });
  }

  ClientMeta _buildClientMeta() {
    String? runtimeTarget;
    if (kIsWeb) {
      runtimeTarget = 'web';
    } else {
      try {
        if (Platform.isAndroid) {
          runtimeTarget = 'android';
        } else if (Platform.isIOS) {
          runtimeTarget = 'ios';
        } else if (Platform.isMacOS) {
          runtimeTarget = 'macos';
        } else {
          runtimeTarget = 'unknown';
        }
      } catch (_) {
        runtimeTarget = 'unknown';
      }
    }
    return ClientMeta(
      appName: widget.appName,
      runtimeTarget: runtimeTarget,
      debugMode: kDebugMode,
      umePluginVersion: _umePluginVersion,
      serverUrl: _serverController.text.trim(),
      appLaunchMode: _appLaunchMode,
    );
  }

  Future<void> _sendInstruction() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) {
      setState(() {
        _status = 'error';
        _statusDetail = 'Instruction is empty.';
      });
      return;
    }

    setState(() {
      _status = 'sending';
      _statusDetail = 'Queuing command...';
      _events.clear();
      _lastResponse = null;
      _currentCommandId = null;
      _pendingApproval = null;
      _groupExpanded.clear();
    });
    await _eventSub?.cancel();
    _eventSub = null;

    await _configStore.saveServerUrl(_serverController.text);
    final serverUrl = _serverController.text.trim();

    try {
      final enq = await _apiClient.enqueueCommand(
        serverUrl: serverUrl,
        instruction: instruction,
        clientMeta: _buildClientMeta(),
        selection: _selection,
        runtimeContext: _runtimeContext,
        sessionId: _sessionId,
        appSessionId: _appSessionId,
      );

      if (!mounted) return;
      setState(() {
        _currentCommandId = enq.commandId;
        _status = 'running';
        _statusDetail = 'commandId=${enq.commandId}';
      });
      _tabController.animateTo(1);

      _startEventStream(serverUrl: serverUrl, commandId: enq.commandId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _statusDetail = 'Failed to enqueue: $error';
      });
    }
  }

  void _startEventStream({
    required String serverUrl,
    required String commandId,
  }) {
    _eventSub = _apiClient
        .streamCommandEvents(serverUrl: serverUrl, commandId: commandId)
        .listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _events.add(event);
          _statusDetail = '[${event.stage}] ${event.message}';
          if (event.stage == 'approval_required') {
            final req = _extractApprovalRequest(event.payload);
            if (req != null) {
              _pendingApproval = req;
              _status = 'awaiting_approval';
              _statusDetail = 'Approval required: ${req.title}';
            }
          } else if (event.stage == 'approval_resolved' ||
              event.stage == 'completed' ||
              event.stage == 'failed' ||
              event.stage == 'safety_blocked') {
            _pendingApproval = null;
            if (event.stage != 'approval_resolved') {
              // Leave running; terminal handling happens in onDone.
            } else if (_status == 'awaiting_approval') {
              _status = 'running';
            }
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _status = 'error';
          _statusDetail = 'Stream failed: $error';
        });
      },
      onDone: () async {
        try {
          final status = await _apiClient.fetchCommandStatus(
            serverUrl: serverUrl,
            commandId: commandId,
          );
          if (!mounted) return;
          setState(() {
            _lastResponse = status.finalResponse;
            final fr = status.finalResponse;
            if (fr?.requiresApproval == true && fr?.approvalRequest != null) {
              _pendingApproval = fr!.approvalRequest;
              _status = 'awaiting_approval';
              _statusDetail =
                  'Approval required: ${fr.approvalRequest!.title}';
            } else {
              _pendingApproval = null;
              _status = fr == null
                  ? 'unknown'
                  : (fr.success ? 'success' : 'error');
              _statusDetail = fr?.message ?? 'No final response.';
            }
          });
          await _refreshSessionFromServer();
          if (_pendingApproval == null) {
            _tabController.animateTo(2);
          }
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _status = 'error';
            _statusDetail = 'Failed to fetch final response: $error';
          });
        }
      },
    );
  }

  ApprovalRequest? _extractApprovalRequest(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final ar = payload['approvalRequest'];
    if (ar is Map<String, dynamic>) {
      return ApprovalRequest.fromJson(ar);
    }
    if (payload['approvalId'] is String) {
      return ApprovalRequest.fromJson(payload);
    }
    return null;
  }

  Future<void> _submitApproval(String decision, {String? comment}) async {
    final pending = _pendingApproval;
    final commandId = _currentCommandId;
    if (pending == null) return;
    setState(() {
      _submittingDecision = true;
      _statusDetail = 'Submitting decision: $decision...';
    });
    final serverUrl = _serverController.text.trim();
    try {
      await _apiClient.submitApprovalDecision(
        serverUrl: serverUrl,
        clientMeta: _buildClientMeta(),
        decision: ApprovalDecision(
          approvalId: pending.approvalId,
          decision: decision,
          comment: comment,
        ),
        sessionId: _sessionId,
        appSessionId: _appSessionId,
      );
      if (!mounted) return;
      setState(() {
        _pendingApproval = null;
        _status = 'running';
        _statusDetail = 'Decision submitted ($decision). Resuming...';
        _reviseController.clear();
      });
      // The server may continue emitting events on the same commandId. If the
      // previous poll stream already closed, start a new one.
      if (_eventSub == null && commandId != null && commandId.isNotEmpty) {
        _startEventStream(serverUrl: serverUrl, commandId: commandId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusDetail = 'Decision submit failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _submittingDecision = false);
      }
    }
  }

  Future<void> _triggerHotReload() async {
    final appSessionId = _appSessionId;
    if (appSessionId == null) return;
    setState(() {
      _appActionPending = true;
      _statusDetail = 'Hot reload requested…';
    });
    try {
      final message = await _apiClient.triggerHotReload(
        serverUrl: _serverController.text.trim(),
        appSessionId: appSessionId,
      );
      if (!mounted) return;
      setState(() => _statusDetail = message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _statusDetail = 'Hot reload failed: $error';
      });
    } finally {
      if (mounted) setState(() => _appActionPending = false);
    }
  }

  Future<void> _triggerHotRestart() async {
    final appSessionId = _appSessionId;
    if (appSessionId == null) return;
    final confirmed = await _showOverlayConfirm(
      title: 'Hot restart the running app?',
      buildBody: () => const Text(
        'A hot restart resets app state and rebuilds the widget tree from '
        'scratch. Anything you have selected, typed, or navigated will be '
        'lost. The current AI command, if any, is not cancelled.',
        style: TextStyle(fontSize: 13),
      ),
      confirmLabel: 'Hot Restart',
      confirmIcon: Icons.restart_alt,
      confirmColor: const Color(0xFFD97706),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _appActionPending = true;
      _statusDetail = 'Hot restart requested…';
    });
    try {
      final message = await _apiClient.triggerHotRestart(
        serverUrl: _serverController.text.trim(),
        appSessionId: appSessionId,
      );
      if (!mounted) return;
      setState(() => _statusDetail = message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _statusDetail = 'Hot restart failed: $error';
      });
    } finally {
      if (mounted) setState(() => _appActionPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildComposeTab(),
                _buildEventsTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'AI Vibe Panel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'status: $_status',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const IconButton(
            tooltip: 'Close',
            onPressed: UMEWidget.closeActivatedPlugin,
            icon: Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF111827),
        unselectedLabelColor: Colors.black54,
        indicatorColor: const Color(0xFF111827),
        tabs: const [
          Tab(text: 'Compose'),
          Tab(text: 'Events'),
          Tab(text: 'History'),
        ],
      ),
    );
  }

  Widget _buildComposeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          TextField(
            controller: _serverController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Server URL',
              hintText: widget.defaultServerUrl,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saveServerUrl,
                  child: const Text('Save & Reconnect'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _useDefaultServerUrl,
                  child: const Text('Use Mac Default'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoStrip(),
          const SizedBox(height: 8),
          _buildAppControlRow(),
          if (_pendingApproval != null) ...[
            const SizedBox(height: 12),
            _buildApprovalBanner(_pendingApproval!),
          ],
          const SizedBox(height: 16),
          const Text(
            'Selected Target',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _buildSelectionSummary(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.onPickTarget,
              icon: const Icon(Icons.ads_click, size: 18),
              label: const Text('Pick Target'),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => _captureSelection(source: 'ume-inspector'),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Sync UME'),
              ),
              OutlinedButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tip: "Pick Target" dims the app, then tap the widget you want to edit. '
            'Or use UME WidgetInfo/WidgetDetail first and press "Sync UME".',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _instructionController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Instruction',
              hintText: 'Describe the change you want.',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _status == 'sending' ||
                    _status == 'running' ||
                    _status == 'awaiting_approval'
                ? null
                : _sendInstruction,
            child: Text(
              _status == 'awaiting_approval'
                  ? 'Awaiting approval…'
                  : (_status == 'running' ? 'Running…' : 'Send'),
            ),
          ),
          const SizedBox(height: 10),
          _buildStatusCard(),
        ],
      ),
    );
  }

  Widget _buildAppControlRow() {
    final disabled = _appSessionId == null;
    final tooltip = disabled
        ? 'Server is not managing this app (manual launch). '
            'Start the app via /app/start to enable hot reload from the panel.'
        : null;
    Widget reload = OutlinedButton.icon(
      onPressed: disabled || _appActionPending ? null : _triggerHotReload,
      icon: _appActionPending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.bolt, size: 16),
      label: const Text('Hot Reload'),
    );
    Widget restart = OutlinedButton.icon(
      onPressed: disabled || _appActionPending ? null : _triggerHotRestart,
      icon: const Icon(Icons.restart_alt, size: 16),
      label: const Text('Hot Restart'),
    );
    if (tooltip != null) {
      reload = Tooltip(message: tooltip, child: reload);
      restart = Tooltip(message: tooltip, child: restart);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        reload,
        restart,
        if (disabled)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'manual launch — reload disabled',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final color = _statusColor(_status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Center(child: _statusLeadingWidget(_status, color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(_status),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  _statusDetail,
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sending':
      case 'running':
        return const Color(0xFF2563EB);
      case 'awaiting_approval':
        return const Color(0xFFD97706);
      case 'success':
        return const Color(0xFF16A34A);
      case 'error':
        return const Color(0xFFDC2626);
      case 'idle':
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'sending':
        return 'SENDING';
      case 'running':
        return 'RUNNING';
      case 'awaiting_approval':
        return 'AWAITING APPROVAL';
      case 'success':
        return 'SUCCESS';
      case 'error':
        return 'ERROR';
      case 'idle':
        return 'IDLE';
      default:
        return status.toUpperCase();
    }
  }

  Widget _statusLeadingWidget(String status, Color color) {
    switch (status) {
      case 'sending':
      case 'running':
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );
      case 'awaiting_approval':
        return Icon(Icons.pause_circle, size: 20, color: color);
      case 'success':
        return Icon(Icons.check_circle, size: 20, color: color);
      case 'error':
        return Icon(Icons.error, size: 20, color: color);
      case 'idle':
      default:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        );
    }
  }

  Widget _buildInfoStrip() {
    final items = <Widget>[
      _infoChip(
        Icons.link,
        'session: ${_sessionId ?? '-'}',
        _sessionFromCache ? Colors.orange.shade100 : null,
      ),
      _infoChip(
        Icons.settings_remote,
        'appSession: ${_appSessionId ?? 'manual'}',
      ),
      _infoChip(
        Icons.cloud,
        _sessionStatus,
        _sessionFromCache
            ? Colors.orange.shade100
            : (_session != null ? Colors.green.shade50 : null),
      ),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items,
    );
  }

  Widget _infoChip(IconData icon, String label, [Color? background]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSelectionSummary() {
    if (_selection == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          border: Border.all(color: Colors.orange.shade200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _selectionError ??
              'No target selected. Server will fall back to default files.',
          style: const TextStyle(fontSize: 13),
        ),
      );
    }
    final sel = _selection!;
    final srcLoc = sel.sourceLocation;
    final locLine = srcLoc is SourceLocationAvailable
        ? '${srcLoc.file}:${srcLoc.line}'
        : (srcLoc is SourceLocationUnavailable
            ? 'source unavailable: ${srcLoc.reason}'
            : 'unknown');
    final candidates = sel.codeContext?.candidateFiles ?? const [];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sel.summarize(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('location: $locLine',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (candidates.isNotEmpty)
            Text('candidates: ${candidates.join(', ')}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('confidence: ${sel.confidence}  source: ${sel.source}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildEventsTab() {
    if (_currentCommandId == null && _events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No command in flight. Send an instruction to see process events.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final groups = _buildEventGroups(_events);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentCommandId != null)
            Text('commandId: $_currentCommandId',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (_pendingApproval != null) ...[
            const SizedBox(height: 8),
            _buildApprovalBanner(_pendingApproval!),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final group = groups[groups.length - 1 - index];
                return _buildEventGroupCard(group);
              },
            ),
          ),
          if (_lastResponse != null) ...[
            const Divider(height: 16),
            _buildFinalResponseBlock(_lastResponse!),
          ],
        ],
      ),
    );
  }

  /// Build display groups from raw [events]. Spec rules
  /// (`.spec/context-contract.spec.md` §过程事件颗粒度契约):
  ///
  /// - 阶段变化必须使用独立 stage：每个非 `agent_log` 事件就是一个独立 group。
  /// - 连续 `agent_log` 可以聚合，但必须可展开。
  /// - 高信号 `agent_log`（level=error 或 category in {safety, approval,
  ///   repair, fallback}）必须始终可见，即使父 group 处于折叠态也不能藏起来。
  List<_EventGroup> _buildEventGroups(List<CommandEvent> events) {
    final groups = <_EventGroup>[];
    for (final event in events) {
      if (event.stage == 'agent_log' && groups.isNotEmpty) {
        final last = groups.last;
        if (last.kind == _EventGroupKind.stream &&
            last.stage == 'agent_log') {
          last.events.add(event);
          continue;
        }
      }
      final kind = event.stage == 'agent_log'
          ? _EventGroupKind.stream
          : _EventGroupKind.phase;
      groups.add(_EventGroup(
        id: '${event.stage}_${event.sequence}',
        stage: event.stage,
        kind: kind,
        events: [event],
      ));
    }
    return groups;
  }

  Widget _buildEventGroupCard(_EventGroup group) {
    if (group.kind == _EventGroupKind.stream) {
      return _buildStreamGroupCard(group);
    }
    return _buildPhaseEventCard(group.events.single, groupId: group.id);
  }

  /// Card for a coalesced run of `agent_log` events.
  Widget _buildStreamGroupCard(_EventGroup group) {
    final color = _stageColor(group.stage);
    final entries = group.events
        .map((e) => _LogEntry(event: e, payload: AgentLogPayload.maybe(e.payload)))
        .toList();
    final highSignal = entries.where((e) => e.payload?.isHighSignal == true).toList();
    final ordinary = entries.where((e) => e.payload?.isHighSignal != true).toList();

    final ordinaryBody = ordinary
        .map((e) => e.event.message)
        .where((m) => m.isNotEmpty)
        .join('\n');
    final ordinaryLines = ordinaryBody.isEmpty
        ? const <String>[]
        : ordinaryBody.split('\n');

    const collapsedLineCount = 6;
    final exceedsThreshold = ordinaryLines.length > collapsedLineCount ||
        ordinaryBody.length > 480;
    final expanded = _groupExpanded[group.id] ?? false;

    final visibleBody = !exceedsThreshold || expanded
        ? ordinaryBody
        : ordinaryLines.take(collapsedLineCount).join('\n');
    final hiddenLines = exceedsThreshold && !expanded
        ? ordinaryLines.length - collapsedLineCount
        : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStreamGroupHeader(group, entries, color),
          if (highSignal.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...highSignal.map(_buildHighSignalLine),
          ],
          if (visibleBody.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SelectableText(
                    visibleBody,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (exceedsThreshold)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() {
                  _groupExpanded[group.id] = !expanded;
                }),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(
                  expanded
                      ? 'Collapse'
                      : 'Show all ($hiddenLines more lines)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStreamGroupHeader(
    _EventGroup group,
    List<_LogEntry> entries,
    Color color,
  ) {
    final first = group.events.first;
    final last = group.events.last;
    final firstTs = _shortTime(first.timestamp);
    final lastTs = _shortTime(last.timestamp);
    final timeRange = firstTs == lastTs ? lastTs : '$firstTs → $lastTs';

    final streamCounts = <String, int>{};
    final levelCounts = <String, int>{};
    final categories = <String>{};
    for (final entry in entries) {
      final p = entry.payload;
      if (p?.stream != null) {
        streamCounts[p!.stream!] = (streamCounts[p.stream!] ?? 0) + 1;
      }
      if (p?.level != null && p!.level != 'info') {
        levelCounts[p.level!] = (levelCounts[p.level!] ?? 0) + 1;
      }
      if (p?.category != null) categories.add(p!.category!);
    }

    final pills = <Widget>[];
    streamCounts.forEach((stream, count) {
      pills.add(_summaryPill(
        '$stream × $count',
        background: const Color(0xFFE0E7FF),
        foreground: const Color(0xFF312E81),
      ));
    });
    levelCounts.forEach((level, count) {
      pills.add(_summaryPill(
        '$level × $count',
        background: level == 'error'
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF3C7),
        foreground: level == 'error'
            ? const Color(0xFF991B1B)
            : const Color(0xFF92400E),
      ));
    });
    for (final c in categories) {
      pills.add(_summaryPill(
        c,
        background: const Color(0xFFE0F2FE),
        foreground: const Color(0xFF075985),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                group.stage,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '#${first.sequence}–#${last.sequence} · ${group.events.length} entries',
                style:
                    const TextStyle(fontSize: 11, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              timeRange,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: pills),
        ],
      ],
    );
  }

  Widget _summaryPill(
    String label, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildHighSignalLine(_LogEntry entry) {
    final payload = entry.payload!;
    final isError = payload.level == 'error';
    final color = isError
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (payload.level != null)
                _summaryPill(
                  payload.level!,
                  background: color,
                  foreground: Colors.white,
                ),
              if (payload.category != null)
                _summaryPill(
                  payload.category!,
                  background: color.withValues(alpha: 0.18),
                  foreground: color,
                ),
              Text('#${entry.event.sequence}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            entry.event.message,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a single non-stream phase event. Adds expand/collapse when the
  /// message itself is long (e.g. patch_applied with embedded diff).
  Widget _buildPhaseEventCard(CommandEvent event, {required String groupId}) {
    final color = _stageColor(event.stage);
    final lines = event.message.split('\n');
    const collapsedLineCount = 6;
    final exceedsThreshold =
        lines.length > collapsedLineCount || event.message.length > 480;
    final expanded = _groupExpanded[groupId] ?? false;
    final visibleMessage = !exceedsThreshold || expanded
        ? event.message
        : lines.take(collapsedLineCount).join('\n');
    final hiddenLines =
        exceedsThreshold && !expanded ? lines.length - collapsedLineCount : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  event.stage,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(width: 6),
              Text('#${event.sequence}',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black45)),
              const Spacer(),
              Text(
                _shortTime(event.timestamp),
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            visibleMessage.isEmpty ? '(no message)' : visibleMessage,
            style: const TextStyle(fontSize: 13),
          ),
          if (exceedsThreshold)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() {
                  _groupExpanded[groupId] = !expanded;
                }),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(
                  expanded
                      ? 'Collapse'
                      : 'Show all ($hiddenLines more lines)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _shortTime(String iso) {
    if (iso.isEmpty) return '';
    final tail = iso.split('T').last;
    final dot = tail.indexOf('.');
    return dot < 0 ? tail : tail.substring(0, dot);
  }

  Widget _buildApprovalBanner(ApprovalRequest req) {
    final actions = req.suggestedActions.isEmpty
        ? const ['continue', 'stop']
        : req.suggestedActions;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFF59E0B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pan_tool_alt,
                  size: 18, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  req.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE68A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(req.reason,
                    style: const TextStyle(fontSize: 11, color: Colors.black87)),
              ),
            ],
          ),
          if (req.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(req.summary,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
          if (req.changedFiles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('changedFiles: ${req.changedFiles.join(', ')}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (req.risks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('risks: ${req.risks.join('; ')}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: actions.map(_buildApprovalActionButton).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _reviseController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Revise (optional)',
                    hintText: 'Provide a revised instruction or guidance',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _submittingDecision
                    ? null
                    : () {
                        final text = _reviseController.text.trim();
                        if (text.isEmpty) {
                          setState(() {
                            _statusDetail =
                                'Revise requires a non-empty comment.';
                          });
                          return;
                        }
                        _submitApproval('revise', comment: text);
                      },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Revise'),
              ),
            ],
          ),
          if (_submittingDecision) ...[
            const SizedBox(height: 6),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalActionButton(String action) {
    final approved = const {'continue', 'rebuild', 'retry'}.contains(action);
    final rejected = const {'rollback', 'stop'}.contains(action);
    final decision = approved ? 'approved' : (rejected ? 'rejected' : 'approved');
    final label = _approvalActionLabel(action);
    final icon = _approvalActionIcon(action);
    if (rejected) {
      return OutlinedButton.icon(
        onPressed: _submittingDecision
            ? null
            : () => _submitApproval(decision, comment: action),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB91C1C),
          side: const BorderSide(color: Color(0xFFFCA5A5)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: _submittingDecision
          ? null
          : () => _submitApproval(decision, comment: action),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF059669),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  String _approvalActionLabel(String action) {
    switch (action) {
      case 'continue':
        return 'Continue';
      case 'rebuild':
        return 'Rebuild';
      case 'rollback':
        return 'Rollback';
      case 'retry':
        return 'Retry';
      case 'stop':
        return 'Stop';
      default:
        return action;
    }
  }

  IconData _approvalActionIcon(String action) {
    switch (action) {
      case 'continue':
        return Icons.play_arrow;
      case 'rebuild':
        return Icons.refresh;
      case 'rollback':
        return Icons.undo;
      case 'retry':
        return Icons.replay;
      case 'stop':
        return Icons.stop;
      default:
        return Icons.check;
    }
  }

  Color _stageColor(String stage) {
    switch (stage) {
      case 'queued':
        return const Color(0xFF6B7280);
      case 'safety_checked':
        return const Color(0xFF2563EB);
      case 'safety_blocked':
      case 'failed':
        return const Color(0xFFDC2626);
      case 'context_collected':
        return const Color(0xFF0891B2);
      case 'agent_started':
      case 'agent_log':
        return const Color(0xFF7C3AED);
      case 'patch_applied':
      case 'patch_generated':
        return const Color(0xFF059669);
      case 'reload_started':
      case 'reload_completed':
        return const Color(0xFF0EA5E9);
      case 'reload_failed':
        return const Color(0xFFB91C1C);
      case 'self_repair_started':
        return const Color(0xFFF97316);
      case 'self_repair_completed':
        return const Color(0xFF16A34A);
      case 'completed':
        return const Color(0xFF16A34A);
      case 'approval_required':
        return const Color(0xFFD97706);
      case 'approval_resolved':
        return const Color(0xFFCA8A04);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Widget _buildFinalResponseBlock(CommandResponse resp) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: resp.success
            ? const Color(0xFFF0FDF4)
            : const Color(0xFFFEF2F2),
        border: Border.all(
          color: resp.success ? Colors.green.shade200 : Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result: ${resp.message}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('applied=${resp.applied}  reload=${resp.reloadTriggered}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (resp.changedFiles.isNotEmpty)
            Text('changedFiles: ${resp.changedFiles.join(', ')}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          if (resp.reloadMessage != null)
            Text('reload: ${resp.reloadMessage}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          if (resp.safety != null && resp.safety!.reasons.isNotEmpty)
            Text('safety: ${resp.safety!.reasons.join('; ')}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          if (resp.diagnostics.isNotEmpty)
            ...resp.diagnostics.map(
              (d) => Text('• [${d.level}] ${d.message}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_sessionStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refreshSessionFromServer,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final turns = _session!.turns;
    if (turns.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No turns yet in the current session.'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'session: ${_session!.sessionId}'
                  '${_sessionFromCache ? '  (cache)' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
              IconButton(
                tooltip: 'Refresh from server',
                onPressed: _refreshSessionFromServer,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: turns.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final turn = turns[turns.length - 1 - index];
                return _buildTurnCard(turn);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnCard(SessionTurn turn) {
    final applied = turn.finalResponse?.applied ?? false;
    final reloaded = turn.finalResponse?.reloadTriggered ?? false;
    final changed = turn.finalResponse?.changedFiles ?? const [];
    final isFailed = _isTurnFailed(turn);
    final accentColor =
        isFailed ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isFailed
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF9FAFB),
        border: Border.all(
          color: isFailed
              ? accentColor.withValues(alpha: 0.4)
              : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(turn.userInstruction,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (isFailed) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'failed',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          if (turn.selectionSummary != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('target: ${turn.selectionSummary}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ),
          const SizedBox(height: 4),
          Text(
            'applied=$applied  reload=$reloaded  events=${turn.events.length}'
            '${changed.isEmpty ? '' : '  changed=${changed.join(', ')}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (turn.finalResponse != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(turn.finalResponse!.message,
                  style: const TextStyle(fontSize: 12)),
            ),
          if (isFailed)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor.withValues(alpha: 0.6)),
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed:
                      _status == 'sending' || _status == 'running'
                          ? null
                          : () => _confirmRetryTurn(turn),
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('Retry',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A turn is considered "failed" when its final response failed, or when
  /// terminal failure stages were observed even before a final response was
  /// recorded (e.g. server crash mid-stream, `safety_blocked`).
  bool _isTurnFailed(SessionTurn turn) {
    final fr = turn.finalResponse;
    if (fr != null) return !fr.success;
    for (final event in turn.events) {
      if (event.stage == 'failed' ||
          event.stage == 'safety_blocked' ||
          event.stage == 'reload_failed') {
        return true;
      }
    }
    return false;
  }

  Future<void> _confirmRetryTurn(SessionTurn turn) async {
    final preview = turn.userInstruction.length > 200
        ? '${turn.userInstruction.substring(0, 200)}…'
        : turn.userInstruction;

    final confirmed = await _showOverlayConfirm(
      title: 'Retry this command?',
      buildBody: () => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This will resend the original instruction as a new turn.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(preview,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 10),
          if (turn.selectionSummary != null)
            Text(
              'Original target: ${turn.selectionSummary}',
              style:
                  const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          const SizedBox(height: 4),
          Text(
            _selection == null
                ? 'Note: no current selection — the retry will run without a target. '
                    'Cancel and pick a new target if needed.'
                : 'Will reuse your current selection: '
                    '${_selection!.widget.widgetType}'
                    '${_selection!.widget.text != null ? ' "${_selection!.widget.text}"' : ''}.',
            style: TextStyle(
              fontSize: 12,
              color: _selection == null
                  ? const Color(0xFFB45309)
                  : Colors.black54,
            ),
          ),
        ],
      ),
      confirmLabel: 'Retry',
      confirmIcon: Icons.replay,
      confirmColor: const Color(0xFFDC2626),
    );

    if (confirmed != true || !mounted) return;
    _instructionController.text = turn.userInstruction;
    _tabController.animateTo(0);
    await _sendInstruction();
  }

  /// Shows a confirm dialog as an [OverlayEntry] in the **same** [Overlay]
  /// that hosts this panel. UME mounts its plugin widgets into a top-level
  /// `Overlay` that sits **above** the host app's `Navigator`, so a normal
  /// `showDialog(...)` would push a route into the host Navigator below the
  /// UME overlay and the dialog would be invisible / unclickable behind the
  /// floating panel.
  Future<bool?> _showOverlayConfirm({
    required String title,
    required Widget Function() buildBody,
    required String confirmLabel,
    required IconData confirmIcon,
    required Color confirmColor,
    String cancelLabel = 'Cancel',
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: false);
    if (overlay == null) {
      return Future.value(null);
    }

    final completer = Completer<bool?>();
    late OverlayEntry entry;

    void close(bool? result) {
      if (!completer.isCompleted) {
        entry.remove();
        completer.complete(result);
      }
    }

    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => close(false),
                child: const ColoredBox(color: Color(0x99000000)),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 440, maxHeight: 520),
                child: Material(
                  color: Colors.white,
                  elevation: 16,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(height: 12),
                        Flexible(
                          child: SingleChildScrollView(
                            child: buildBody(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => close(false),
                              child: Text(cancelLabel),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: confirmColor,
                              ),
                              onPressed: () => close(true),
                              icon: Icon(confirmIcon, size: 16),
                              label: Text(confirmLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
    return completer.future;
  }
}

enum _EventGroupKind { phase, stream }

class _EventGroup {
  _EventGroup({
    required this.id,
    required this.stage,
    required this.kind,
    required this.events,
  });

  final String id;
  final String stage;
  final _EventGroupKind kind;
  final List<CommandEvent> events;
}

class _LogEntry {
  const _LogEntry({required this.event, this.payload});

  final CommandEvent event;
  final AgentLogPayload? payload;
}

// A tiny 1x1 PNG keeps the plugin self-contained for the MVP.
const List<int> _iconPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
