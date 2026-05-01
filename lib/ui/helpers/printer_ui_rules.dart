import '../../state/app_state.dart';

const Set<String> _blockingQueueReasons = {
  'queue_paused',
  'printer_no_address',
  'printer_disconnected',
  'printer_status_unsupported',
  'printer_paper_out',
  'printer_cover_open',
  'printer_offline',
  'printer_health_failed',
  'print_command_failed',
  'printer_reconnect_backoff',
  'printer_reconnect_max_attempts',
};

bool printerQueueReasonIsBlocking(String? reason, bool strictStatusRequired) {
  if (reason == 'printer_status_unsupported' && !strictStatusRequired) {
    return false;
  }
  return _blockingQueueReasons.contains(reason);
}

bool printerHasHardBlock(PrinterStatus printer, bool strictStatusRequired) {
  if (!printer.connected) return true;
  if (!printer.statusSupported) return strictStatusRequired;
  if (!printer.paperOk) return true;
  if (!printer.coverClosed) return true;
  if (printer.offline) return true;
  return false;
}

bool printerHasCompatibleStatusWarning(
  PrinterStatus printer,
  bool strictStatusRequired,
) {
  return !strictStatusRequired && printer.connected && !printer.statusSupported;
}
