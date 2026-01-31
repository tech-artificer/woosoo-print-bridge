class DeviceConfig {
  final String apiBaseUrl;
  final String wsUrl;

  final String? deviceId;
  final String? authToken;

  final String? printerName;
  final String? printerAddress; // MAC
  final String printerId; // backend identifier

  const DeviceConfig({
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.deviceId,
    required this.authToken,
    required this.printerName,
    required this.printerAddress,
    required this.printerId,
  });

  DeviceConfig copyWith({
    String? apiBaseUrl,
    String? wsUrl,
    String? deviceId,
    String? authToken,
    String? printerName,
    String? printerAddress,
    String? printerId,
  }) {
    return DeviceConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      wsUrl: wsUrl ?? this.wsUrl,
      deviceId: deviceId ?? this.deviceId,
      authToken: authToken ?? this.authToken,
      printerName: printerName ?? this.printerName,
      printerAddress: printerAddress ?? this.printerAddress,
      printerId: printerId ?? this.printerId,
    );
  }
}
