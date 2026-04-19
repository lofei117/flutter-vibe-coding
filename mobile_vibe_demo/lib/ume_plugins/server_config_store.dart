import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigStore {
  static const defaultServerUrl = 'http://192.168.11.169:8787';
  static const _serverUrlKey = 'ai_vibe_server_url';
  static const _sessionIdKey = 'ai_vibe_session_id';
  static const _appSessionIdKey = 'ai_vibe_app_session_id';
  static const lastSessionKey = 'ai_vibe_last_session';

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_serverUrlKey);
    if (storedValue == null ||
        storedValue == 'http://192.168.1.100:8787' ||
        storedValue == 'http://192.168.31.10:8787') {
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
