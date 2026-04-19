import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ume_core/ume_core.dart';
import 'package:ume_kit_ui/components/hit_test.dart';

import 'api_client.dart';
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

const String _umePluginVersion = '0.2.0';

class AiVibePanel implements Pluggable {
  @override
  Widget? buildWidget(BuildContext? context) => const AiVibeFloatingPanel();

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
  const AiVibeFloatingPanel({super.key});

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
  const AiVibePanelPage({super.key, this.onPickTarget});

  final VoidCallback? onPickTarget;

  @override
  State<AiVibePanelPage> createState() => AiVibePanelPageState();
}

class AiVibePanelPageState extends State<AiVibePanelPage>
    with SingleTickerProviderStateMixin {
  final _configStore = ServerConfigStore();
  final _apiClient = AiVibeApiClient();
  final _serverController = TextEditingController();
  final _instructionController = TextEditingController(
    text: '把按钮改成绿色，并把文案改成 Start',
  );

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

  SessionState? _session;
  bool _sessionFromCache = false;

  @override
  void initState() {
    super.initState();
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
    _serverController.text = ServerConfigStore.defaultServerUrl;
    await _saveServerUrl();
  }

  void _captureSelection({String source = 'tap-select'}) {
    final outcome = SelectionCapture.captureCurrent(source: source);
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
      appName: 'mobile_vibe_demo',
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Server URL',
              hintText: ServerConfigStore.defaultServerUrl,
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(_statusDetail),
          ),
        ],
      ),
    );
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

  /// Coalesce consecutive events with the same "stream" stage (currently only
  /// `agent_log`, which Codex emits as one event per token / line) into a
  /// single group so the Events tab stays readable.
  List<_EventGroup> _buildEventGroups(List<CommandEvent> events) {
    final groups = <_EventGroup>[];
    for (final event in events) {
      final isStream = _isStreamStage(event.stage);
      if (isStream && groups.isNotEmpty) {
        final last = groups.last;
        if (last.stage == event.stage) {
          last.events.add(event);
          continue;
        }
      }
      groups.add(_EventGroup(stage: event.stage, events: [event]));
    }
    return groups;
  }

  bool _isStreamStage(String stage) => stage == 'agent_log';

  Widget _buildEventGroupCard(_EventGroup group) {
    if (group.events.length == 1) {
      return _buildEventRow(group.events.single);
    }
    return _buildCoalescedAgentLog(group);
  }

  Widget _buildCoalescedAgentLog(_EventGroup group) {
    final color = _stageColor(group.stage);
    final first = group.events.first;
    final last = group.events.last;
    final firstTs = first.timestamp.split('T').last.split('.').first;
    final lastTs = last.timestamp.split('T').last.split('.').first;
    final timeRange = firstTs == lastTs ? lastTs : '$firstTs → $lastTs';
    final body = group.events
        .map((e) => e.message)
        .where((m) => m.isNotEmpty)
        .join('\n');

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
                  group.stage,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '#${first.sequence}–#${last.sequence} · ${group.events.length} lines',
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45),
              ),
              const Spacer(),
              Text(
                timeRange,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(
                  body.isEmpty ? '(empty stream)' : body,
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
      ),
    );
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

  Widget _buildEventRow(CommandEvent event) {
    final color = _stageColor(event.stage);
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
                event.timestamp.split('T').last.split('.').first,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(event.message,
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(turn.userInstruction,
              style: const TextStyle(fontWeight: FontWeight.w600)),
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
        ],
      ),
    );
  }
}

class _EventGroup {
  _EventGroup({required this.stage, required this.events});

  final String stage;
  final List<CommandEvent> events;
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
