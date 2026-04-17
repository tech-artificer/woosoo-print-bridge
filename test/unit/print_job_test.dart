import 'package:flutter_test/flutter_test.dart';

import 'package:woosoo_relay_device/models/print_job.dart';

void main() {
  group('PrintJob — serialization round-trip', () {
    test('toJson / fromJson preserves all required fields', () {
      final original = PrintJob(
        printEventId: 7,
        deviceId: 'device-abc',
        orderId: 55,
        sessionId: 3,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {'order_number': '#007', 'items': []},
        status: PrintJobStatus.pending,
        retryCount: 0,
        lastError: null,
        createdAt: DateTime.utc(2026, 4, 8, 12, 0, 0),
        printedAt: null,
      );

      final json = original.toJson();
      final restored = PrintJob.fromJson(json);

      expect(restored.printEventId, original.printEventId);
      expect(restored.deviceId, original.deviceId);
      expect(restored.orderId, original.orderId);
      expect(restored.sessionId, original.sessionId);
      expect(restored.printType, original.printType);
      expect(restored.refillNumber, original.refillNumber);
      expect(restored.status, original.status);
      expect(restored.retryCount, original.retryCount);
      expect(restored.lastError, original.lastError);
      expect(restored.createdAt, original.createdAt);
      expect(restored.printedAt, original.printedAt);
    });

    test('toJson / fromJson preserves optional printedAt', () {
      final printed = PrintJob(
        printEventId: 8,
        deviceId: 'device-abc',
        orderId: 56,
        sessionId: 3,
        printType: 'REFILL',
        refillNumber: 2,
        payload: {},
        status: PrintJobStatus.printed_awaiting_ack,
        retryCount: 1,
        lastError: null,
        createdAt: DateTime.utc(2026, 4, 8, 12, 0, 0),
        printedAt: DateTime.utc(2026, 4, 8, 12, 1, 0),
      );

      final restored = PrintJob.fromJson(printed.toJson());
      expect(restored.printedAt, printed.printedAt);
      expect(restored.refillNumber, 2);
    });

    test('toJson / fromJson preserves lastError string', () {
      final failed = PrintJob(
        printEventId: 9,
        deviceId: 'device-abc',
        orderId: 57,
        sessionId: 3,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {},
        status: PrintJobStatus.failed,
        retryCount: 5,
        lastError: 'Bluetooth connection refused',
        createdAt: DateTime.utc(2026, 4, 8, 12, 0, 0),
        printedAt: null,
      );

      final restored = PrintJob.fromJson(failed.toJson());
      expect(restored.lastError, 'Bluetooth connection refused');
      expect(restored.retryCount, 5);
      expect(restored.status, PrintJobStatus.failed);
    });

    test('toJson / fromJson with null sessionId', () {
      final job = PrintJob(
        printEventId: 10,
        deviceId: 'device-abc',
        orderId: 58,
        sessionId: null,
        printType: 'INITIAL',
        refillNumber: null,
        payload: {},
        status: PrintJobStatus.pending,
        retryCount: 0,
        lastError: null,
        createdAt: DateTime.utc(2026, 4, 8, 12, 0, 0),
        printedAt: null,
      );

      final restored = PrintJob.fromJson(job.toJson());
      expect(restored.sessionId, isNull);
    });

    test('status enum round-trips for all values', () {
      for (final status in PrintJobStatus.values) {
        final job = PrintJob(
          printEventId: status.index,
          deviceId: 'dev',
          orderId: 1,
          sessionId: 1,
          printType: 'INITIAL',
          refillNumber: null,
          payload: {},
          status: status,
          retryCount: 0,
          lastError: null,
          createdAt: DateTime.utc(2026),
          printedAt: null,
        );
        final restored = PrintJob.fromJson(job.toJson());
        expect(restored.status, status, reason: 'Status $status did not survive round-trip');
      }
    });
  });

  group('PrintJob — copyWith', () {
    final base = PrintJob(
      printEventId: 1,
      deviceId: 'dev',
      orderId: 1,
      sessionId: 1,
      printType: 'INITIAL',
      refillNumber: null,
      payload: {},
      status: PrintJobStatus.pending,
      retryCount: 0,
      lastError: null,
      createdAt: DateTime.utc(2026, 4, 8),
      printedAt: null,
    );

    test('copyWith changes only the specified field', () {
      final updated = base.copyWith(status: PrintJobStatus.printing);
      expect(updated.status, PrintJobStatus.printing);
      expect(updated.retryCount, base.retryCount);
      expect(updated.printEventId, base.printEventId);
    });

    test('copyWith can set lastError to null explicitly', () {
      final withError = base.copyWith(lastError: 'some error');
      final cleared = withError.copyWith(lastError: null);
      expect(cleared.lastError, isNull);
    });

    test('copyWith increments retryCount correctly', () {
      final retried = base.copyWith(retryCount: base.retryCount + 1);
      expect(retried.retryCount, 1);
    });

    test('copyWith preserves immutability — original unchanged', () {
      base.copyWith(status: PrintJobStatus.failed);
      expect(base.status, PrintJobStatus.pending);
    });
  });
}
