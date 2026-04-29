import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
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

  static String _originFor(String wsUrl) {
    final uri = Uri.parse(wsUrl);
    final scheme = uri.scheme == 'wss' ? 'https' : 'http';
    final defaultPort = scheme == 'https' ? 443 : 80;
    final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';

    return '$scheme://${uri.host}$port';
  }

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
      // Accept self-signed certificates from known local Pi hosts in all build modes.
      // In debug mode: accept all. In release/profile mode: only trusted Pi endpoints.
      // This mirrors the pattern in ApiService and is NOT a global bypass.
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        if (kDebugMode) {
          log.w(
              'WS accepting self-signed certificate from $host:$port (debug mode)');
          return true;
        }
        // Outside debug mode, only allow self-signed certificates for trusted local hosts.
        final trusted = AppConstants.trustedLocalHosts.contains(host);
        if (trusted) {
          log.w(
              'WS accepting self-signed certificate from trusted Pi host: $host:$port');
        }
        return trusted;
      };

      final socket = await WebSocket.connect(
        wsUrl,
        headers: {'Origin': _originFor(wsUrl)},
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

      final rawError = e.toString();
      final lower = rawError.toLowerCase();
      final isCertError = lower.contains('certificate') ||
          lower.contains('cert_verify_failed') ||
          lower.contains('handshakeexception') ||
          lower.contains('tls');

      final message = isCertError && !kDebugMode
          ? 'TLS certificate validation failed for Reverb host. Install a trusted certificate on device and server before running release builds. Raw: $rawError'
          : rawError;

      onError?.call(message);
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
    _attempts++;
    final backoffIndex = _attempts <= _reconnectBackoff.length
        ? _attempts - 1
        : _reconnectBackoff.length - 1;
    final delaySeconds = _reconnectBackoff[backoffIndex];
    log.i('WS reconnect in ${delaySeconds}s (attempt $_attempts)');
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
