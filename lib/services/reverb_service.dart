import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'logger_service.dart';

typedef PrintEventHandler = Future<void> Function(Map<String, dynamic> payload);

class ReverbService {
  final LoggerService log;
  final PrintEventHandler onPrintEvent;
  final void Function(String)? onError;
  final void Function()? onConnect;
  final void Function(String?)? onDisconnect;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  bool _connected = false;
  bool get isConnected => _connected;

  int _attempts = 0;
  Timer? _reconnectTimer;
  String? _wsUrl;

  // Exponential backoff cap: max 60 seconds between reconnect attempts
  static const _reconnectBackoff = [1, 2, 4, 8, 16, 30, 60];

  ReverbService({
    required this.log,
    required this.onPrintEvent,
    this.onError,
    this.onConnect,
    this.onDisconnect,
  });

  Future<void> connect(String wsUrl) async {
    _wsUrl = wsUrl;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    final wsUrl = _wsUrl;
    if (wsUrl == null || wsUrl.isEmpty) return;

    await disconnect();
    try {
      log.i('WS connecting: $wsUrl');

      final httpClient = HttpClient();
      if (kDebugMode) {
        // Accept self-signed certificates in debug builds only.
        // In release/profile builds the default certificate validation is enforced.
        httpClient.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          log.w('WS accepting self-signed certificate from $host:$port (debug only)');
          return true;
        };
      }

      final socket = await WebSocket.connect(
        wsUrl,
        customClient: httpClient,
      );

      _ch = IOWebSocketChannel(socket);
      _connected = true;
      _attempts = 0;
      onConnect?.call();

      // Do NOT send pusher:subscribe here — wait for pusher:connection_established
      // from the server before subscribing (Pusher protocol requirement).

      _sub = _ch!.stream.listen((msg) async => _handleMessage(msg),
          onError: (e, st) {
        log.e('WS error', e, st);
        _connected = false;
        onDisconnect?.call(e.toString());
        _scheduleReconnect();
      }, onDone: () {
        log.w('WS disconnected');
        _connected = false;
        onDisconnect?.call('WS disconnected');
        _scheduleReconnect();
      }, cancelOnError: true);

      log.i('WS connected — awaiting pusher:connection_established');
    } catch (e, st) {
      log.e('WS connect failed', e, st);
      _connected = false;
      onError?.call(e.toString());
      _scheduleReconnect();
    }
  }

  Future<void> _handleMessage(dynamic raw) async {
    if (raw == null) return;
    Map<String, dynamic>? msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final event = (msg['event'] ?? '').toString();

    // Handle Pusher protocol handshake and control events before filtering
    if (event == 'pusher:connection_established') {
      _ch!.sink.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'channel': 'admin.print'},
      }));
      log.i('[WS] Subscribed to admin.print');
      return;
    }

    if (event == 'pusher:subscription_succeeded') {
      log.i('[WS] Subscription confirmed for admin.print');
      return;
    }

    if (event == 'pusher:error') {
      final data = msg['data'];
      log.e('[WS] Pusher error: $data');
      onError?.call('Pusher error: $data');
      return;
    }

    if (event.startsWith('pusher:') || event.startsWith('pusher_internal:')) {
      return;
    }

    final normalized = event.startsWith('.') ? event.substring(1) : event;
    if (normalized != 'order.printed') return;

    dynamic data = msg['data'];
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return;
      }
    }
    if (data is Map) await onPrintEvent(Map<String, dynamic>.from(data));
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_attempts >= 10) {
      log.w('WS max reconnect attempts reached; polling continues');
      return;
    }
    _attempts++;
    final backoffIndex = _attempts <= _reconnectBackoff.length
        ? _attempts - 1
        : _reconnectBackoff.length - 1;
    final delaySeconds = _reconnectBackoff[backoffIndex];
    log.i('WS reconnect in ${delaySeconds}s (attempt $_attempts/10)');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!_connected) await _connectInternal();
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    _connected = false;
  }
}
