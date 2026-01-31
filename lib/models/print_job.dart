enum PrintJobStatus {
  pending,              // Job waiting to print
  printing,             // Job actively printing
  printed_awaiting_ack, // Job printed locally, waiting for server ACK
  success,              // Job printed AND acknowledged by server
  failed,               // Job failed after max retries
  cancelled             // Job explicitly cancelled
}

// Sentinel object to distinguish "not provided" from "explicitly null"
const _unset = Object();

class PrintJob {
  final int printEventId;
  final String deviceId;
  final int orderId;
  final int? sessionId;
  final String printType;
  final int? refillNumber;

  final Map<String, dynamic> payload;
  final PrintJobStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? printedAt;
  final int? ackAttempts;         // Track ACK retry count (0-3)
  final DateTime? lastAckAttempt; // Track last ACK retry time for backoff
  final int printerReconnectAttempts;         // M3.5-3: Track printer reconnect attempts (0-5)
  final DateTime? lastPrinterReconnectAttempt; // M3.5-3: Track last printer reconnect time for backoff

  const PrintJob({
    required this.printEventId,
    required this.deviceId,
    required this.orderId,
    required this.sessionId,
    required this.printType,
    required this.refillNumber,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.lastError,
    required this.createdAt,
    required this.printedAt,
    this.ackAttempts,
    this.lastAckAttempt,
    this.printerReconnectAttempts = 0,
    this.lastPrinterReconnectAttempt,
  });

  PrintJob copyWith({
    PrintJobStatus? status,
    int? retryCount,
    int? ackAttempts,
    Object? lastError = _unset,
    DateTime? printedAt,
    DateTime? lastAckAttempt,
    int? printerReconnectAttempts,
    Object? lastPrinterReconnectAttempt = _unset,
  }) =>
      PrintJob(
        printEventId: printEventId,
        deviceId: deviceId,
        orderId: orderId,
        sessionId: sessionId,
        printType: printType,
        refillNumber: refillNumber,
        payload: payload,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        ackAttempts: ackAttempts ?? this.ackAttempts,
        lastError: lastError == _unset ? this.lastError : lastError as String?,
        createdAt: createdAt,
        printedAt: printedAt ?? this.printedAt,
        lastAckAttempt: lastAckAttempt ?? this.lastAckAttempt,
        printerReconnectAttempts: printerReconnectAttempts ?? this.printerReconnectAttempts,
        lastPrinterReconnectAttempt: lastPrinterReconnectAttempt == _unset ? this.lastPrinterReconnectAttempt : lastPrinterReconnectAttempt as DateTime?,
      );

  Map<String, dynamic> toJson() => {
        'printEventId': printEventId,
        'deviceId': deviceId,
        'orderId': orderId,
        'sessionId': sessionId,
        'printType': printType,
        'refillNumber': refillNumber,
        'payload': payload,
        'status': status.name,
        'retryCount': retryCount,
        'lastError': lastError,
        'createdAt': createdAt.toIso8601String(),
        'printedAt': printedAt?.toIso8601String(),
        'ackAttempts': ackAttempts,
        'lastAckAttempt': lastAckAttempt?.toIso8601String(),
        'printerReconnectAttempts': printerReconnectAttempts,
        'lastPrinterReconnectAttempt': lastPrinterReconnectAttempt?.toIso8601String(),
      };

  static PrintJob fromJson(Map<String, dynamic> j) => PrintJob(
        printEventId: j['printEventId'] as int,
        deviceId: j['deviceId'] as String,
        orderId: j['orderId'] as int,
        sessionId: j['sessionId'] as int?,
        printType: (j['printType'] as String?) ?? 'INITIAL',
        refillNumber: j['refillNumber'] as int?,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        status: PrintJobStatus.values.byName(j['status'] as String),
        retryCount: (j['retryCount'] as int?) ?? 0,
        lastError: j['lastError'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        printedAt: j['printedAt'] == null ? null : DateTime.parse(j['printedAt'] as String),
        ackAttempts: (j['ackAttempts'] as int?) ?? 0,
        lastAckAttempt: j['lastAckAttempt'] == null ? null : DateTime.parse(j['lastAckAttempt'] as String),
        printerReconnectAttempts: (j['printerReconnectAttempts'] as int?) ?? 0,
        lastPrinterReconnectAttempt: j['lastPrinterReconnectAttempt'] == null ? null : DateTime.parse(j['lastPrinterReconnectAttempt'] as String),
      );
}
