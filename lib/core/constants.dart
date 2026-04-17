import 'package:flutter/foundation.dart';

class AppConstants {
  // Default API URL — override at build time via --dart-define=API_BASE_URL=<url>
  // or change at runtime in Settings. No hardcoded production IPs.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  // Reverb app key — fetched automatically from the server at auth time.
  // Can be overridden at build time via --dart-define=REVERB_APP_KEY=<key>
  // or changed at runtime in Settings (stored in SharedPreferences).
  static const String defaultReverbAppKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: '',
  );

  /// Derive the WebSocket URL from an API base URL and Reverb app key.
  /// Converts https:// → wss://, http:// → ws://, preserves host and port.
  static String deriveWsUrl(String apiBaseUrl, {String? appKey}) {
    final key = (appKey ?? '').isNotEmpty ? appKey! : defaultReverbAppKey;
    if (apiBaseUrl.isEmpty) return '';
    try {
      final uri = Uri.parse(apiBaseUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final host = uri.host.isNotEmpty ? uri.host : 'localhost';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://$host$port/app/$key?protocol=7&client=flutter&version=1.0';
    } catch (_) {
      return '';
    }
  }

  static String get defaultWsUrl =>
      deriveWsUrl(defaultApiBaseUrl, appKey: defaultReverbAppKey);

  static const Duration queueTick = Duration(seconds: 2);
  static const Duration pollingInterval = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  static const int receiptCharsPerLine = 32;
  static const int maxPrintAttempts = 3;
  static const int maxApiRetries = 3;

  /// Hosts for which self-signed TLS certificates are accepted in release builds.
  /// Includes the API host derived at runtime plus common local aliases.
  /// NOT a global bypass — only private/local endpoints.
  /// Call [updateTrustedHosts] when the API base URL changes.
  static Set<String> trustedLocalHosts = {'localhost'};

  /// Update the trusted hosts set based on the current API base URL.
  static void updateTrustedHosts(String? apiBaseUrl) {
    final hosts = <String>{'localhost'};
    if (apiBaseUrl != null && apiBaseUrl.isNotEmpty) {
      try {
        final host = Uri.parse(apiBaseUrl).host;
        if (host.isNotEmpty) hosts.add(host);
      } catch (_) {}
    }
    trustedLocalHosts = hosts;
  }

  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[RelayDevice] $message');
    }
  }
}
