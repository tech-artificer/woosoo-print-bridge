import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';
import 'package:woosoo_relay_device/state/app_state.dart';
import 'package:woosoo_relay_device/ui/screens/metrics_dashboard_screen.dart';

void main() {
  testWidgets('Metrics dashboard shows core metrics and activity', (tester) async {
    final cfg = DeviceConfig(
      apiBaseUrl: 'http://localhost:8000/api',
      wsUrl: 'ws://localhost:6001',
      deviceId: 'device-123',
      authToken: 'token',
      printerName: 'PB-58H',
      printerAddress: 'AA:BB:CC',
      printerId: 'printer-01',
    );

    final now = DateTime.parse('2026-01-25T10:00:00Z');
    final jobs = <PrintJob>[
      PrintJob(
        printEventId: 101,
        deviceId: 'device-123',
        orderId: 201,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: const {},
        status: PrintJobStatus.pending,
        retryCount: 0,
        lastError: null,
        createdAt: now.subtract(const Duration(minutes: 10)),
        printedAt: null,
        ackAttempts: 0,
        lastAckAttempt: null,
        printerReconnectAttempts: 1,
        lastPrinterReconnectAttempt: now.subtract(const Duration(minutes: 9)),
      ),
      PrintJob(
        printEventId: 102,
        deviceId: 'device-123',
        orderId: 202,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: const {},
        status: PrintJobStatus.printing,
        retryCount: 0,
        lastError: null,
        createdAt: now.subtract(const Duration(minutes: 8)),
        printedAt: null,
        ackAttempts: 0,
        lastAckAttempt: null,
        printerReconnectAttempts: 0,
        lastPrinterReconnectAttempt: null,
      ),
      PrintJob(
        printEventId: 103,
        deviceId: 'device-123',
        orderId: 203,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: const {},
        status: PrintJobStatus.printed_awaiting_ack,
        retryCount: 0,
        lastError: null,
        createdAt: now.subtract(const Duration(minutes: 6)),
        printedAt: now.subtract(const Duration(minutes: 5)),
        ackAttempts: 1,
        lastAckAttempt: now.subtract(const Duration(minutes: 4)),
        printerReconnectAttempts: 3,
        lastPrinterReconnectAttempt: now.subtract(const Duration(minutes: 3)),
      ),
      PrintJob(
        printEventId: 104,
        deviceId: 'device-123',
        orderId: 204,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: const {},
        status: PrintJobStatus.success,
        retryCount: 0,
        lastError: null,
        createdAt: now.subtract(const Duration(minutes: 4)),
        printedAt: now.subtract(const Duration(minutes: 3)),
        ackAttempts: 0,
        lastAckAttempt: now.subtract(const Duration(minutes: 3)),
        printerReconnectAttempts: 2,
        lastPrinterReconnectAttempt: now.subtract(const Duration(minutes: 2)),
      ),
      PrintJob(
        printEventId: 105,
        deviceId: 'device-123',
        orderId: 205,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: const {},
        status: PrintJobStatus.failed,
        retryCount: 3,
        lastError: 'Failed to print',
        createdAt: now.subtract(const Duration(minutes: 2)),
        printedAt: null,
        ackAttempts: 3,
        lastAckAttempt: now.subtract(const Duration(minutes: 1)),
        printerReconnectAttempts: 5,
        lastPrinterReconnectAttempt: now,
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
          appControllerProvider.overrideWith((ref) => _FakeAppController(ref, LoggerService(), cfg, seededState)),
        ],
        child: const MaterialApp(home: MetricsDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Metrics Dashboard'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Printing'), findsOneWidget);
    expect(find.text('Awaiting ACK'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byKey(const Key('metric_pending')), findsOneWidget);
    expect(find.byKey(const Key('metric_success')), findsOneWidget);
    expect(find.byKey(const Key('metric_failed')), findsOneWidget);
    expect(find.byKey(const Key('metric_reconnect_total')), findsOneWidget);
    expect(find.byKey(const Key('metric_reconnect_max')), findsOneWidget);

    final pendingValue = tester.widget<Text>(find.byKey(const Key('metric_pending'))).data;
    final successValue = tester.widget<Text>(find.byKey(const Key('metric_success'))).data;
    final failedValue = tester.widget<Text>(find.byKey(const Key('metric_failed'))).data;
    final reconnectTotal = tester.widget<Text>(find.byKey(const Key('metric_reconnect_total'))).data;
    final reconnectMax = tester.widget<Text>(find.byKey(const Key('metric_reconnect_max'))).data;

    expect(pendingValue, '1');
    expect(successValue, '1');
    expect(failedValue, '1');
    expect(reconnectTotal, '11');
    expect(reconnectMax, '5');

    expect(find.text('print_event_id=105'), findsOneWidget);
    expect(find.text('print_event_id=101'), findsOneWidget);
  });
}

class _FakeAppController extends AppController {
  _FakeAppController(Ref ref, LoggerService log, DeviceConfig cfg, AppState seeded) : super(ref, log, cfg) {
    state = seeded;
  }

  @override
  Future<void> init() async {}
}
