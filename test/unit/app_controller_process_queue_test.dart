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

PrintJob _job(int id, Map<String, dynamic> payload) => PrintJob(
      printEventId: id,
      deviceId: 'tablet-1',
      orderId: 1000 + id,
      sessionId: null,
      printType: (payload['print_type'] ?? 'INITIAL').toString(),
      refillNumber: null,
      payload: payload,
      status: PrintJobStatus.pending,
      retryCount: 0,
      lastError: null,
      createdAt: DateTime.utc(2026, 4, 29, 1, 0, id),
      printedAt: null,
      ackAttempts: 0,
      lastAckAttempt: null,
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

  test('processes a pending print job when the printer is connected', () async {
    await store.upsert(_job(1, {
      'print_event_id': 1,
      'order_id': 1001,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A1',
      'order_number': 'ORD-1001',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 2},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(1);
    expect(printer.printedBatches, hasLength(1));
    expect(printer.printedBatches.single, contains('2 Pork Belly'));
    expect(job?.status, PrintJobStatus.success);
  });

  test('does not leave a job stuck as printing when receipt building fails',
      () async {
    await store.upsert(_job(2, {
      'print_event_id': 2,
      'order_id': 1002,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'items': ['not-a-map'],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(2);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.retryCount, 1);
    expect(job?.lastError, contains('Receipt build failed'));
  });

  test('recovers a stale printing job on the next queue tick', () async {
    await store.upsert(_job(3, {
      'print_event_id': 3,
      'order_id': 1003,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A3',
      'order_number': 'ORD-1003',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Beef Brisket', 'quantity': 1},
      ],
    }).copyWith(
      status: PrintJobStatus.printing,
    ));

    final raw = await store.get(3);
    await store.upsert(PrintJob(
      printEventId: raw!.printEventId,
      deviceId: raw.deviceId,
      orderId: raw.orderId,
      sessionId: raw.sessionId,
      printType: raw.printType,
      refillNumber: raw.refillNumber,
      payload: raw.payload,
      status: raw.status,
      retryCount: raw.retryCount,
      lastError: raw.lastError,
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
      printedAt: raw.printedAt,
      ackAttempts: raw.ackAttempts,
      lastAckAttempt: raw.lastAckAttempt,
      printerReconnectAttempts: raw.printerReconnectAttempts,
      lastPrinterReconnectAttempt: raw.lastPrinterReconnectAttempt,
    ));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(3);
    expect(printer.printedBatches, hasLength(1));
    expect(job?.status, PrintJobStatus.success);
  });

  test('force prints a selected queued job immediately and ACKs it', () async {
    await store.upsert(_job(4, {
      'print_event_id': 4,
      'order_id': 1004,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A4',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Chicken Thigh', 'quantity': 3},
      ],
    }).copyWith(status: PrintJobStatus.failed));

    final controller = container.read(appControllerProvider.notifier);

    await controller.forcePrintJob(4);

    final job = await store.get(4);
    expect(printer.printedBatches, hasLength(1));
    expect(printer.printedBatches.single, contains('3 Chicken Thigh'));
    expect(api.printedEventIds, [4]);
    expect(job?.status, PrintJobStatus.success);
  });

  test('reprints an already printed order without sending an ACK', () async {
    final printedAt = DateTime.utc(2026, 4, 29, 1, 30);
    await store.upsert(_job(5, {
      'print_event_id': 5,
      'order_id': 1005,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A5',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Jowl', 'quantity': 2},
      ],
    }).copyWith(status: PrintJobStatus.success, printedAt: printedAt));

    final controller = container.read(appControllerProvider.notifier);
    final original = await store.get(5);

    await controller.reprintOrder(original!);

    final job = await store.get(5);
    expect(printer.printedBatches, hasLength(1));
    expect(printer.printedBatches.single, contains('2 Pork Jowl'));
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.success);
    expect(job?.printedAt, printedAt);
  });
}
