import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/queue_store.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';

void main() {
  late ProviderContainer container;
  late AppController controller;
  late QueueStore store;

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

    final config = DeviceConfig(
      apiBaseUrl: 'http://test.local',
      wsUrl: 'ws://test.local',
      deviceId: '123', // Test device ID
      authToken: 'test-token',
      printerName: 'Test Printer',
      printerAddress: '00:11:22:33:44:55',
      printerId: 'test-printer-01',
    );

    // Riverpod 2.x: create container with override
    container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith((ref) {
          return AppController(ref, ref.read(loggerProvider), config);
        }),
      ],
    );
    addTearDown(container.dispose);

    final log = container.read(loggerProvider);
    await log.init();

    store = container.read(queueStoreProvider);
    await store.init();

    // Read the controller from container
    controller = container.read(appControllerProvider.notifier);
  });

  tearDown(() async {
    await store.clear();
  });

  group('C5: device_id Filtering Tests', () {
    test('enqueues event when device_id matches local config', () async {
      // Arrange: Event with matching device_id
      final payload = {
        'print_event_id': 1,
        'order_id': 100,
        'device_id': '123', // ✅ Matches config
        'session_id': 1,
        'print_type': 'INITIAL',
        'payload': {'test': 'data'},
      };

      // Act
      await controller.enqueueFromPayload(payload);

      // Assert
      final jobs = await store.all();
      expect(jobs.length, equals(1), reason: 'Should enqueue matching device_id event');
      expect(jobs.first.printEventId, equals(1));
      expect(jobs.first.deviceId, equals('123'));
    });

    test('ignores event when device_id does not match', () async {
      // Arrange: Event with different device_id
      final payload = {
        'print_event_id': 2,
        'order_id': 200,
        'device_id': '456', // ❌ Different device
        'session_id': 1,
        'print_type': 'INITIAL',
        'payload': {'test': 'data'},
      };

      // Act
      await controller.enqueueFromPayload(payload);

      // Assert
      final jobs = await store.all();
      expect(jobs.length, equals(0), reason: 'Should ignore non-matching device_id');
    });

    test('ignores event when device_id is missing', () async {
      // Arrange: Event without device_id
      final payload = {
        'print_event_id': 3,
        'order_id': 300,
        // device_id missing
        'session_id': 1,
        'print_type': 'INITIAL',
        'payload': {'test': 'data'},
      };

      // Act
      await controller.enqueueFromPayload(payload);

      // Assert
      final jobs = await store.all();
      expect(jobs.length, equals(0), reason: 'Should ignore missing device_id');
    });

    test('ignores event when device_id is empty string', () async {
      // Arrange: Event with empty device_id
      final payload = {
        'print_event_id': 4,
        'order_id': 400,
        'device_id': '', // Empty
        'session_id': 1,
        'print_type': 'INITIAL',
        'payload': {'test': 'data'},
      };

      // Act
      await controller.enqueueFromPayload(payload);

      // Assert
      final jobs = await store.all();
      expect(jobs.length, equals(0), reason: 'Should ignore empty device_id');
    });

    test('handles numeric device_id correctly', () async {
      // Arrange: Controller with numeric device_id
      final numericConfig = DeviceConfig(
        apiBaseUrl: 'http://test.local',
        wsUrl: 'ws://test.local',
        deviceId: '999',
        authToken: 'test-token',
        printerName: 'Test Printer',
        printerAddress: '00:11:22:33:44:55',
        printerId: 'test-printer-01',
      );

      // Riverpod 2.x: Create a temporary container with numeric config override
      final numericContainer = ProviderContainer(
        overrides: [
          appControllerProvider.overrideWith((ref) {
            return AppController(ref, ref.read(loggerProvider), numericConfig);
          }),
        ],
      );
      addTearDown(numericContainer.dispose);

      final numericController = numericContainer.read(appControllerProvider.notifier);
      
      // Initialize the numeric store
      final numericStore = numericContainer.read(queueStoreProvider);
      await numericStore.init();

      final payload = {
        'print_event_id': 5,
        'order_id': 500,
        'device_id': 999, // Numeric
        'session_id': 1,
        'print_type': 'INITIAL',
        'payload': {'test': 'data'},
      };

      // Act
      await numericController.enqueueFromPayload(payload);

      // Assert
      final jobs = await numericStore.all();
      expect(jobs.length, equals(1), reason: 'Should handle numeric device_id');
      expect(jobs.first.deviceId, equals('999'));
    });
  });
}
