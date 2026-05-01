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
  bool connectSucceeds = true;
  bool throwOnConnect = false;
  bool disconnectAfterPrint = false;
  bool printSucceeds = true;
  PrinterHealthResult health = PrinterHealthResult.ready(
    checkedAt: DateTime.utc(2026, 4, 29),
    rawStatus: const [18, 18, 18],
  );
  final List<List<String>> printedBatches = [];

  @override
  Future<List<Map<String, String>>> bondedDevices() async => const [];

  @override
  Future<bool> connectByAddress(String address) async {
    if (throwOnConnect) {
      throw StateError('simulated connect error');
    }
    connected = connectSucceeds;
    return connectSucceeds;
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
  Stream<PrinterConnectionStatus> watchConnectionStatus() =>
      const Stream.empty();

  @override
  Future<PrinterHealthResult> checkHealth({
    Duration timeout = const Duration(seconds: 2),
  }) async =>
      connected ? health : PrinterHealthResult.disconnected();

  @override
  Future<bool> printLines(List<String> lines) async {
    if (!printSucceeds) return false;
    printedBatches.add(lines);
    if (disconnectAfterPrint) connected = false;
    return true;
  }

  @override
  Future<bool> testPrint() async => true;
}

class _AckingApiService extends ApiService {
  _AckingApiService() : super(LoggerService());

