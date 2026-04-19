import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigStore {
  static const defaultServerUrl = 'http://192.168.11.169:8787';
  static const _serverUrlKey = 'ai_vibe_server_url';

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
}
