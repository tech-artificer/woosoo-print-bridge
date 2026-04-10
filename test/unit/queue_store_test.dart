import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:woosoo_relay_device/models/print_job.dart';
import 'package:woosoo_relay_device/services/queue_store.dart';

PrintJob _makeJob(int id, {PrintJobStatus status = PrintJobStatus.pending, int retryCount = 0}) =>
    PrintJob(
      printEventId: id,
      deviceId: 'device-001',
      orderId: 100 + id,
      sessionId: 1,
      printType: 'INITIAL',
      refillNumber: null,
      payload: {'order_number': '#$id'},
      status: status,
      retryCount: retryCount,
      lastError: null,
      createdAt: DateTime.utc(2026, 4, 8, 12, 0, id),
      printedAt: null,
    );

void main() {
  late QueueStore store;

  setUp(() async {
    final db = await databaseFactoryMemory.openDatabase('test_${ DateTime.now().microsecondsSinceEpoch}.db');
    store = QueueStore();
    store.initForTesting(db);
  });

  group('QueueStore — insert and read', () {
    test('insert adds item to store', () async {
      final job = _makeJob(1);
      await store.insert(job);
      final all = await store.all();
      expect(all.length, 1);
      expect(all.first.printEventId, 1);
    });

    test('exists returns true for inserted job', () async {
      await store.insert(_makeJob(5));
      expect(await store.exists(5), isTrue);
    });

    test('exists returns false for unknown id', () async {
      expect(await store.exists(999), isFalse);
    });

    test('get returns null for missing id', () async {
      expect(await store.get(42), isNull);
    });

    test('all returns jobs sorted by createdAt ascending', () async {
      await store.insert(_makeJob(3));
      await store.insert(_makeJob(1));
      await store.insert(_makeJob(2));
      final all = await store.all();
      expect(all.map((j) => j.printEventId).toList(), [1, 2, 3]);
    });
  });

  group('QueueStore — updates via updateJob', () {
    test('updateJob changes status to printing', () async {
      await store.insert(_makeJob(10));
      await store.updateJob(10, (old) => old.copyWith(status: PrintJobStatus.printing));
      final updated = await store.get(10);
      expect(updated?.status, PrintJobStatus.printing);
    });

    test('updateJob increments retryCount correctly', () async {
      await store.insert(_makeJob(11, retryCount: 2));
      await store.updateJob(11, (old) => old.copyWith(retryCount: old.retryCount + 1));
      final updated = await store.get(11);
      expect(updated?.retryCount, 3);
    });

    test('updateJob persists lastError string', () async {
      await store.insert(_makeJob(12));
      await store.updateJob(12, (old) => old.copyWith(lastError: 'Bluetooth timeout'));
      final updated = await store.get(12);
      expect(updated?.lastError, 'Bluetooth timeout');
    });

    test('updateJob on non-existent id is a no-op', () async {
      // Should complete without throwing
      await expectLater(
        store.updateJob(999, (old) => old.copyWith(status: PrintJobStatus.printing)),
        completes,
      );
      expect(await store.get(999), isNull);
    });
  });

  group('QueueStore — status transitions', () {
    test('pending → printing → printed_awaiting_ack → success lifecycle', () async {
      await store.insert(_makeJob(20, status: PrintJobStatus.pending));

      await store.updateJob(20, (j) => j.copyWith(status: PrintJobStatus.printing));
      expect((await store.get(20))?.status, PrintJobStatus.printing);

      await store.updateJob(
        20,
        (j) => j.copyWith(
          status: PrintJobStatus.printed_awaiting_ack,
          printedAt: DateTime.utc(2026, 4, 8, 12, 1),
        ),
      );
      expect((await store.get(20))?.status, PrintJobStatus.printed_awaiting_ack);
      expect((await store.get(20))?.printedAt, isNotNull);

      await store.updateJob(20, (j) => j.copyWith(status: PrintJobStatus.success));
      expect((await store.get(20))?.status, PrintJobStatus.success);
    });

    test('pending → failed after exceeding retryCount', () async {
      await store.insert(_makeJob(21, retryCount: 4));
      await store.updateJob(
        21,
        (j) => j.copyWith(status: PrintJobStatus.failed, retryCount: j.retryCount + 1, lastError: 'Max retries'),
      );
      final job = await store.get(21);
      expect(job?.status, PrintJobStatus.failed);
      expect(job?.retryCount, 5);
    });
  });

  group('QueueStore — dead letter', () {
    test('moveToDeadLetter places job in dead letter store', () async {
      final job = _makeJob(30, status: PrintJobStatus.failed);
      await store.insert(job);
      await store.moveToDeadLetter(job, reason: 'Max retries exceeded');
      final dead = await store.getDeadLetter(30);
      expect(dead, isNotNull);
      expect(dead?['dead_letter_reason'], 'Max retries exceeded');
    });

    test('moveToDeadLetter preserves printEventId', () async {
      final job = _makeJob(31, status: PrintJobStatus.failed);
      await store.insert(job);
      await store.moveToDeadLetter(job, reason: 'Printer offline');
      final dead = await store.getDeadLetter(31);
      expect(dead?['printEventId'], 31);
    });

    test('allDeadLetters returns most recent first', () async {
      final job1 = _makeJob(40, status: PrintJobStatus.failed);
      final job2 = _makeJob(41, status: PrintJobStatus.failed);
      await store.insert(job1);
      await store.insert(job2);
      await store.moveToDeadLetter(job1, reason: 'r1', failedAt: DateTime.utc(2026, 4, 8, 10));
      await store.moveToDeadLetter(job2, reason: 'r2', failedAt: DateTime.utc(2026, 4, 8, 11));
      final all = await store.allDeadLetters();
      // Most recent first
      expect(all.first['printEventId'], 41);
    });

    test('removeDeadLetter purges the entry', () async {
      final job = _makeJob(50, status: PrintJobStatus.failed);
      await store.insert(job);
      await store.moveToDeadLetter(job, reason: 'test purge');
      await store.removeDeadLetter(50);
      expect(await store.getDeadLetter(50), isNull);
    });

    test('getDeadLetter returns null for unknown id', () async {
      expect(await store.getDeadLetter(999), isNull);
    });
  });

  group('QueueStore — upsert', () {
    test('upsert creates a new record when it does not exist', () async {
      final job = _makeJob(60);
      await store.upsert(job);
      expect(await store.exists(60), isTrue);
    });

    test('upsert updates status on existing record', () async {
      await store.insert(_makeJob(61, status: PrintJobStatus.pending));
      await store.upsert(_makeJob(61, status: PrintJobStatus.printing));
      final updated = await store.get(61);
      expect(updated?.status, PrintJobStatus.printing);
    });
  });

  group('QueueStore — clear', () {
    test('clear removes all jobs from the main store', () async {
      await store.insert(_makeJob(70));
      await store.insert(_makeJob(71));
      await store.clear();
      expect((await store.all()).isEmpty, isTrue);
    });

    test('clear does not remove dead letter entries', () async {
      final job = _makeJob(72, status: PrintJobStatus.failed);
      await store.insert(job);
      await store.moveToDeadLetter(job, reason: 'survived clear');
      await store.clear();
      expect(await store.getDeadLetter(72), isNotNull);
    });
  });
}
