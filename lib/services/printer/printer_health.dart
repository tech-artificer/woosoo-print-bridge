enum PrinterConnectionStatus {
  connected,
  disconnected,
  disconnectRequested,
  bluetoothOff,
  unknown,
}

class PrinterHealthResult {
  final bool connected;
  final bool statusSupported;
  final bool paperOk;
  final bool coverClosed;
  final bool offline;
  final List<int>? rawStatus;
  final DateTime checkedAt;
  final String? message;

  const PrinterHealthResult({
    required this.connected,
    required this.statusSupported,
    required this.paperOk,
    required this.coverClosed,
    required this.offline,
    required this.rawStatus,
    required this.checkedAt,
    required this.message,
  });

  factory PrinterHealthResult.ready({
    DateTime? checkedAt,
    List<int>? rawStatus,
  }) =>
      PrinterHealthResult(
        connected: true,
        statusSupported: true,
        paperOk: true,
        coverClosed: true,
        offline: false,
        rawStatus: rawStatus,
        checkedAt: checkedAt ?? DateTime.now().toUtc(),
        message: null,
      );

  factory PrinterHealthResult.disconnected({DateTime? checkedAt}) =>
      PrinterHealthResult(
        connected: false,
        statusSupported: false,
        paperOk: false,
        coverClosed: false,
        offline: true,
        rawStatus: null,
        checkedAt: checkedAt ?? DateTime.now().toUtc(),
        message: 'Printer disconnected.',
      );

  factory PrinterHealthResult.unsupported({
    DateTime? checkedAt,
    String? message,
  }) =>
      PrinterHealthResult(
        connected: true,
        statusSupported: false,
        paperOk: false,
        coverClosed: false,
        offline: true,
        rawStatus: null,
        checkedAt: checkedAt ?? DateTime.now().toUtc(),
        message: message ?? 'Printer status response is unsupported.',
      );

  bool get ready =>
      connected && statusSupported && paperOk && coverClosed && !offline;

  String get blockReason {
    if (!connected) return 'printer_disconnected';
    if (!statusSupported) return 'printer_status_unsupported';
    if (!paperOk) return 'printer_paper_out';
    if (!coverClosed) return 'printer_cover_open';
    if (offline) return 'printer_offline';
    return 'printer_health_failed';
  }

  String get operatorMessage {
    if (message != null && message!.trim().isNotEmpty) return message!;
    switch (blockReason) {
      case 'printer_disconnected':
        return 'Printer disconnected.';
      case 'printer_status_unsupported':
        return 'Printer did not return a readable status response.';
      case 'printer_paper_out':
        return 'Printer paper is out.';
      case 'printer_cover_open':
        return 'Printer cover is open.';
      case 'printer_offline':
        return 'Printer is offline.';
      default:
        return 'Printer health check failed.';
    }
  }
}
