import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../models/print_job.dart';

class QueueStore {
  static const _dbName = 'print_queue.db';
  static const _storeName = 'print_jobs';

  late Database _db;
  final StoreRef<int, Map<String, dynamic>> _store =
      intMapStoreFactory.store(_storeName);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
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

  Future<void> clear() async => _store.delete(_db);
}
