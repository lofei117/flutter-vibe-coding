class ClientMeta {
  const ClientMeta({
    this.platform = 'flutter',
    required this.appName,
    this.appVersion,
    this.buildNumber,
    this.gitSha,
    this.runtimeTarget,
    this.debugMode,
    this.buildMode,
    this.umePluginVersion,
    this.serverUrl,
    this.appLaunchMode,
  });

  final String platform;
  final String appName;
  final String? appVersion;
  final String? buildNumber;
  final String? gitSha;

  /// One of: 'web' | 'android' | 'ios' | 'macos' | 'unknown'.
  final String? runtimeTarget;
  final bool? debugMode;

  /// One of: 'debug' | 'profile' | 'release' | 'unknown'. Used by the server
  /// to pick the right pipeline (live edit vs feedback ticket).
  final String? buildMode;
  final String? umePluginVersion;
  final String? serverUrl;

  /// One of: 'server-managed' | 'manual'.
  final String? appLaunchMode;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'appName': appName,
        if (appVersion != null) 'appVersion': appVersion,
        if (buildNumber != null) 'buildNumber': buildNumber,
        if (gitSha != null) 'gitSha': gitSha,
        if (runtimeTarget != null) 'runtimeTarget': runtimeTarget,
        if (debugMode != null) 'debugMode': debugMode,
        if (buildMode != null) 'buildMode': buildMode,
        if (umePluginVersion != null) 'umePluginVersion': umePluginVersion,
        if (serverUrl != null) 'serverUrl': serverUrl,
        if (appLaunchMode != null) 'appLaunchMode': appLaunchMode,
      };
}
