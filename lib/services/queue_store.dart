import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../models/print_job.dart';

class QueueStore {
  static const _dbName = 'print_queue.db';
  static const _storeName = 'print_jobs';
  static const _deadLetterStoreName = 'print_jobs_dead_letter';

  late Database _db;
  final StoreRef<int, Map<String, dynamic>> _store =
      intMapStoreFactory.store(_storeName);
  final StoreRef<int, Map<String, dynamic>> _deadLetterStore =
      intMapStoreFactory.store(_deadLetterStoreName);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
  }

  /// For unit testing only — inject a pre-built in-memory database.
  void initForTesting(Database db) {
    _db = db;
  }

  Future<void> close() async {
    await _db.close();
  }

  Future<bool> exists(int printEventId) async {
    final v = await _store.record(printEventId).get(_db);
    return v != null;
  }

  Future<void> upsert(PrintJob job) async =>
      _store.record(job.printEventId).put(_db, job.toJson(), merge: true);

  Future<List<PrintJob>> all() async {
    final records = await _store.find(_db);
    final jobs = records
        .map((r) => PrintJob.fromJson(Map<String, dynamic>.from(r.value)))
        .toList();
    jobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  Future<void> updateJob(int id, PrintJob Function(PrintJob old) fn) async {
    final rec = _store.record(id);
    await _db.transaction((txn) async {
      final old = await rec.get(txn);
      if (old == null) return;
      final job = PrintJob.fromJson(Map<String, dynamic>.from(old));
      await rec.put(txn, fn(job).toJson(), merge: false);
    });
  }

  // H2: Atomic state persistence helpers
  Future<PrintJob?> get(int printEventId) async {
    final v = await _store.record(printEventId).get(_db);
    return v == null ? null : PrintJob.fromJson(Map<String, dynamic>.from(v));
  }

  Future<void> insert(PrintJob job) async {
    await _store.record(job.printEventId).put(_db, job.toJson());
  }

  Future<void> moveToDeadLetter(
    PrintJob job, {
    required String reason,
    DateTime? failedAt,
  }) async {
    final at = failedAt ?? DateTime.now().toUtc();
    final record = {
      ...job.toJson(),
      'dead_letter_reason': reason,
      'failed_at': at.toIso8601String(),
    };

    await _deadLetterStore
        .record(job.printEventId)
        .put(_db, record, merge: true);
  }

  Future<List<Map<String, dynamic>>> allDeadLetters() async {
    final records = await _deadLetterStore.find(_db);
    final rows =
        records.map((r) => Map<String, dynamic>.from(r.value)).toList();
    rows.sort((a, b) {
      final aAt = DateTime.tryParse((a['failed_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = DateTime.tryParse((b['failed_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return rows;
  }

  Future<Map<String, dynamic>?> getDeadLetter(int printEventId) async {
    final v = await _deadLetterStore.record(printEventId).get(_db);
    return v == null ? null : Map<String, dynamic>.from(v);
  }

  Future<void> removeDeadLetter(int printEventId) async {
    await _deadLetterStore.record(printEventId).delete(_db);
  }

  Future<void> clear() async => _store.delete(_db);
}
