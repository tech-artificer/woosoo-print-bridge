import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/printer/printer_service.dart';
import 'package:woosoo_relay_device/services/test_print_service.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';
import 'package:woosoo_relay_device/state/app_state.dart';
import 'package:woosoo_relay_device/ui/screens/status_screen.dart';

void main() {
  testWidgets('Status screen shows live state and queue counts', (tester) async {
    final cfg = DeviceConfig(
      apiBaseUrl: 'http://localhost:8000/api',
      wsUrl: 'ws://localhost:6001',
      deviceId: 'device-123',
      authToken: 'token',
      printerName: 'PB-58H',
      printerAddress: 'AA:BB:CC',
      printerId: 'printer-01',
    );

    final now = DateTime.parse('2026-01-23T12:00:00Z');
    final jobs = <PrintJob>[
      // Pending x2
      for (var i = 0; i < 2; i++)
        PrintJob(
          printEventId: 100 + i,
          deviceId: 'device-123',
          orderId: 200 + i,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: const {},
          status: PrintJobStatus.pending,
          retryCount: 0,
          lastError: null,
          createdAt: now.subtract(Duration(minutes: 10 - i)),
          printedAt: null,
          ackAttempts: 0,
          lastAckAttempt: null,
        ),
      // Printing x3
      for (var i = 0; i < 3; i++)
        PrintJob(
          printEventId: 200 + i,
          deviceId: 'device-123',
          orderId: 300 + i,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: const {},
          status: PrintJobStatus.printing,
          retryCount: 0,
          lastError: null,
          createdAt: now.subtract(Duration(minutes: 7 - i)),
          printedAt: null,
          ackAttempts: 0,
          lastAckAttempt: null,
        ),
      // Awaiting ACK x4
      for (var i = 0; i < 4; i++)
        PrintJob(
          printEventId: 300 + i,
          deviceId: 'device-123',
          orderId: 400 + i,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: const {},
          status: PrintJobStatus.printed_awaiting_ack,
          retryCount: 0,
          lastError: null,
          createdAt: now.subtract(Duration(minutes: 5 - i)),
          printedAt: now.subtract(Duration(minutes: 4 - i)),
          ackAttempts: 1,
          lastAckAttempt: now.subtract(Duration(minutes: 3 - i)),
        ),
      // Success x5
      for (var i = 0; i < 5; i++)
        PrintJob(
          printEventId: 400 + i,
          deviceId: 'device-123',
          orderId: 500 + i,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: const {},
          status: PrintJobStatus.success,
          retryCount: 0,
          lastError: null,
          createdAt: now.subtract(Duration(minutes: 3 - i)),
          printedAt: now.subtract(Duration(minutes: 2 - i)),
          ackAttempts: 0,
          lastAckAttempt: now.subtract(Duration(minutes: 2 - i)),
        ),
      // Failed x6
      for (var i = 0; i < 6; i++)
        PrintJob(
          printEventId: 500 + i,
          deviceId: 'device-123',
          orderId: 600 + i,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: const {},
          status: PrintJobStatus.failed,
          retryCount: 3,
          lastError: 'Failed to print',
          createdAt: now.subtract(Duration(minutes: 1 - i)),
          printedAt: null,
          ackAttempts: 3,
          lastAckAttempt: now.subtract(Duration(minutes: 1 - i)),
        ),
    ];

    final seededState = AppState(
      initialized: true,
      authenticating: false,
      config: cfg,
      printer: const PrinterStatus(connected: true, name: 'PB-58H', address: 'AA:BB:CC', error: null),
      queue: jobs,
      sessionId: 99,
      lastError: null,
      wsConnected: true,
      networkConnected: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testPrintServiceProvider.overrideWith((ref) => _InlineTestPrintService(ref)),
          appControllerProvider.overrideWith((ref) => _FakeAppController(ref, LoggerService(), cfg, seededState)),
        ],
        child: const MaterialApp(home: StatusScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('device-123'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Printing'), findsOneWidget);
    expect(find.text('Awaiting ACK'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // Pending
    expect(find.text('3'), findsOneWidget); // Printing
    expect(find.text('4'), findsOneWidget); // Awaiting ACK
    expect(find.text('5'), findsOneWidget); // Success
    expect(find.text('6'), findsOneWidget); // Failed
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

class _InlineTestPrintService extends TestPrintService {
  _InlineTestPrintService(Ref ref) : super(ref, LoggerService(), _NoopPrinter());

  @override
  Future<TestPrintResult> printTest() async => const TestPrintResult(true, 'ok');
}

class _NoopPrinter implements PrinterService {
  @override
  Future<bool> connectByAddress(String address) async => true;

  @override
  Future<void> cut() async {}

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<List<Map<String, String>>> bondedDevices() async => const [];

  @override
  Future<bool> printLines(List<String> lines) async => true;

  @override
  Future<bool> testPrint() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> init() async {}
}
