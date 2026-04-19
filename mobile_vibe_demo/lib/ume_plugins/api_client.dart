import 'dart:convert';

import 'package:http/http.dart' as http;

class AiCommandResponse {
  const AiCommandResponse({
    required this.success,
    required this.message,
    required this.applied,
    required this.reloadTriggered,
    required this.raw,
  });

  final bool success;
  final String message;
  final bool applied;
  final bool reloadTriggered;
  final Map<String, dynamic> raw;

  factory AiCommandResponse.fromJson(Map<String, dynamic> json) {
    return AiCommandResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      applied: json['applied'] == true,
      reloadTriggered: json['reloadTriggered'] == true,
      raw: json,
    );
  }
}

class AiVibeApiClient {
  Future<AiCommandResponse> sendCommand({
    required String serverUrl,
    required String instruction,
  }) async {
    final baseUri = Uri.parse(serverUrl.trim());
    final uri = baseUri.replace(path: _joinPath(baseUri.path, '/command'));

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'instruction': instruction,
        'clientMeta': {
          'platform': 'flutter',
          'appName': 'mobile_vibe_demo',
          // TODO: send selected widget/runtime element info in phase 2.
        },
      }),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] ?? response.body);
    }

    return AiCommandResponse.fromJson(decoded);
  }

  String _joinPath(String basePath, String endpoint) {
    final cleanBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$cleanBase$endpoint';
  }
}
