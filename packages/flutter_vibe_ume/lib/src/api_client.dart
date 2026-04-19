import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'context/approval.dart';
import 'context/client_meta.dart';
import 'context/command_event.dart';
import 'context/command_response.dart';
import 'context/runtime_context.dart';
import 'context/selected_component_context.dart';
import 'context/session_state.dart';

class EnqueueResult {
  const EnqueueResult({required this.commandId, required this.message});
  final String commandId;
  final String message;
}

class CommandStatus {
  const CommandStatus({
    required this.commandId,
    required this.stage,
    required this.message,
    required this.events,
    this.finalResponse,
  });

  final String commandId;
  final String stage;
  final String message;
  final List<CommandEvent> events;
  final CommandResponse? finalResponse;

  bool get isFinal => finalResponse != null;
}

class AiVibeApiClient {
  AiVibeApiClient({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  Uri _buildUri(String serverUrl, String path, {Map<String, String>? query}) {
    final baseUri = Uri.parse(serverUrl.trim());
    final cleanBase = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(
      path: '$cleanBase$path',
      queryParameters: query,
    );
  }

  /// POST /command. Does NOT wait for final response; returns the commandId
  /// so the caller can poll /command/:id/status.
  Future<EnqueueResult> enqueueCommand({
    required String serverUrl,
    required String instruction,
    required ClientMeta clientMeta,
    SelectedComponentContext? selection,
    RuntimeContext? runtimeContext,
    String? sessionId,
    String? appSessionId,
    ApprovalDecision? approvalDecision,
  }) async {
    final uri = _buildUri(serverUrl, '/command');
    final body = <String, dynamic>{
      'instruction': instruction,
      'clientMeta': clientMeta.toJson(),
      if (selection != null) 'selection': selection.toJson(),
      if (runtimeContext != null) 'runtimeContext': runtimeContext.toJson(),
      if (sessionId != null) 'sessionId': sessionId,
      if (appSessionId != null) 'appSessionId': appSessionId,
      if (approvalDecision != null)
        'approvalDecision': approvalDecision.toJson(),
    };

    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? response.body);
    }
    return EnqueueResult(
      commandId: (decoded['commandId'] as String?) ?? '',
      message: (decoded['message'] as String?) ?? '',
    );
  }

  /// Submit an [ApprovalDecision] through `POST /command`. Used when the
  /// server has emitted an `approval_required` event and the user picks one
  /// of the suggested actions from the AI Vibe Panel.
  ///
  /// MVP behaviour: we reuse `enqueueCommand` with an empty instruction plus
  /// the decision payload. The spec allows the server to continue or abort
  /// the original commandId based on the decision.
  Future<EnqueueResult> submitApprovalDecision({
    required String serverUrl,
    required ClientMeta clientMeta,
    required ApprovalDecision decision,
    String? sessionId,
    String? appSessionId,
    String instruction = '',
  }) {
    return enqueueCommand(
      serverUrl: serverUrl,
      instruction: instruction,
      clientMeta: clientMeta,
      sessionId: sessionId,
      appSessionId: appSessionId,
      approvalDecision: decision,
    );
  }

  /// GET /command/:id/status. Returns current stage + accumulated events +
  /// finalResponse (null until the command finishes).
  Future<CommandStatus> fetchCommandStatus({
    required String serverUrl,
    required String commandId,
  }) async {
    final uri = _buildUri(serverUrl, '/command/$commandId/status');
    final response = await _client.get(uri);
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? response.body);
    }
    return CommandStatus(
      commandId: commandId,
      stage: (decoded['stage'] as String?) ?? 'unknown',
      message: (decoded['message'] as String?) ?? '',
      events: (decoded['events'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CommandEvent.fromJson)
              .toList() ??
          const [],
      finalResponse: decoded['finalResponse'] is Map<String, dynamic>
          ? CommandResponse.fromJson(
              decoded['finalResponse'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Short-polling stream of command events. Emits every new event once,
  /// then completes after the final response arrives (or [timeout] elapses).
  Stream<CommandEvent> streamCommandEvents({
    required String serverUrl,
    required String commandId,
    Duration interval = const Duration(milliseconds: 800),
    Duration timeout = const Duration(minutes: 5),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    var lastSequence = 0;
    while (DateTime.now().isBefore(deadline)) {
      CommandStatus status;
      try {
        status = await fetchCommandStatus(
          serverUrl: serverUrl,
          commandId: commandId,
        );
      } catch (error) {
        yield CommandEvent(
          commandId: commandId,
          sequence: lastSequence + 1,
          stage: 'agent_log',
          message: 'poll failed: $error',
          timestamp: DateTime.now().toUtc().toIso8601String(),
        );
        await Future<void>.delayed(interval);
        continue;
      }

      for (final event in status.events) {
        if (event.sequence <= lastSequence) continue;
        lastSequence = event.sequence;
        yield event;
      }

      if (status.isFinal) return;
      await Future<void>.delayed(interval);
    }
  }

  /// GET /session/current.
  Future<SessionState?> fetchCurrentSession(String serverUrl) async {
    final uri = _buildUri(serverUrl, '/session/current');
    final response = await _client.get(uri);
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? response.body);
    }
    final session = decoded['session'];
    if (session is! Map<String, dynamic>) return null;
    return SessionState.fromJson(session);
  }

  /// POST /app/:appSessionId/reload. Asks the server-managed Flutter dev
  /// server to perform a hot reload (`r`). Throws when the server returns a
  /// non-2xx response so the caller can surface the failure to the user.
  Future<String> triggerHotReload({
    required String serverUrl,
    required String appSessionId,
  }) async {
    final uri = _buildUri(serverUrl, '/app/$appSessionId/reload');
    final response = await _client.post(uri);
    final decoded = _decode(response);
    if (response.statusCode >= 400 || decoded['success'] == false) {
      throw Exception(
        decoded['message'] ?? 'Hot reload failed (${response.statusCode}).',
      );
    }
    return (decoded['message'] as String?) ?? 'Hot reload requested.';
  }

  /// POST /app/:appSessionId/restart. Triggers a hot restart (`R`). This
  /// resets app state so callers should confirm with the user first.
  Future<String> triggerHotRestart({
    required String serverUrl,
    required String appSessionId,
  }) async {
    final uri = _buildUri(serverUrl, '/app/$appSessionId/restart');
    final response = await _client.post(uri);
    final decoded = _decode(response);
    if (response.statusCode >= 400 || decoded['success'] == false) {
      throw Exception(
        decoded['message'] ?? 'Hot restart failed (${response.statusCode}).',
      );
    }
    return (decoded['message'] as String?) ?? 'Hot restart requested.';
  }

  /// GET /app/session. Returns the current server-managed app session id, or
  /// null when the user launched the app manually.
  Future<String?> fetchAppSessionId(String serverUrl) async {
    final uri = _buildUri(serverUrl, '/app/session');
    final response = await _client.get(uri);
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? response.body);
    }
    final session = decoded['session'];
    if (session is Map<String, dynamic>) {
      return session['appSessionId'] as String?;
    }
    return null;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) return raw;
      return <String, dynamic>{'body': raw};
    } catch (_) {
      return <String, dynamic>{'message': response.body};
    }
  }

  void close() => _client.close();
}
