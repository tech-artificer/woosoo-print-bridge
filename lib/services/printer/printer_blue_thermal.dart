import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import '../logger_service.dart';
import 'printer_service.dart';

class PrinterBlueThermal implements PrinterService {
  final LoggerService log;
  final BlueThermalPrinter _bt = BlueThermalPrinter.instance;

  PrinterBlueThermal(this.log);

  @override
  Future<void> init() async {}

  @override
  Future<List<Map<String, String>>> bondedDevices() async {
    final devices = await _bt.getBondedDevices();
    return devices
        .map((d) => {'name': d.name ?? '', 'address': d.address ?? ''})
        .where((d) => (d['address'] ?? '').isNotEmpty)
        .toList();
  }

  @override
  Future<bool> connectByAddress(String address) async {
    try {
      final devices = await _bt.getBondedDevices();
      final match = devices.firstWhere(
        (d) => (d.address ?? '').toUpperCase() == address.toUpperCase(),
        orElse: () => BluetoothDevice(address, address),
      );
      final ok = await _bt.connect(match);
      log.i('Printer connectByAddress($address) => $ok');
      return ok == true;
    } catch (e, st) {
      log.e('Printer connect error', e, st);
      return false;
    }
  }

  @override
  Future<void> disconnect() async { try { await _bt.disconnect(); } catch (_) {} }

  @override
  Future<bool> isConnected() async { try { return (await _bt.isConnected) == true; } catch (_) { return false; } }

  @override
  Future<bool> printLines(List<String> lines) async {
    try {
      if (!await isConnected()) return false;
      for (final line in lines) {
        if (line.isEmpty) {
          await _bt.printNewLine();
        } else {
          await _bt.printCustom(line, 0, 0);
        }
      }
      return true;
    } catch (e, st) {
      log.e('printLines failed', e, st);
      return false;
    }
  }

  @override
  Future<bool> testPrint() => printLines(['WOOSOO RELAY DEVICE', 'PB-58H TEST OK', '']);

  @override
  Future<void> cut() async { try { await _bt.paperCut(); } catch (_) {} }
}
