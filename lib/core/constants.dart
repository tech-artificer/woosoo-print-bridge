import 'package:flutter/foundation.dart';

class AppConstants {
  static const String defaultApiBaseUrl = 'https://192.168.100.7:8443';

  // Reverb app key — copied from woosoo-nexus REVERB_APP_KEY.
  // Can be overridden at build time via --dart-define=REVERB_APP_KEY=<key>
  // or changed at runtime in the Settings screen (stored in SharedPreferences).
  static const String defaultReverbAppKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: '2f8e4a7c9b3d6e1a5f0c8e2b7d4a9c6f',
  );

  /// Derive the WebSocket URL from an API base URL and Reverb app key.
  /// Converts https:// → wss://, http:// → ws://, preserves host and port.
  static String deriveWsUrl(String apiBaseUrl, {String? appKey}) {
    final key = (appKey ?? '').isNotEmpty ? appKey! : defaultReverbAppKey;
    try {
      final uri = Uri.parse(apiBaseUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final host = uri.host.isNotEmpty ? uri.host : '192.168.100.7';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://$host$port/app/$key?protocol=7&client=flutter&version=1.0';
    } catch (_) {
      return defaultWsUrl;
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
  /// Restricted to known local Pi network endpoints only — NOT a global bypass.
  static const Set<String> trustedLocalHosts = {
    '192.168.100.7',
    'woosoo.local',
    'api.woosoo.local',
  };

  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[RelayDevice] $message');
    }
  }
}
