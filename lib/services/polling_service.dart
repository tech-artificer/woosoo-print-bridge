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
  // Called with '' on a successful poll tick, non-empty error string on failure.
  final void Function(String)? onPollError;

  Timer? _timer;
  DateTime? _since;
  int? _sessionId;

  PollingService({required this.log, required this.api, required this.onEvents, this.onPollError});

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

    // Task 2.8: Stale watermark guard — clear watermark if offline > 1 hour.
    // This ensures events missed during extended downtime are re-fetched.
    final sp = await SharedPreferences.getInstance();
    final lastPollRaw = sp.getString('last_poll_time');
    if (lastPollRaw != null) {
      try {
        final elapsed = DateTime.now().difference(DateTime.parse(lastPollRaw));
        if (elapsed > const Duration(hours: 1)) {
          log.w('Polling watermark stale — offline ${elapsed.inMinutes}m. Clearing to fetch all unprinted events.');
          await sp.remove('polling_watermark'); // correct key name (not 'poll_watermark')
          await sp.remove('last_poll_time');
        }
      } catch (e) {
        log.w('Could not parse last_poll_time: $lastPollRaw — clearing watermark as precaution.');
        await sp.remove('polling_watermark');
        await sp.remove('last_poll_time');
      }
    }

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
      // Task 2.8: Record last successful poll time for stale watermark detection.
      final sp = await SharedPreferences.getInstance();
      await sp.setString('last_poll_time', DateTime.now().toUtc().toIso8601String());
      // Keep _since unchanged if events.isEmpty
      onPollError?.call(''); // clear any previous error on success
    } catch (e, st) {
      log.e('Polling tick failed', e, st);
      onPollError?.call(e.toString());
    }
  }
}
