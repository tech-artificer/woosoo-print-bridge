import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/services/logger_service.dart';
import 'package:woosoo_relay_device/services/reverb_service.dart';

void main() {
  test('reports print event handler errors without uncaught async exception',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];

    unawaited(server.forEach((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      unawaited(Future<void>.delayed(const Duration(milliseconds: 10), () {
        socket.add(jsonEncode({
          'event': 'order.printed',
          'data': jsonEncode({'print_event_id': 42}),
        }));
      }));
    }));

    final uncaughtErrors = <Object>[];
    final reportedErrors = <String>[];

    await runZonedGuarded(() async {
      final service = ReverbService(
        log: LoggerService(),
        onPrintEvent: (_) async => throw StateError('enqueue failed'),
        onError: reportedErrors.add,
      );

      await service.connect(
        'ws://${InternetAddress.loopbackIPv4.address}:${server.port}/app/key?protocol=7&client=flutter&version=1.0',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await service.disconnect();
    }, (error, _) {
      uncaughtErrors.add(error);
    });

    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);

    expect(uncaughtErrors, isEmpty);
    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single, contains('enqueue failed'));
  });
}