  final printedEventIds = <int>[];
  final verificationModes = <String?>[];

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
    String? verificationMode,
  }) async {
    printedEventIds.add(printEventId);
    verificationModes.add(verificationMode);
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

  test('does not ACK when printer disconnects during automatic print',
      () async {
    printer.disconnectAfterPrint = true;
    await store.upsert(_job(6, {
      'print_event_id': 6,
      'order_id': 1006,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A6',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Short Rib', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(6);
    expect(printer.printedBatches, hasLength(1));
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.lastError, contains('Printer disconnected'));
  });

  test('ACK retry includes the configured verification mode', () async {
    final printedAt = DateTime.utc(2026, 4, 29, 1, 30);
    await store.upsert(_job(17, {
      'print_event_id': 17,
      'order_id': 1017,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A17',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }).copyWith(
      status: PrintJobStatus.printedAwaitingAck,
      printedAt: printedAt,
      ackAttempts: 1,
      lastAckAttempt: DateTime.now().toUtc().subtract(const Duration(seconds: 3)),
    ));

    final controller = container.read(appControllerProvider.notifier);

    await controller.flushPendingAcks();

    expect(api.printedEventIds, [17]);
    expect(api.verificationModes, ['connected_only']);
  });

  test('does not ACK when printer status is unsupported', () async {
    final controller = container.read(appControllerProvider.notifier);
    await controller.setStrictStatusRequired(true);

    printer.health = PrinterHealthResult.unsupported(
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'No DLE EOT response from printer',
    );
    await store.upsert(_job(8, {
      'print_event_id': 8,
      'order_id': 1008,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A8',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    }));

    await controller.processQueueOnce();

    final job = await store.get(8);
    final state = container.read(appControllerProvider);
    expect(printer.printedBatches, isEmpty);
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.lastError, contains('No DLE EOT response'));
    expect(state.queuePaused, isTrue);
    expect(state.lastQueueSkipReason, 'printer_status_unsupported');
  });

  test('compatible mode allows print when status is unsupported', () async {
    printer.health = PrinterHealthResult.unsupported(
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'No DLE EOT response from printer',
    );
    await store.upsert(_job(18, {
      'print_event_id': 18,
      'order_id': 1018,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A18',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(18);
    final state = container.read(appControllerProvider);
    expect(printer.printedBatches, hasLength(1));
    expect(api.printedEventIds, [18]);
    expect(job?.status, PrintJobStatus.success);
    expect(state.queuePaused, isFalse);
  });

  test('compatible mode blocks printing when printer is disconnected', () async {
    printer.connected = false;
    printer.connectSucceeds = false;
    final controller = container.read(appControllerProvider.notifier);
    await controller.updateConfig(
      container
          .read(appControllerProvider)
          .config
          .copyWith(printerAddress: '00:11:22:33:44:55'),
    );

    await store.upsert(_job(19, {
      'print_event_id': 19,
      'order_id': 1019,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A19',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }));

    await controller.processQueueOnce();

    final job = await store.get(19);
    expect(printer.printedBatches, isEmpty);
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
  });

  test('queue processing survives thrown printer connect exception', () async {
    printer.connected = false;
    printer.throwOnConnect = true;
    final controller = container.read(appControllerProvider.notifier);
    await controller.updateConfig(
      container
          .read(appControllerProvider)
          .config
          .copyWith(printerAddress: '00:11:22:33:44:55'),
    );

    await store.upsert(_job(190, {
      'print_event_id': 190,
      'order_id': 1190,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A190',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }));

    await controller.processQueueOnce();

    final state = container.read(appControllerProvider);
    final job = await store.get(190);
    expect(job?.status, PrintJobStatus.pending);
    expect(state.printer.error ?? '', contains('Connect failed'));
    expect(job?.lastError ?? '', contains('Printer reconnect failed'));
  });

  test('compatible mode with print command failure blocks ACK', () async {
    printer.printSucceeds = false;
    await store.upsert(_job(20, {
      'print_event_id': 20,
      'order_id': 1020,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A20',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(20);
    expect(printer.printedBatches, isEmpty);
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.lastError, contains('Print command failed'));
  });

  test('paused queue due to unsupported status resumes in compatible mode',
      () async {
    final controller = container.read(appControllerProvider.notifier);
    await controller.setStrictStatusRequired(true);

    printer.health = PrinterHealthResult.unsupported(
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'No DLE EOT response from printer',
    );
    await store.upsert(_job(21, {
      'print_event_id': 21,
      'order_id': 1021,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A21',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }));

    await controller.processQueueOnce();
    expect(container.read(appControllerProvider).queuePaused, isTrue);

    await controller.setStrictStatusRequired(false);
    await controller.resumeAndProcessPending();

    final job = await store.get(21);
    final state = container.read(appControllerProvider);
    expect(api.printedEventIds, [21]);
    expect(job?.status, PrintJobStatus.success);
    expect(state.queuePaused, isFalse);
  });

  test('resumeQueue uses compatible hard-block logic for unsupported status',
      () async {
    final controller = container.read(appControllerProvider.notifier);
    await controller.setStrictStatusRequired(true);

    printer.health = PrinterHealthResult.unsupported(
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'No DLE EOT response from printer',
    );

    controller.pauseQueueForPrinterAttention('status unsupported in strict mode');
    expect(container.read(appControllerProvider).queuePaused, isTrue);

    await controller.setStrictStatusRequired(false);
    await controller.resumeQueue();

    final state = container.read(appControllerProvider);
    expect(state.queuePaused, isFalse);
    expect(state.queuePauseReason, isNull);
    expect(state.lastQueueSkipReason, isNull);
  });

  test('initial and refill jobs both follow compatible unsupported behavior',
      () async {
    printer.health = PrinterHealthResult.unsupported(
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'No DLE EOT response from printer',
    );

    await store.upsert(_job(22, {
      'print_event_id': 22,
      'order_id': 1022,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A22',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
      ],
    }));
    await store.upsert(_job(23, {
      'print_event_id': 23,
      'order_id': 1023,
      'device_id': 'tablet-1',
      'print_type': 'REFILL',
      'refill_number': 2,
      'tablename': 'A23',
      'items': [
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();
    await controller.processQueueOnce();

    final jobInitial = await store.get(22);
    final jobRefill = await store.get(23);
    expect(api.printedEventIds, containsAll([22, 23]));
    expect(jobInitial?.status, PrintJobStatus.success);
    expect(jobRefill?.status, PrintJobStatus.success);
  });

  test('auto-resumes paused queue and prints pending job when health is ready',
      () async {
    await store.upsert(_job(10, {
      'print_event_id': 10,
      'order_id': 1010,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A10',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);
    controller.pauseQueueForPrinterAttention('Paused due to prior health check');

    await controller.processQueueOnce();

    final job = await store.get(10);
    final state = container.read(appControllerProvider);
    expect(printer.printedBatches, hasLength(1));
    expect(api.printedEventIds, [10]);
    expect(job?.status, PrintJobStatus.success);
    expect(state.queuePaused, isFalse);
    expect(state.queuePauseReason, isNull);
  });

  test('does not ACK when paper is out', () async {
    printer.health = PrinterHealthResult(
      connected: true,
      statusSupported: true,
      paperOk: false,
      coverClosed: true,
      offline: false,
      rawStatus: const [18, 18, 96],
      checkedAt: DateTime.utc(2026, 4, 29),
      message: 'Printer paper is out.',
    );
    await store.upsert(_job(9, {
      'print_event_id': 9,
      'order_id': 1009,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A9',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Short Rib', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await controller.processQueueOnce();

    final job = await store.get(9);
    final state = container.read(appControllerProvider);
    expect(printer.printedBatches, isEmpty);
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.lastError, contains('paper'));
    expect(state.queuePaused, isTrue);
    expect(state.lastQueueSkipReason, 'printer_paper_out');
  });

  test('does not ACK when printer disconnects during manual print', () async {
    printer.disconnectAfterPrint = true;
    await store.upsert(_job(7, {
      'print_event_id': 7,
      'order_id': 1007,
      'device_id': 'tablet-1',
      'print_type': 'INITIAL',
      'tablename': 'A7',
      'items': [
        {'name': 'Dinner Set', 'quantity': 1},
        {'name': 'Pork Belly', 'quantity': 1},
      ],
    }));

    final controller = container.read(appControllerProvider.notifier);

    await expectLater(controller.forcePrintJob(7), throwsStateError);

    final job = await store.get(7);
    expect(printer.printedBatches, hasLength(1));
    expect(api.printedEventIds, isEmpty);
    expect(job?.status, PrintJobStatus.pending);
    expect(job?.lastError, contains('Printer disconnected'));
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
