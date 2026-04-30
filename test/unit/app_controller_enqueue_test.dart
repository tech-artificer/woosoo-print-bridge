import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/api_service.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/printer/printer_service.dart';
import 'package:woosoo_relay_device/services/queue_store.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';

class _FakePrinter implements PrinterService {
  bool connected = true;
  final List<List<String>> printedBatches = [];

  @override
  Future<List<Map<String, String>>> bondedDevices() async => const [];

  @override
  Future<bool> connectByAddress(String address) async {
    connected = true;
    return true;
  }

  @override
  Future<void> cut() async {}

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<bool> printLines(List<String> lines) async {
    printedBatches.add(lines);
    return true;
  }

  @override
  Future<bool> testPrint() async => true;
}

class _AckingApiService extends ApiService {
  _AckingApiService() : super(LoggerService());

  final printedEventIds = <int>[];

  @override
  Future<bool> markPrintEventPrinted(
    DeviceConfig cfg,
    int printEventId, {
    required String token,
    required DateTime printedAt,
    required String printerId,
    String? printerName,
    String? bluetoothAddress,
    String? appVersion,
  }) async {
    printedEventIds.add(printEventId);
    return true;
  }
}

PrintJob _job(int id, PrintJobStatus status) => PrintJob(
      printEventId: id,
      deviceId: 'tablet-01',
      orderId: 70,
      sessionId: null,
      printType: 'INITIAL',
      refillNumber: null,
      payload: {
        'print_event_id': id,
        'order_id': 7000 + id,
        'device_id': 'tablet-01',
      },
      status: status,
      retryCount: status == PrintJobStatus.failed ? 5 : 0,
      lastError:
          status == PrintJobStatus.failed ? 'Previous print failure' : null,
      createdAt: DateTime.utc(2026, 4, 29, 1, 0),
      printedAt: null,
      ackAttempts: 0,
      lastAckAttempt: null,
      printerReconnectAttempts: status == PrintJobStatus.failed ? 5 : 0,
    );

void main() {
  late QueueStore store;
  late _FakePrinter printer;
  late _AckingApiService api;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = QueueStore();
    store.initForTesting(await databaseFactoryMemory
        .openDatabase('queue_${DateTime.now().microsecondsSinceEpoch}.db'));
    printer = _FakePrinter();
    api = _AckingApiService();
    container = ProviderContainer(
      overrides: [
        queueStoreProvider.overrideWithValue(store),
        printerServiceProvider.overrideWithValue(printer),
        apiProvider.overrideWithValue(api),
      ],
    );
  });

  tearDown(() async {
    await store.close();
  });

  test('requeued duplicate failed print event resets retry state and prints',
      () async {
    await store.upsert(_job(3, PrintJobStatus.failed).copyWith(
      printerReconnectAttempts: 5,
    ));

    final controller = container.read(appControllerProvider.notifier);

    await controller.enqueueFromPayload({
      'print_event_id': 3,
      'order_id': 70,
      'device_id': 'tablet-01',
      'print_type': 'INITIAL',
      'created_at': '2026-04-29T01:12:00Z',
      'items': [
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final job = await store.get(3);
    expect(job, isNotNull);
    expect(job!.status, PrintJobStatus.success);
    expect(job.retryCount, 0);
    expect(job.printerReconnectAttempts, 0);
    expect(job.lastError, isNull);
    expect(job.payload['items'], isNotEmpty);
    expect(printer.printedBatches, hasLength(1));
  });

  test('prints a new enqueued job immediately when printer is connected',
      () async {
    final controller = container.read(appControllerProvider.notifier);

    await controller.enqueueFromPayload({
      'print_event_id': 10,
      'order_id': 7010,
      'device_id': 'tablet-01',
      'print_type': 'INITIAL',
      'tablename': 'A1',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 2},
      ],
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final job = await store.get(10);
    expect(printer.printedBatches, hasLength(1));
    expect(printer.printedBatches.single, contains('2 Pork Belly'));
    expect(api.printedEventIds, [10]);
    expect(job?.status, PrintJobStatus.success);
  });

  test('prints a requeued failed duplicate immediately', () async {
    await store.upsert(_job(11, PrintJobStatus.failed).copyWith(
      printerReconnectAttempts: 5,
    ));
    final controller = container.read(appControllerProvider.notifier);

    await controller.enqueueFromPayload({
      'print_event_id': 11,
      'order_id': 7011,
      'device_id': 'tablet-01',
      'print_type': 'INITIAL',
      'tablename': 'A2',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Beef Brisket', 'quantity': 1},
      ],
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final job = await store.get(11);
    expect(printer.printedBatches, hasLength(1));
    expect(printer.printedBatches.single, contains('1 Beef Brisket'));
    expect(api.printedEventIds, [11]);
    expect(job?.status, PrintJobStatus.success);
  });

  test('does not print duplicate pending events', () async {
    await store.upsert(_job(12, PrintJobStatus.pending));
    final controller = container.read(appControllerProvider.notifier);

    await controller.enqueueFromPayload({
      'print_event_id': 12,
      'order_id': 7012,
      'device_id': 'tablet-01',
      'print_type': 'INITIAL',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Chicken Thigh', 'quantity': 1},
      ],
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(printer.printedBatches, isEmpty);
    expect(api.printedEventIds, isEmpty);
  });

  test('records queue paused skip reason', () async {
    final controller = container.read(appControllerProvider.notifier);
    controller.pauseQueueForPrinterAttention('Paper out');

    await controller.processQueueOnce();

    expect(container.read(appControllerProvider).lastQueueSkipReason,
        'queue_paused');
  });

  test('records no pending job skip reason', () async {
    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    expect(container.read(appControllerProvider).lastQueueSkipReason,
        'no_pending_job');
  });
}
