import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:woosoo_relay_device/services/api_service.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';

void main() {
  test('registerDevice sends setup code as security_code and accepts 200', () async {
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
}
