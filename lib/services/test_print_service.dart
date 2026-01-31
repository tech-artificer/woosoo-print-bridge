import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import 'logger_service.dart';
import 'printer/printer_service.dart';

class TestPrintResult {
  final bool success;
  final String message;

  const TestPrintResult(this.success, this.message);
}

class TestPrintService {
  final Ref ref;
  final LoggerService log;
  final PrinterService printer;

  TestPrintService(this.ref, this.log, this.printer);

  Future<TestPrintResult> printTest() async {
    final cfg = ref.read(appControllerProvider).config;
    final address = cfg.printerAddress;
    final name = cfg.printerName;
    final deviceId = cfg.deviceId;

    var connected = await printer.isConnected();
    if (!connected && address != null && address.isNotEmpty) {
      await printer.connectByAddress(address);
      connected = await printer.isConnected();
    }

    if (!connected) {
      return const TestPrintResult(false, 'Printer not connected. Pair and select a printer first.');
    }

    final now = DateTime.now().toUtc();
    final lines = <String>[
      'WOOSOO RELAY DEVICE',
      '--- TEST PRINT ---',
      'Device ID: ${deviceId ?? '(unset)'}',
      'Printer: ${name ?? '(unset)'}',
      'MAC: ${address ?? '(unset)'}',
      'Time: ${now.toIso8601String()}',
      'TEST OK',
      '',
    ];

    final ok = await printer.printLines(lines);
    if (!ok) {
      return const TestPrintResult(false, 'Test print failed');
    }

    await printer.cut();
    log.i('Test print sent (device_id=${deviceId ?? ''}, mac=${address ?? ''}) at ${now.toIso8601String()}');
    return const TestPrintResult(true, 'Test print sent!');
  }
}

final testPrintServiceProvider = Provider<TestPrintService>((ref) {
  final log = ref.read(loggerProvider);
  final printer = ref.read(printerServiceProvider);
  return TestPrintService(ref, log, printer);
});
