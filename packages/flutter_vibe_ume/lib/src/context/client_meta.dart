class ClientMeta {
  const ClientMeta({
    this.platform = 'flutter',
    required this.appName,
    this.appVersion,
    this.runtimeTarget,
    this.debugMode,
    this.umePluginVersion,
    this.serverUrl,
    this.appLaunchMode,
  });

  final String platform;
  final String appName;
  final String? appVersion;

  /// One of: 'web' | 'android' | 'ios' | 'macos' | 'unknown'.
  final String? runtimeTarget;
  final bool? debugMode;
  final String? umePluginVersion;
  final String? serverUrl;

  /// One of: 'server-managed' | 'manual'.
  final String? appLaunchMode;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'appName': appName,
        if (appVersion != null) 'appVersion': appVersion,
        if (runtimeTarget != null) 'runtimeTarget': runtimeTarget,
        if (debugMode != null) 'debugMode': debugMode,
        if (umePluginVersion != null) 'umePluginVersion': umePluginVersion,
        if (serverUrl != null) 'serverUrl': serverUrl,
        if (appLaunchMode != null) 'appLaunchMode': appLaunchMode,
      };
}
