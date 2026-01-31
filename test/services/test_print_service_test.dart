import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/printer/printer_service.dart';
import 'package:woosoo_relay_device/services/test_print_service.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';
import 'package:woosoo_relay_device/state/app_state.dart';

void main() {
  group('TestPrintService', () {
    late DeviceConfig cfg;
    late LoggerService log;
    late AppState seededState;

    setUp(() {
      cfg = DeviceConfig(
        apiBaseUrl: 'http://localhost:8000/api',
        wsUrl: 'ws://localhost:6001',
        deviceId: 'device-xyz',
        authToken: 'token',
        printerName: 'PB-58H',
        printerAddress: 'AA:BB:CC:DD:EE:FF',
        printerId: 'printer-01',
      );
      log = LoggerService();
      seededState = AppState(
        initialized: true,
        authenticating: false,
        config: cfg,
        printer: const PrinterStatus(connected: false, name: null, address: null, error: null),
        queue: const [],
        sessionId: 1,
        lastError: null,
        wsConnected: true,
        networkConnected: true,
      );
    });

    test('prints diagnostics with device + printer metadata', () async {
      final fakePrinter = _FakePrinterService(connectSucceeds: true, printSucceeds: true);

      final container = ProviderContainer(overrides: [
        printerServiceProvider.overrideWithValue(fakePrinter),
        loggerProvider.overrideWithValue(log),
        appControllerProvider.overrideWith((ref) => _FakeAppController(ref, log, cfg, seededState)),
      ]);

      final svc = container.read(testPrintServiceProvider);
      final result = await svc.printTest();

      expect(result.success, isTrue);
      expect(fakePrinter.connectedAttempts, equals(1));
      expect(fakePrinter.printedLines.join('\n'), contains('Device ID: device-xyz'));
      expect(fakePrinter.printedLines.join('\n'), contains('MAC: AA:BB:CC:DD:EE:FF'));
      expect(fakePrinter.printedLines.join('\n'), contains('TEST OK'));
    });

    test('fails fast when printer is unavailable', () async {
      final fakePrinter = _FakePrinterService(connectSucceeds: false, printSucceeds: false);

      final container = ProviderContainer(overrides: [
        printerServiceProvider.overrideWithValue(fakePrinter),
        loggerProvider.overrideWithValue(log),
        appControllerProvider.overrideWith((ref) => _FakeAppController(ref, log, cfg, seededState)),
      ]);

      final svc = container.read(testPrintServiceProvider);
      final result = await svc.printTest();

      expect(result.success, isFalse);
      expect(fakePrinter.printedLines, isEmpty);
    });
  });
}

class _FakeAppController extends AppController {
  _FakeAppController(Ref ref, LoggerService log, DeviceConfig cfg, AppState seeded)
      : super(ref, log, cfg) {
    state = seeded;
  }

  @override
  Future<void> init() async {}
}

class _FakePrinterService implements PrinterService {
  final bool connectSucceeds;
  final bool printSucceeds;

  int connectedAttempts = 0;
  bool _connected = false;
  final List<String> printedLines = [];

  _FakePrinterService({required this.connectSucceeds, required this.printSucceeds});

  @override
  Future<bool> connectByAddress(String address) async {
    connectedAttempts++;
    _connected = connectSucceeds;
    return connectSucceeds;
  }

  @override
  Future<void> cut() async {}

  @override
  Future<bool> isConnected() async => _connected;

  @override
  Future<List<Map<String, String>>> bondedDevices() async => const [];

  @override
  Future<bool> printLines(List<String> lines) async {
    printedLines.addAll(lines);
    return printSucceeds;
  }

  @override
  Future<bool> testPrint() async => false;

  @override
  Future<void> disconnect() async { _connected = false; }

  @override
  Future<void> init() async {}
}
