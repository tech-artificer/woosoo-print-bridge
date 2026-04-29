import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_config.dart';
import 'api_service.dart';
import 'logger_service.dart';

typedef PollResultHandler = Future<void> Function(
    List<Map<String, dynamic>> events);

class PollingService {
  final LoggerService log;
  final ApiService api;
  final PollResultHandler onEvents;
  // Called with '' on a successful poll tick, non-empty error string on failure.
  final void Function(String)? onPollError;

  Timer? _timer;
  DateTime? _since;
  int? _sessionId;
  String _watermarkKey = 'polling_watermark';

  PollingService(
      {required this.log,
      required this.api,
      required this.onEvents,
      this.onPollError});

  String _watermarkKeyFor(int? sessionId) =>
      sessionId == null ? 'polling_watermark:branch' : 'polling_watermark';

  Future<DateTime?> _loadWatermark() async {
    final sp = await SharedPreferences.getInstance();
    final iso = sp.getString(_watermarkKey);
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
    await sp.setString(_watermarkKey, dt.toUtc().toIso8601String());
  }

  Future<void> start(DeviceConfig cfg,
      {int? sessionId, Duration interval = const Duration(seconds: 30)}) async {
    _sessionId = sessionId;
    _watermarkKey = _watermarkKeyFor(sessionId);
    _timer?.cancel();

    // Task 2.8: Stale watermark guard — clear watermark if offline > 1 hour.
    // This ensures events missed during extended downtime are re-fetched.
    final sp = await SharedPreferences.getInstance();
    final lastPollRaw = sp.getString('last_poll_time');
    if (lastPollRaw != null) {
      try {
        final elapsed = DateTime.now().difference(DateTime.parse(lastPollRaw));
        if (elapsed > const Duration(hours: 1)) {
          log.w(
              'Polling watermark stale — offline ${elapsed.inMinutes}m. Clearing to fetch all unprinted events.');
          await sp.remove(_watermarkKey);
          await sp.remove('last_poll_time');
        }
      } catch (e) {
        log.w(
            'Could not parse last_poll_time: $lastPollRaw — clearing watermark as precaution.');
        await sp.remove(_watermarkKey);
        await sp.remove('last_poll_time');
      }
    }

    _timer = Timer.periodic(interval, (_) => _tick(cfg));
    _since = await _loadWatermark();
    log.i('Polling watermark loaded: $_since');
    _tick(cfg);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> forceTick(DeviceConfig cfg) async {
    log.i('Force poll triggered');
    await _tick(cfg);
  }

  Future<void> _tick(DeviceConfig cfg) async {
    try {
      final list = await api.getUnprintedPrintEvents(cfg,
          token: cfg.authToken ?? '',
          sessionId: _sessionId,
          since: _since,
          limit: 50);
      if (list.isNotEmpty) {
        await onEvents(list);

        // Filter events with valid created_at timestamps to prevent crash on null
        final validTimestamps = list
            .where((e) => e['created_at'] != null && e['created_at'] is String)
            .map((e) => DateTime.parse(e['created_at'] as String))
            .toList();

        // Only update watermark if we have valid timestamps
        if (validTimestamps.isNotEmpty) {
          final maxCreatedAt =
              validTimestamps.reduce((a, b) => a.isAfter(b) ? a : b);
          _since = maxCreatedAt;
          await _saveWatermark(maxCreatedAt);
        }
        // If all events have null created_at, keep previous _since to prevent re-fetch loop
      }
      // Task 2.8: Record last successful poll time for stale watermark detection.
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          'last_poll_time', DateTime.now().toUtc().toIso8601String());
      // Keep _since unchanged if events.isEmpty
      onPollError?.call(''); // clear any previous error on success
    } catch (e, st) {
      log.e('Polling tick failed', e, st);
      onPollError?.call(e.toString());
    }
  }
}
