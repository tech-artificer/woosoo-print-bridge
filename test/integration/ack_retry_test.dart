import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/api_service.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/queue_store.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';

/// Mock API Service for testing ACK retry behavior
class MockApiService extends ApiService {
  int _ackAttempts = 0;
  final int _failUntilAttempt;

  MockApiService(LoggerService log, {required int failUntilAttempt})
      : _failUntilAttempt = failUntilAttempt,
        super(log);

  @override
  Future<bool> markPrintEventPrinted(
    DeviceConfig config,
    int printEventId, {
    required DateTime printedAt,
    String? printerId,
    String? printerName,
    String? bluetoothAddress,
    String? appVersion,
  }) async {
    _ackAttempts++;
    // Fail until reaching target attempt count
    return _ackAttempts >= _failUntilAttempt;
  }

  void reset() => _ackAttempts = 0;
}

void main() {
  late ProviderContainer container;
  late QueueStore store;
  late LoggerService log;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // Mock path_provider for getApplicationDocumentsDirectory
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });

    container = ProviderContainer();
    log = container.read(loggerProvider);
    await log.init();

    store = container.read(queueStoreProvider);
    await store.init();
  });

  tearDown(() async {
    await store.clear();
    container.dispose();
  });

  group('C6: ACK Retry Integration Tests', () {
    test('job transitions from printed_awaiting_ack to success after flush', () async {
      // Arrange: Mock API that fails first 2 ACKs, succeeds on 3rd
      final mockApi = MockApiService(log, failUntilAttempt: 3);

      // Override API provider with mock
      final config = DeviceConfig(
        apiBaseUrl: 'http://test.local',
        wsUrl: 'ws://test.local',
        deviceId: '123',
        authToken: 'test-token',
        printerName: 'Test Printer',
        printerAddress: '00:11:22:33:44:55',
        printerId: 'test-printer-01',
      );

      final testContainer = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(mockApi),
          appControllerProvider.overrideWith((ref) {
            return AppController(ref, log, config);
          }),
        ],
      );
      addTearDown(testContainer.dispose);

      final testStore = testContainer.read(queueStoreProvider);
      await testStore.init();

      final controller = testContainer.read(appControllerProvider.notifier);

      // Create job in printed_awaiting_ack state (simulating ACK failure)
      final job = PrintJob(
        printEventId: 1,
        deviceId: '123',
        orderId: 100,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {'test': 'data'},
        status: PrintJobStatus.printed_awaiting_ack,
        retryCount: 0,
        lastError: 'ACK pending retry',
        createdAt: DateTime.now(),
        printedAt: DateTime.now(),
        ackAttempts: 0,
        lastAckAttempt: null,
      );

      await testStore.insert(job);

      // Act & Assert: First flush - ACK fails (attempt 1/3)
      await controller.flushPendingAcks();
      var updatedJob = await testStore.get(1);
      expect(updatedJob!.status, equals(PrintJobStatus.printed_awaiting_ack));
      expect(updatedJob.ackAttempts, equals(1));

      // Second flush: ACK fails (attempt 2/3)
      await Future.delayed(const Duration(seconds: 2)); // Wait for backoff
      await controller.flushPendingAcks();
      updatedJob = await testStore.get(1);
      expect(updatedJob!.status, equals(PrintJobStatus.printed_awaiting_ack));
      expect(updatedJob.ackAttempts, equals(2));

      // Third flush: ACK succeeds
      await Future.delayed(const Duration(seconds: 4)); // Wait for backoff
      await controller.flushPendingAcks();
      updatedJob = await testStore.get(1);
      expect(updatedJob!.status, equals(PrintJobStatus.success)); // ✅ Transitioned to success
      expect(updatedJob.lastError, isNull);
    });

    test('job transitions to failed after max retry attempts', () async {
      // Arrange: Mock API that always fails
      final mockApi = MockApiService(log, failUntilAttempt: 999); // Never succeeds

      final config = DeviceConfig(
        apiBaseUrl: 'http://test.local',
        wsUrl: 'ws://test.local',
        deviceId: '123',
        authToken: 'test-token',
        printerName: 'Test Printer',
        printerAddress: '00:11:22:33:44:55',
        printerId: 'test-printer-01',
      );

      final testContainer = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(mockApi),
          appControllerProvider.overrideWith((ref) {
            return AppController(ref, log, config);
          }),
        ],
      );
      addTearDown(testContainer.dispose);

      final testStore = testContainer.read(queueStoreProvider);
      await testStore.init();

      final controller = testContainer.read(appControllerProvider.notifier);

      final job = PrintJob(
        printEventId: 2,
        deviceId: '123',
        orderId: 200,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {'test': 'data'},
        status: PrintJobStatus.printed_awaiting_ack,
        retryCount: 0,
        lastError: 'ACK pending retry',
        createdAt: DateTime.now(),
        printedAt: DateTime.now(),
        ackAttempts: 0,
        lastAckAttempt: null,
      );

      await testStore.insert(job);

      // Act: Flush 3 times with backoff
      for (int i = 0; i < 3; i++) {
        final backoffSeconds = [2, 4, 8][i];
        await Future.delayed(Duration(seconds: backoffSeconds));
        await controller.flushPendingAcks();
      }

      // Assert: Max retries exceeded, marked as failed
      final updatedJob = await testStore.get(2);
      expect(updatedJob!.status, equals(PrintJobStatus.failed)); // ✅ Max retries exceeded
      expect(updatedJob.lastError, contains('ACK failed after 3 retries'));
    });

    test('backoff prevents premature retry attempts', () async {
      // Arrange
      final mockApi = MockApiService(log, failUntilAttempt: 999);

      final config = DeviceConfig(
        apiBaseUrl: 'http://test.local',
        wsUrl: 'ws://test.local',
        deviceId: '123',
        authToken: 'test-token',
        printerName: 'Test Printer',
        printerAddress: '00:11:22:33:44:55',
        printerId: 'test-printer-01',
      );

      final testContainer = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(mockApi),
          appControllerProvider.overrideWith((ref) {
            return AppController(ref, log, config);
          }),
        ],
      );
      addTearDown(testContainer.dispose);

      final testStore = testContainer.read(queueStoreProvider);
      await testStore.init();

      final controller = testContainer.read(appControllerProvider.notifier);

      final job = PrintJob(
        printEventId: 3,
        deviceId: '123',
        orderId: 300,
        sessionId: 1,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {'test': 'data'},
        status: PrintJobStatus.printed_awaiting_ack,
        retryCount: 0,
        lastError: 'ACK pending retry',
        createdAt: DateTime.now(),
        printedAt: DateTime.now(),
        ackAttempts: 0,
        lastAckAttempt: DateTime.now(), // Just attempted
      );

      await testStore.insert(job);

      // Act: Immediate flush (should skip due to backoff)
      await controller.flushPendingAcks();

      // Assert: Attempt count unchanged (backoff prevented retry)
      final updatedJob = await testStore.get(3);
      expect(updatedJob!.ackAttempts, equals(0), reason: 'Backoff should prevent premature retry');
    });
  });
}
