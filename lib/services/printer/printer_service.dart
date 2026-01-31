abstract class PrinterService {
  Future<void> init();
  Future<bool> isConnected();
  Future<List<Map<String, String>>> bondedDevices();
  Future<bool> connectByAddress(String address);
  Future<void> disconnect();
  Future<bool> printLines(List<String> lines);
  Future<bool> testPrint();
  Future<void> cut();
}
