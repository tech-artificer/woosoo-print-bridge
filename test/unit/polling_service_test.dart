import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/services/api_service.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/polling_service.dart';

class _CapturingApiService extends ApiService {
  final List<DateTime?> sinceValues = [];
  final List<int?> sessionIds = [];

  _CapturingApiService(super.log);

  @override
  Future<List<Map<String, dynamic>>> getUnprintedPrintEvents(
    DeviceConfig cfg, {
    required String token,
    int? sessionId,
    DateTime? since,
    int limit = 50,
  }) async {
    sessionIds.add(sessionId);
    sinceValues.add(since);
    return const [];
  }
}

void main() {
  const config = DeviceConfig(
    apiBaseUrl: 'https://192.168.100.7',
    wsUrl: 'wss://192.168.100.7/app/key',
    deviceId: '7',
    authToken: 'device-token',
    printerName: null,
    printerAddress: null,
    printerId: 'kitchen-printer-01',
  );

  test('branch-wide polling ignores legacy session-scoped watermark', () async {
    SharedPreferences.setMockInitialValues({
      'polling_watermark': '2026-04-29T01:00:00.000Z',
    });

    final api = _CapturingApiService(LoggerService());
    final polling = PollingService(
      log: LoggerService(),
      api: api,
      onEvents: (_) async {},
    );

    await polling.start(
      config,
      sessionId: null,
      interval: const Duration(hours: 1),
    );
    await polling.forceTick(config);
    polling.stop();

    expect(api.sessionIds, isNotEmpty);
    expect(api.sessionIds.every((id) => id == null), isTrue);
    expect(api.sinceValues.every((since) => since == null), isTrue);
  });
}
