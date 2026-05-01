import 'printer_health.dart';
export 'printer_health.dart';

abstract class PrinterService {
  Future<void> init();
  Future<bool> isConnected();
  Stream<PrinterConnectionStatus> watchConnectionStatus();
  Future<PrinterHealthResult> checkHealth({
    Duration timeout = const Duration(seconds: 2),
  });
  Future<List<Map<String, String>>> bondedDevices();
  Future<bool> connectByAddress(String address);
  Future<void> disconnect();
  Future<bool> printLines(List<String> lines);
  Future<bool> testPrint();
  Future<void> cut();
}
