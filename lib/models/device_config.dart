import '../core/constants.dart';

class DeviceConfig {
  final String apiBaseUrl;
  final String wsUrl;

  final String? deviceId;
  final String? authToken;

  final String? printerName;
  final String? printerAddress; // MAC
  final String printerId; // backend identifier

  /// Reverb app key — kept in sync with woosoo-nexus REVERB_APP_KEY.
  /// Stored separately so changing the API host auto-derives a new WS URL.
  final String reverbAppKey;

  /// The last registration/security code used to register this device.
  /// Persisted so it remains visible after app restarts.
  final String? registrationCode;

  /// Printer verification mode.
  /// true  => strict ESC/POS status verification is required.
  /// false => compatible mode (connected-only fallback when status is unsupported).
  final bool strictStatusRequired;

  const DeviceConfig({
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.deviceId,
    required this.authToken,
    required this.printerName,
    required this.printerAddress,
    required this.printerId,
    this.reverbAppKey = AppConstants.defaultReverbAppKey,
    this.registrationCode,
    this.strictStatusRequired = false,
  });

  DeviceConfig copyWith({
    String? apiBaseUrl,
    String? wsUrl,
    String? deviceId,
    String? authToken,
    String? printerName,
    String? printerAddress,
    String? printerId,
    String? reverbAppKey,
    String? registrationCode,
    bool? strictStatusRequired,
  }) {
    return DeviceConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      wsUrl: wsUrl ?? this.wsUrl,
      deviceId: deviceId ?? this.deviceId,
      authToken: authToken ?? this.authToken,
      printerName: printerName ?? this.printerName,
      printerAddress: printerAddress ?? this.printerAddress,
      printerId: printerId ?? this.printerId,
      reverbAppKey: reverbAppKey ?? this.reverbAppKey,
      registrationCode: registrationCode ?? this.registrationCode,
      strictStatusRequired: strictStatusRequired ?? this.strictStatusRequired,
    );
  }

  /// Returns a copy with the WS URL re-derived from apiBaseUrl + reverbAppKey.
  DeviceConfig withDerivedWsUrl() {
    return copyWith(wsUrl: AppConstants.deriveWsUrl(apiBaseUrl, appKey: reverbAppKey));
  }
}
