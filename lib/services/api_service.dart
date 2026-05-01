import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/constants.dart';
import '../models/device_config.dart';
import 'logger_service.dart';

class ApiService {
  final LoggerService log;
  late final http.Client _client;

  ApiService(this.log, {http.Client? client}) {
    if (client != null) {
      _client = client;
      return;
    }

    final httpClient = HttpClient();
    // Accept self-signed certificates from known local Pi hosts in all build modes.
    // In debug mode: accept all (existing behaviour preserved for development).
    // In release/profile mode: only accept certificates from trusted Pi endpoints.
    // This is NOT a global bypass — external HTTPS is still fully validated.
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      if (kDebugMode) {
        log.w(
            'Accepting self-signed certificate from $host:$port (debug mode)');
        return true;
      }
      final trusted = AppConstants.trustedLocalHosts.contains(host);
      if (trusted) {
        log.w(
            'Accepting self-signed certificate from trusted Pi host: $host:$port');
      }
      return trusted;
    };
    _client = IOClient(httpClient);
  }

  String _toSqlDateTimeUtc(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  Future<T> _retry<T>(Future<T> Function() fn, {String op = 'API'}) async {
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await fn();
      } on SocketException catch (e) {
        if (attempt >= AppConstants.maxApiRetries) rethrow;
        final d = Duration(seconds: 1 << (attempt - 1));
        log.w(
            '$op SocketException attempt=$attempt retry in ${d.inSeconds}s: $e');
        await Future.delayed(d);
      } on TimeoutException catch (e) {
        if (attempt >= AppConstants.maxApiRetries) rethrow;
        final d = Duration(seconds: 1 << (attempt - 1));
        log.w('$op Timeout attempt=$attempt retry in ${d.inSeconds}s: $e');
        await Future.delayed(d);
      }
    }
  }

  Map<String, String> _headers({String? token}) {
    final h = {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    };
    if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Uri _u(String base, String path, [Map<String, String>? q]) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p').replace(queryParameters: q);
  }

  /// Returns the full response body (includes `device` + `broadcasting`).
  /// Returns null on network failure or non-200 status.
  /// [ipAddress] — the device's own LAN IP. When provided it is sent as
  /// `?ip_address=<ip>` so the server can trust the client-supplied value
  /// (requires DEVICE_ALLOW_CLIENT_SUPPLIED_IP=true on the backend).
  /// This is necessary in Docker-on-Windows where all requests arrive at the
  /// nginx container from the Docker bridge gateway (172.18.0.1), not from
  /// the real LAN IP.
  Future<Map<String, dynamic>?> lookupDeviceByIp(String apiBaseUrl,
      {String? ipAddress}) async {
    return _retry(() async {
      final q = ipAddress != null ? {'ip_address': ipAddress} : null;
      final res = await _client
          .get(_u(apiBaseUrl, '/api/device/lookup-by-ip', q),
              headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return j;
    }, op: 'lookupDeviceByIp');
  }

  /// Fetch public config (broadcasting, app_version) from unauthenticated endpoint.
  /// Used on cold-start when no cached config exists.
  Future<Map<String, dynamic>?> fetchConfig(String apiBaseUrl) async {
    return _retry(() async {
      final res = await _client
          .get(_u(apiBaseUrl, '/api/config'), headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    }, op: 'fetchConfig');
  }

  Future<Map<String, dynamic>?> getLatestSession(DeviceConfig cfg) async {
    return _retry(() async {
      final res = await _client
          .get(_u(cfg.apiBaseUrl, '/api/devices/latest-session'),
              headers: _headers(token: cfg.authToken))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 401) return {'_unauthorized': true};
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    }, op: 'getLatestSession');
  }

  Future<List<Map<String, dynamic>>> getUnprintedPrintEvents(DeviceConfig cfg,
      {required String token,
      int? sessionId,
      DateTime? since,
      int limit = 50}) async {
    return _retry(() async {
      final q = {
        // session_id is optional — when omitted the server returns all unprinted
        // branch events, which is the correct behaviour for printer-relay devices.
        if (sessionId != null) 'session_id': '$sessionId',
        'limit': '$limit',
        if (since != null) 'since': _toSqlDateTimeUtc(since)
      };
      final url = _u(cfg.apiBaseUrl, '/api/printer/unprinted-events', q);
      final res = await _client
          .get(url, headers: _headers(token: token))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        final snippet = res.body.substring(0, min(200, res.body.length));
        log.w('[API ${res.statusCode}] ${url.path}: $snippet');
        throw Exception('HTTP ${res.statusCode}: $snippet');
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final list =
          (j['print_events'] as List?) ?? (j['events'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }, op: 'getUnprintedPrintEvents');
  }

  Future<bool> markPrintEventPrinted(DeviceConfig cfg, int printEventId,
      {required String token,
      required DateTime printedAt,
      required String printerId,
      String? printerName,
      String? bluetoothAddress,
      String? appVersion,
      String? verificationMode}) async {
    return _retry(() async {
      final body = jsonEncode({
        'printed_at': printedAt.toUtc().toIso8601String(),
        'printer_id': printerId,
        'printer_name': printerName,
        'bluetooth_address': bluetoothAddress,
        'app_version': appVersion,
        if (verificationMode != null) 'verification_mode': verificationMode,
      });
      final url =
          _u(cfg.apiBaseUrl, '/api/printer/print-events/$printEventId/ack');
      final res = await _client
          .post(url, headers: _headers(token: token), body: body)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        log.w(
            '[API ${res.statusCode}] ${url.path}: ${res.body.substring(0, min(200, res.body.length))}');
      }
      return res.statusCode == 200;
    }, op: 'markPrintEventPrinted');
  }

  Future<bool> markPrintEventFailed(DeviceConfig cfg, int printEventId,
      {required String token,
      required DateTime failedAt,
      required String error,
      required int attemptCount,
      String? printerName,
      String? appVersion}) async {
    return _retry(() async {
      final body = jsonEncode({
        'failed_at': failedAt.toUtc().toIso8601String(),
        'error': error,
        'attempt_count': attemptCount,
        'printer_name': printerName,
        'app_version': appVersion,
      });
      final url =
          _u(cfg.apiBaseUrl, '/api/printer/print-events/$printEventId/failed');
      final res = await _client
          .post(url, headers: _headers(token: token), body: body)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        log.w(
            '[API ${res.statusCode}] ${url.path}: ${res.body.substring(0, min(200, res.body.length))}');
      }
      return res.statusCode == 200;
    }, op: 'markPrintEventFailed');
  }

  /// Register a new device using a one-time registration code.
  /// Returns the full response body on success (contains `token` and `device`),
  /// or a map with `_error: true` on failure.
  /// [ipAddress] — the device's own LAN IP (detected via NetworkInterface).
  /// Sent as `ip_address` in the body so the server stores the correct IP
  /// instead of the Docker bridge gateway address (172.18.0.1).
  Future<Map<String, dynamic>?> registerDevice(String apiBaseUrl,
      {required String code, String? appVersion, String? ipAddress}) async {
    return _retry(() async {
      final body = jsonEncode({
        'security_code': code,
        if (appVersion != null) 'app_version': appVersion,
        if (ipAddress != null) 'ip_address': ipAddress,
      });
      final res = await _client
          .post(_u(apiBaseUrl, '/api/devices/register'),
              headers: _headers(), body: body)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      try {
        return {
          '_error': true,
          'body': jsonDecode(res.body),
          'status': res.statusCode
        };
      } catch (_) {}
      return {'_error': true, 'status': res.statusCode};
    }, op: 'registerDevice');
  }

  Future<void> sendHeartbeat(DeviceConfig cfg,
      {required Map<String, dynamic> payload}) async {
    final token = cfg.authToken ?? '';
    if (token.isEmpty) return;
    await _retry(() async {
      await _client
          .post(_u(cfg.apiBaseUrl, '/api/printer/heartbeat'),
              headers: _headers(token: token), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      return true;
    }, op: 'heartbeat');
  }
}
