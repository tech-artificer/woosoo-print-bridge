import '../models/device_config.dart';
import '../models/print_job.dart';

const _unset = Object();

class PrinterStatus {
  final bool connected;
  final String? name;
  final String? address;
  final String? error;

  const PrinterStatus(
      {required this.connected,
      required this.name,
      required this.address,
      required this.error});
  static const empty =
      PrinterStatus(connected: false, name: null, address: null, error: null);

  PrinterStatus copyWith(
          {bool? connected, String? name, String? address, String? error}) =>
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
  final String platform;
  final String osVersion;

  final PrinterStatus printer;
  final List<PrintJob> queue;

  final int? sessionId;
  final String? lastError;
  final bool wsConnected;
  final bool networkConnected;
  final int historicalTotalJobs;
  final int historicalSuccessCount;
  final int historicalFailedCount;
  final int historicalReconnectAttemptTotal;
  final int historicalReconnectAttemptMax;
  final DateTime? historicalLastReconnectAttempt;
  final DateTime? historicalLastJobTime;
  final DateTime? metricsTrackingSince;
  // Per-service error reasons: empty string = no error, non-empty = last error message.
  // Preserved across unrelated state updates (uses ?? this.field in copyWith).
  final String? lastPollError;
  final String? lastWsError;
  final bool queuePaused;
  final String? queuePauseReason;
  final DateTime? lastQueueTick;
  final int? lastSelectedPrintEventId;
  final String? lastQueueSkipReason;

  const AppState({
    required this.initialized,
    required this.authenticating,
    required this.config,
    required this.platform,
    required this.osVersion,
    required this.printer,
    required this.queue,
    required this.sessionId,
    required this.lastError,
    required this.wsConnected,
    required this.networkConnected,
    required this.historicalTotalJobs,
    required this.historicalSuccessCount,
    required this.historicalFailedCount,
    required this.historicalReconnectAttemptTotal,
    required this.historicalReconnectAttemptMax,
    required this.historicalLastReconnectAttempt,
    required this.historicalLastJobTime,
    required this.metricsTrackingSince,
    this.lastPollError,
    this.lastWsError,
    this.queuePaused = false,
    this.queuePauseReason,
    this.lastQueueTick,
    this.lastSelectedPrintEventId,
    this.lastQueueSkipReason,
  });

  int get pendingCount =>
      queue.where((j) => j.status == PrintJobStatus.pending).length;
  int get failedCount =>
      queue.where((j) => j.status == PrintJobStatus.failed).length;
  int get successCount =>
      queue.where((j) => j.status == PrintJobStatus.success).length;

  AppState copyWith({
    bool? initialized,
    bool? authenticating,
    DeviceConfig? config,
    String? platform,
    String? osVersion,
    PrinterStatus? printer,
    List<PrintJob>? queue,
    int? sessionId,
    Object? lastError = _unset,
    bool? wsConnected,
    bool? networkConnected,
    int? historicalTotalJobs,
    int? historicalSuccessCount,
    int? historicalFailedCount,
    int? historicalReconnectAttemptTotal,
    int? historicalReconnectAttemptMax,
    DateTime? historicalLastReconnectAttempt,
    DateTime? historicalLastJobTime,
    DateTime? metricsTrackingSince,
    String? lastPollError,
    String? lastWsError,
    bool? queuePaused,
    Object? queuePauseReason = _unset,
    DateTime? lastQueueTick,
    Object? lastSelectedPrintEventId = _unset,
    Object? lastQueueSkipReason = _unset,
  }) =>
      AppState(
        initialized: initialized ?? this.initialized,
        authenticating: authenticating ?? this.authenticating,
        config: config ?? this.config,
        platform: platform ?? this.platform,
        osVersion: osVersion ?? this.osVersion,
        printer: printer ?? this.printer,
        queue: queue ?? this.queue,
        sessionId: sessionId ?? this.sessionId,
        lastError: lastError == _unset ? this.lastError : lastError as String?,
        wsConnected: wsConnected ?? this.wsConnected,
        networkConnected: networkConnected ?? this.networkConnected,
        historicalTotalJobs: historicalTotalJobs ?? this.historicalTotalJobs,
        historicalSuccessCount:
            historicalSuccessCount ?? this.historicalSuccessCount,
        historicalFailedCount:
            historicalFailedCount ?? this.historicalFailedCount,
        historicalReconnectAttemptTotal: historicalReconnectAttemptTotal ??
            this.historicalReconnectAttemptTotal,
        historicalReconnectAttemptMax:
            historicalReconnectAttemptMax ?? this.historicalReconnectAttemptMax,
        historicalLastReconnectAttempt: historicalLastReconnectAttempt ??
            this.historicalLastReconnectAttempt,
        historicalLastJobTime:
            historicalLastJobTime ?? this.historicalLastJobTime,
        metricsTrackingSince: metricsTrackingSince ?? this.metricsTrackingSince,
        lastPollError: lastPollError ?? this.lastPollError,
        lastWsError: lastWsError ?? this.lastWsError,
        queuePaused: queuePaused ?? this.queuePaused,
        queuePauseReason: queuePauseReason == _unset
            ? this.queuePauseReason
            : queuePauseReason as String?,
        lastQueueTick: lastQueueTick ?? this.lastQueueTick,
        lastSelectedPrintEventId: lastSelectedPrintEventId == _unset
            ? this.lastSelectedPrintEventId
            : lastSelectedPrintEventId as int?,
        lastQueueSkipReason: lastQueueSkipReason == _unset
            ? this.lastQueueSkipReason
            : lastQueueSkipReason as String?,
      );
}
