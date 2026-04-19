import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigStore {
  const ServerConfigStore({this.defaultServerUrl = 'http://127.0.0.1:8787'});

  final String defaultServerUrl;
  static const _serverUrlKey = 'ai_vibe_server_url';
  static const _sessionIdKey = 'ai_vibe_session_id';
  static const _appSessionIdKey = 'ai_vibe_app_session_id';
  static const lastSessionKey = 'ai_vibe_last_session';
  static final RegExp _legacyPrivateIpv4Url = RegExp(
    r'^http://(?:192\.168|10\.|172\.(?:1[6-9]|2[0-9]|3[0-1]))\.\d{1,3}\.\d{1,3}:8787$',
  );

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_serverUrlKey);
    if (storedValue == null || _legacyPrivateIpv4Url.hasMatch(storedValue)) {
      await prefs.setString(_serverUrlKey, defaultServerUrl);
      return defaultServerUrl;
    }
    return storedValue;
  }

  Future<void> saveServerUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, value.trim());
  }

  Future<String?> loadSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionIdKey);
  }

  Future<void> saveSessionId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_sessionIdKey);
    } else {
      await prefs.setString(_sessionIdKey, value);
    }
  }

  Future<String?> loadAppSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appSessionIdKey);
  }

  Future<void> saveAppSessionId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_appSessionIdKey);
    } else {
      await prefs.setString(_appSessionIdKey, value);
    }
  }

  Future<String?> loadCachedSessionJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastSessionKey);
  }

  Future<void> saveCachedSessionJson(String? json) async {
    final prefs = await SharedPreferences.getInstance();
    if (json == null || json.isEmpty) {
      await prefs.remove(lastSessionKey);
    } else {
      await prefs.setString(lastSessionKey, json);
    }
  }
}
