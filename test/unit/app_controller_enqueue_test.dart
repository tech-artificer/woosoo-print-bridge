import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/queue_store.dart';
import 'package:woosoo_relay_device/state/app_controller.dart';

void main() {
  late QueueStore store;
  late ProviderContainer container;

  setUp(() async {
    store = QueueStore();
    store.initForTesting(await databaseFactoryMemory.openDatabase('queue.db'));
    container = ProviderContainer(
      overrides: [
        queueStoreProvider.overrideWithValue(store),
      ],
    );
  });

  tearDown(() async {
    await store.close();
  });

  test('requeues duplicate failed print event returned by server polling',
      () async {
    final createdAt = DateTime.utc(2026, 4, 29, 1, 0);
    await store.upsert(PrintJob(
      printEventId: 3,
      deviceId: 'tablet-01',
      orderId: 70,
      sessionId: null,
      printType: 'INITIAL',
      refillNumber: null,
      payload: const {
        'print_event_id': 3,
        'order_id': 70,
        'device_id': 'tablet-01',
      },
      status: PrintJobStatus.failed,
      retryCount: 5,
      lastError: 'Printer reconnect max attempts exceeded',
      createdAt: createdAt,
      printedAt: null,
      ackAttempts: 0,
      lastAckAttempt: null,
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

    final job = await store.get(3);

    expect(job, isNotNull);
    expect(job!.status, PrintJobStatus.pending);
    expect(job.retryCount, 0);
    expect(job.printerReconnectAttempts, 0);
    expect(job.lastError, isNull);
    expect(job.payload['items'], isNotEmpty);
  });
}
