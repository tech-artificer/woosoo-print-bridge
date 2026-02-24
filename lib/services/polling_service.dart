import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_config.dart';
import 'api_service.dart';
import 'logger_service.dart';

typedef PollResultHandler = Future<void> Function(List<Map<String, dynamic>> events);

class PollingService {
  final LoggerService log;
  final ApiService api;
  final PollResultHandler onEvents;

  Timer? _timer;
  DateTime? _since;
  int? _sessionId;

  PollingService({required this.log, required this.api, required this.onEvents});

  Future<DateTime?> _loadWatermark() async {
    final sp = await SharedPreferences.getInstance();
    final iso = sp.getString('polling_watermark');
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso);
    } catch (e) {
      log.w('Invalid watermark in storage: $iso');
      return null;
    }
  }

  Future<void> _saveWatermark(DateTime dt) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('polling_watermark', dt.toUtc().toIso8601String());
  }

  Future<void> start(DeviceConfig cfg, {required int sessionId, Duration interval = const Duration(seconds: 30)}) async {
    _sessionId = sessionId;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick(cfg));
    _since = await _loadWatermark();
    log.i('Polling watermark loaded: $_since');
    _tick(cfg);
  }

  void stop() { _timer?.cancel(); _timer = null; }

  Future<void> forceTick(DeviceConfig cfg) async {
    log.i('Force poll triggered');
    await _tick(cfg);
  }

  Future<void> _tick(DeviceConfig cfg) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final list = await api.getUnprintedPrintEvents(cfg, token: cfg.authToken ?? '', sessionId: sessionId, since: _since, limit: 50);
      if (list.isNotEmpty) {
        await onEvents(list);
        final maxCreatedAt = list
            .map((e) => DateTime.parse(e['created_at'] as String))
            .reduce((a, b) => a.isAfter(b) ? a : b);
        _since = maxCreatedAt;
        await _saveWatermark(maxCreatedAt);
      }
      // Keep _since unchanged if events.isEmpty
    } catch (e, st) {
      log.e('Polling tick failed', e, st);
    }
  }
}
