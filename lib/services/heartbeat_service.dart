import 'dart:async';
import '../models/device_config.dart';
import 'api_service.dart';
import 'logger_service.dart';

typedef HeartbeatPayloadBuilder = Map<String, dynamic> Function();

class HeartbeatService {
  final LoggerService log;
  final ApiService api;
  final HeartbeatPayloadBuilder buildPayload;

  Timer? _timer;

  HeartbeatService({required this.log, required this.api, required this.buildPayload});

  void start(DeviceConfig cfg, {Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      try { await api.sendHeartbeat(cfg, payload: buildPayload()); }
      catch (e, st) { log.e('Heartbeat failed', e, st); }
    });
  }

  void stop() { _timer?.cancel(); _timer = null; }
}
