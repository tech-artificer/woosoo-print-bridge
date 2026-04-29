import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:woosoo_relay_device/models/device_config.dart';
import 'package:woosoo_relay_device/services/api_service.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';

void main() {
  test('registerDevice sends setup code as security_code and accepts 200',
      () async {
    late Map<String, dynamic> requestBody;

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/devices/register');

      requestBody = jsonDecode(request.body) as Map<String, dynamic>;

      return http.Response(
        jsonEncode({
          'success': true,
          'token': 'device-token',
          'device': {'id': 7},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiService(LoggerService(), client: client);
    final response = await api.registerDevice(
      'https://192.168.100.7',
      code: '123456',
      appVersion: '1.0.0+1',
    );

    expect(response?['token'], 'device-token');
    expect(requestBody['security_code'], '123456');
    expect(requestBody['code'], isNull);
    expect(requestBody['name'], isNull);
    expect(requestBody['app_version'], '1.0.0+1');
  });

  test('getLatestSession sends device bearer token', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/devices/latest-session');
      expect(request.headers['Authorization'], 'Bearer device-token');

      return http.Response(
        jsonEncode({
          'session': {'id': 42},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiService(LoggerService(), client: client);
    final response = await api.getLatestSession(
      const DeviceConfig(
        apiBaseUrl: 'https://192.168.100.7',
        wsUrl: 'wss://192.168.100.7/app/key',
        deviceId: '7',
        authToken: 'device-token',
        printerName: null,
        printerAddress: null,
        printerId: 'kitchen-printer-01',
      ),
    );

    expect(response?['session']['id'], 42);
  });

  test(
      'getUnprintedPrintEvents omits session_id when polling all branch events',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/printer/unprinted-events');
      expect(request.url.queryParameters.containsKey('session_id'), isFalse);
      expect(request.url.queryParameters['limit'], '50');
      expect(request.headers['Authorization'], 'Bearer device-token');

      return http.Response(
        jsonEncode({
          'success': true,
          'count': 1,
          'events': [
            {'print_event_id': 11, 'order_id': 22}
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiService(LoggerService(), client: client);
    final events = await api.getUnprintedPrintEvents(
      const DeviceConfig(
        apiBaseUrl: 'https://192.168.100.7',
        wsUrl: 'wss://192.168.100.7/app/key',
        deviceId: '7',
        authToken: 'device-token',
        printerName: null,
        printerAddress: null,
        printerId: 'kitchen-printer-01',
      ),
      token: 'device-token',
      sessionId: null,
    );

    expect(events, hasLength(1));
    expect(events.single['print_event_id'], 11);
  });
}
