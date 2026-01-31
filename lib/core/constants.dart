import 'package:flutter/foundation.dart';

class AppConstants {
    static const String defaultApiBaseUrl = 'https://192.168.100.85:8000';
    
    // Build-time configuration via --dart-define
    // Usage: flutter build apk --dart-define=REVERB_APP_KEY=your_key_here
    static const String _reverbAppKey = String.fromEnvironment(
      'REVERB_APP_KEY',
      defaultValue: 'vhy4mrtlhdwa61lukcze', // Fallback for development only
    );
    
    // Connect via nginx proxy with TLS termination (port 8000/reverb path)
    // When system uses HTTPS, WebSocket must use WSS via nginx reverse proxy
    static String get defaultWsUrl =>
      'wss://192.168.100.85:8000/reverb/app/$_reverbAppKey?protocol=7&client=flutter&version=1.0';

  static const Duration queueTick = Duration(seconds: 2);
  static const Duration pollingInterval = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  static const int receiptCharsPerLine = 32;
  static const int maxPrintAttempts = 3;
  static const int maxApiRetries = 3;

  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[RelayDevice] $message');
    }
  }
}
