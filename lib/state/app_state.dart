import '../models/device_config.dart';
import '../models/print_job.dart';

class PrinterStatus {
  final bool connected;
  final String? name;
  final String? address;
  final String? error;

  const PrinterStatus({required this.connected, required this.name, required this.address, required this.error});
  static const empty = PrinterStatus(connected: false, name: null, address: null, error: null);

  PrinterStatus copyWith({bool? connected, String? name, String? address, String? error}) =>
      PrinterStatus(
        connected: connected ?? this.connected,
        name: name ?? this.name,
        address: address ?? this.address,
        error: error ?? this.error,
      );
}

class AppState {
  final bool initialized;
  final bool authenticating;
  final DeviceConfig config;

  final PrinterStatus printer;
  final List<PrintJob> queue;

  final int? sessionId;
  final String? lastError;
  final bool wsConnected;
  final bool networkConnected;

  const AppState({
    required this.initialized,
    required this.authenticating,
    required this.config,
    required this.printer,
    required this.queue,
    required this.sessionId,
    required this.lastError,
    required this.wsConnected,
    required this.networkConnected,
  });

  int get pendingCount => queue.where((j) => j.status == PrintJobStatus.pending).length;
  int get failedCount => queue.where((j) => j.status == PrintJobStatus.failed).length;
  int get successCount => queue.where((j) => j.status == PrintJobStatus.success).length;

  AppState copyWith({
    bool? initialized,
    bool? authenticating,
    DeviceConfig? config,
    PrinterStatus? printer,
    List<PrintJob>? queue,
    int? sessionId,
    String? lastError,
    bool? wsConnected,
    bool? networkConnected,
  }) =>
      AppState(
        initialized: initialized ?? this.initialized,
        authenticating: authenticating ?? this.authenticating,
        config: config ?? this.config,
        printer: printer ?? this.printer,
        queue: queue ?? this.queue,
        sessionId: sessionId ?? this.sessionId,
        lastError: lastError,
        wsConnected: wsConnected ?? this.wsConnected,
        networkConnected: networkConnected ?? this.networkConnected,
      );
}
