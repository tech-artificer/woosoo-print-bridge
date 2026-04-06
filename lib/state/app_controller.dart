import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:synchronized/synchronized.dart';

import '../core/constants.dart';
import '../models/device_config.dart';
import '../models/print_job.dart';
import '../services/api_service.dart';
import '../services/heartbeat_service.dart';
import '../services/logger_service.dart';
import '../services/polling_service.dart';
import '../services/queue_store.dart';
import '../services/reverb_service.dart';
import '../services/receipt/receipt_builder_58mm.dart';
import '../services/printer/printer_blue_thermal.dart';
import '../services/printer/printer_service.dart';
import '../services/permissions_service.dart';
import 'app_state.dart';

final loggerProvider = Provider<LoggerService>((ref) => LoggerService());
final permissionsProvider =
    Provider<PermissionsService>((ref) => PermissionsService());
final queueStoreProvider = Provider<QueueStore>((ref) => QueueStore());
final apiProvider =
    Provider<ApiService>((ref) => ApiService(ref.read(loggerProvider)));
final printerServiceProvider = Provider<PrinterService>(
    (ref) => PrinterBlueThermal(ref.read(loggerProvider)));

final appControllerProvider =
    StateNotifierProvider<AppController, AppState>((ref) {
  final cfg = DeviceConfig(
    apiBaseUrl: AppConstants.defaultApiBaseUrl,
    wsUrl: AppConstants.defaultWsUrl,
    deviceId: null,
    authToken: null,
    printerName: null,
    printerAddress: null,
    printerId: 'kitchen-printer-01',
  );
  return AppController(ref, ref.read(loggerProvider), cfg);
});

class AppController extends StateNotifier<AppState> {
  final Ref ref;
  final LoggerService log;
  final ReceiptBuilder58mm receipt = ReceiptBuilder58mm();

  ReverbService? _ws;
  PollingService? _polling;
  HeartbeatService? _hb;

  Timer? _queueTimer;
  Timer? _ackFlushTimer;
  Timer? _wsStatusTimer;
  Timer? _printerStatusTimer;
  // M3.5-1: Single shared lock for ALL job state mutations (prevents collision between _processQueue + flushPendingAcks)
  final _jobStateLock = Lock();
  static const List<int> _printerReconnectBackoffSeconds = [1, 2, 5, 10, 30];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final DateTime _bootedAt = DateTime.now().toUtc();

  AppController(this.ref, this.log, DeviceConfig initialCfg)
      : super(AppState(
          initialized: false,
          authenticating: false,
          config: initialCfg,
          printer: PrinterStatus.empty,
          queue: const [],
          sessionId: null,
          lastError: null,
          wsConnected: false,
          networkConnected: false,
        ));

  Duration get uptime => DateTime.now().toUtc().difference(_bootedAt);
  int get printingCount =>
      state.queue.where((j) => j.status == PrintJobStatus.printing).length;
  int get awaitingAckCount => state.queue
      .where((j) => j.status == PrintJobStatus.printed_awaiting_ack)
      .length;
  int get reconnectAttemptTotal =>
      state.queue.fold(0, (sum, j) => sum + j.printerReconnectAttempts);
  int get reconnectAttemptMax => state.queue.fold(
      0,
      (max, j) =>
          j.printerReconnectAttempts > max ? j.printerReconnectAttempts : max);
  DateTime? get lastReconnectAttempt =>
      _latestDate(state.queue.map((j) => j.lastPrinterReconnectAttempt));
  DateTime? get lastJobTime =>
      _latestDate(state.queue.map((j) => j.printedAt ?? j.createdAt));

  List<PrintJob> recentJobs({int limit = 5}) {
    if (limit <= 0) return const [];
    final jobs = List<PrintJob>.from(state.queue);
    jobs.sort((a, b) => _jobSortTime(b).compareTo(_jobSortTime(a)));
    if (jobs.length <= limit) return jobs;
    return jobs.sublist(0, limit);
  }

  DateTime _jobSortTime(PrintJob job) => job.printedAt ?? job.createdAt;

  DateTime? _latestDate(Iterable<DateTime?> dates) {
    DateTime? latest;
    for (final dt in dates) {
      if (dt == null) continue;
      if (latest == null || dt.isAfter(latest)) {
        latest = dt;
      }
    }
    return latest;
  }

  Future<void> init() async {
    await log.init();
    log.i('=== APP INITIALIZATION START ===');
    await ref.read(queueStoreProvider).init();
    await _loadConfig();
    log.i('Config loaded: apiBaseUrl=${state.config.apiBaseUrl}');

    final jobs = await ref.read(queueStoreProvider).all();
    state = state.copyWith(queue: jobs);
    log.i('Queue loaded: ${jobs.length} jobs');

    final ok = await ref.read(permissionsProvider).ensureBluetoothPermissions();
    if (!ok) {
      log.w('Bluetooth permissions not granted');
      state = state.copyWith(lastError: 'Bluetooth permissions not granted');
    } else {
      log.i('Bluetooth permissions granted');
    }

    log.i('STEP 1: Device authentication');
    await _ensureDeviceAuth();
    log.i(
        'Device auth complete: deviceId=${state.config.deviceId ?? "NULL"}, hasToken=${(state.config.authToken ?? "").isNotEmpty}');

    log.i('STEP 2: Session resolution');
    await _resolveSession();
    log.i(
        'Session resolution complete: sessionId=${state.sessionId ?? "NULL"}');

    log.i('STEP 3: Start WebSocket');
    _startWs();

    log.i('STEP 4: Start Polling');
    await _startPolling();
    log.i(
        'Polling service status: ${_polling != null ? "INITIALIZED" : "NULL"}');

    _startHeartbeat();
    _startQueueProcessor();

    await WakelockPlus.enable();
    _startWsStatusMonitor();
    _startNetworkMonitor();
    _startPrinterStatusMonitor();
    state = state.copyWith(initialized: true);
    log.i('=== APP INITIALIZATION COMPLETE ===');
  }

  Future<void> _ensureDeviceAuth() async {
    final cfg = state.config;
    if ((cfg.authToken ?? '').isNotEmpty && (cfg.deviceId ?? '').isNotEmpty) {
      return;
    }

    state = state.copyWith(authenticating: true);
    try {
      log.i('Attempting device lookup by IP from ${cfg.apiBaseUrl}');
      final device =
          await ref.read(apiProvider).lookupDeviceByIp(cfg.apiBaseUrl);
      if (device == null) {
        log.w(
            'Device lookup returned null - device not registered or API failed');
        state = state.copyWith(
            lastError: 'Device not registered (lookup-by-ip not found)');
        return;
      }

      final deviceId = (device['device_id'] ?? '').toString();
      final authToken = (device['auth_token'] ?? '').toString();
      log.i(
          'Device lookup successful: device_id=$deviceId, has_token=${authToken.isNotEmpty}');

      final next = cfg.copyWith(
        deviceId: deviceId,
        authToken: authToken,
        printerName: (device['printer_name'] ?? cfg.printerName)?.toString(),
        printerAddress:
            (device['bluetooth_address'] ?? cfg.printerAddress)?.toString(),
      );

      await _saveConfig(next);
      state = state.copyWith(config: next);
      log.i('Auto-registered device: ${next.deviceId}');
    } catch (e, st) {
      log.e('Auto-registration failed', e, st);
      state = state.copyWith(lastError: 'Auto-registration failed: $e');
    } finally {
      state = state.copyWith(authenticating: false);
    }
  }

  Future<void> _resolveSession() async {
    log.i('Fetching latest session from API...');
    final res = await ref.read(apiProvider).getLatestSession(state.config);
    if (res == null) {
      log.w('Session API returned null');
      return;
    }
    log.i('Session API response: $res');
    if (res['_unauthorized'] == true) {
      log.e('Session API returned 401 unauthorized');
      state =
          state.copyWith(lastError: 'Unauthorized (401). Re-register device.');
      return;
    }
    final session = res['session'];
    if (session is Map) {
      log.i('Session object: $session');
      final id = session['id'];
      final sid = id is int ? id : int.tryParse(id.toString());
      state = state.copyWith(sessionId: sid);
      log.i('✅ Session resolved: ${state.sessionId}');
    } else {
      log.w('Session field is not a Map: ${session?.runtimeType}');
    }
  }

  void _startWs() {
    _ws?.disconnect();
    _ws = ReverbService(
      log: log,
      onPrintEvent: (payload) async => enqueueFromPayload(payload),
      onConnect: () => state = state.copyWith(wsConnected: true, lastWsError: ''),
      onDisconnect: (reason) => state = state.copyWith(wsConnected: false, lastWsError: reason ?? ''),
      onError: (msg) => state = state.copyWith(lastWsError: msg),
    );
    _ws!.connect(state.config.wsUrl);
  }

  Future<void> _startPolling() async {
    final sessionId = state.sessionId;
    log.i('Attempting to start polling service...');
    log.i('Session ID: ${sessionId ?? "NULL"}');

    if (sessionId == null) {
      log.w('⚠️ POLLING NOT STARTED: Session ID is null');
      log.w(
          'Polling requires an active table session. WebSocket will handle print events.');
      return;
    }

    log.i('Creating polling service...');
    _polling?.stop();
    _polling = PollingService(
      log: log,
      api: ref.read(apiProvider),
      onPollError: (msg) => state = state.copyWith(lastPollError: msg),
      onEvents: (events) async {
        log.i('Polling received ${events.length} events');
        for (final e in events) {
          await enqueueFromPayload(e);
        }
      },
    );
    log.i(
        'Starting polling with interval: ${AppConstants.pollingInterval.inSeconds}s');
    await _polling!.start(state.config,
        sessionId: sessionId, interval: AppConstants.pollingInterval);
    log.i('✅ Polling service started successfully');
  }

  void _startWsStatusMonitor() {
    _wsStatusTimer?.cancel();
    _wsStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final connected = _ws?.isConnected ?? false;
      if (state.wsConnected != connected) {
        state = state.copyWith(wsConnected: connected);
      }
    });
  }

  void _startPrinterStatusMonitor() {
    _printerStatusTimer?.cancel();
    _printerStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // Skip check if printer address not configured
      if ((state.config.printerAddress ?? '').isEmpty) return;

      try {
        final printer = ref.read(printerServiceProvider);
        final connected = await printer.isConnected();

        if (state.printer.connected != connected) {
          state = state.copyWith(
              printer: state.printer.copyWith(connected: connected));
          log.i(
              'Printer status changed: ${connected ? "Connected" : "Disconnected"}');
        }
      } catch (e) {
        // Suppress errors to avoid log spam
      }
    });
  }

  void _startNetworkMonitor() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile);
      if (state.networkConnected != connected) {
        state = state.copyWith(networkConnected: connected);
        log.i('Network connectivity changed: $connected');
      }
    });

    // Check initial state
    Connectivity().checkConnectivity().then((results) {
      final connected = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile);
      state = state.copyWith(networkConnected: connected);
    });
  }

  void _startHeartbeat() {
    _hb?.stop();
    _hb = HeartbeatService(
      log: log,
      api: ref.read(apiProvider),
      buildPayload: () {
        final now = DateTime.now().toUtc();
        final successes = state.queue
            .where((j) => j.status == PrintJobStatus.success)
            .toList()
          ..sort((a, b) => (a.printedAt ?? a.createdAt)
              .compareTo(b.printedAt ?? b.createdAt));
        final last = successes.isEmpty ? null : successes.last;

        return {
          'device_id': state.config.deviceId,
          'printer_id': state.config.printerId,
          'printer_name': state.config.printerName,
          'bluetooth_address': state.config.printerAddress,
          'app_version': '1.0.0+1',
          'session_id': state.sessionId,
          'last_print_event_id': last?.printEventId,
          'last_printed_order_id': last?.orderId,
          'timestamp': now.toIso8601String(),
          'status': {
            'printer_connected': state.printer.connected,
            'queue_pending': state.pendingCount,
            'queue_failed': state.failedCount,
          }
        };
      },
    );
    _hb!.start(state.config, interval: AppConstants.heartbeatInterval);
  }

  void _startQueueProcessor() {
    _queueTimer?.cancel();
    _queueTimer =
        Timer.periodic(AppConstants.queueTick, (_) => _processQueue());

    // Start ACK flush service: retry ACKs that failed
    _ackFlushTimer?.cancel();
    _ackFlushTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => flushPendingAcks());
  }

  Future<void> enqueueFromPayload(Map<String, dynamic> payload) async {
    log.i('📥 Received print payload: $payload');
    // Normalize backend response shape: backend sends 'id' not 'print_event_id';
    // 'order_id' is nested inside 'order'; 'device_id' and 'session_id' are absent
    // from the response so we fall back to local config/state values.
    final orderMap = payload['order'] as Map<String, dynamic>?;
    final peid = payload['print_event_id'] ?? payload['printEventId'] ?? payload['id'];
    final orderId = payload['order_id'] ?? payload['orderId'] ?? orderMap?['order_id'];
    final deviceId =
        (payload['device_id'] ?? payload['deviceId'] ?? state.config.deviceId ?? '').toString();
    final sessionId = payload['session_id'] ?? payload['sessionId'] ?? state.sessionId;

    log.i(
        'Payload validation: print_event_id=$peid, order_id=$orderId, device_id=$deviceId, session_id=$sessionId');

    // P3-RELX-5: Strict validation - reject payload if print_event_id is missing
    if (peid == null) {
      log.w('❌ Payload REJECTED: missing print_event_id. Payload: $payload');
      return;
    }

    // M3.5-4: Positive ID validation - reject print_event_id <= 0
    final printEventId = peid is int ? peid : int.tryParse(peid.toString());
    if (printEventId == null || printEventId <= 0) {
      log.w(
          'Invalid print_event_id: $printEventId (must be > 0) - rejecting. Payload: $payload');
      return;
    }

    // C4: Device_id filtering - TEMPORARILY DISABLED for emergency printing
    // TODO: Re-enable after device lookup is working
    final myDeviceId = state.config.deviceId ?? '';
    if (myDeviceId.isNotEmpty &&
        deviceId.isNotEmpty &&
        deviceId != myDeviceId) {
      log.w(
          'Cross-device event rejected: print_event_id=$printEventId deviceId=$deviceId (mine=$myDeviceId)');
      return;
    } else if (myDeviceId.isEmpty) {
      log.w(
          'Device ID not configured - accepting event anyway (EMERGENCY MODE)');
    }

    final oId = orderId is int ? orderId : int.tryParse(orderId.toString());
    final sId = sessionId == null
        ? null
        : (sessionId is int ? sessionId : int.tryParse(sessionId.toString()));

    if (oId == null || deviceId.isEmpty) {
      log.w('Invalid payload skipped: $payload');
      return;
    }

    final store = ref.read(queueStoreProvider);
    if (await store.exists(printEventId)) {
      log.d('Duplicate print_event_id=$printEventId ignored');
      return;
    }

    final printType =
        (payload['print_type'] ?? payload['printType'] ?? 'INITIAL')
            .toString()
            .toUpperCase();
    final refill = payload['refill_number'] ?? payload['refillNumber'];
    final refillNo = refill == null
        ? null
        : (refill is int ? refill : int.tryParse(refill.toString()));

    final job = PrintJob(
      printEventId: printEventId,
      deviceId: deviceId,
      orderId: oId,
      sessionId: sId,
      printType: printType,
      refillNumber: refillNo,
      payload: payload,
      status: PrintJobStatus.pending,
      retryCount: 0,
      lastError: null,
      createdAt: DateTime.now().toUtc(),
      printedAt: null,
      ackAttempts: 0,
      lastAckAttempt: null,
    );

    await store.upsert(job);
    state = state.copyWith(queue: await store.all());
    log.i('Enqueued print_event_id=$printEventId order_id=$oId');
  }

  Future<bool> connectPrinterByAddress(String address, {String? name}) async {
    // M3.5-3: Track reconnect attempts and implement exponential backoff [1,2,5,10,30]s
    final printer = ref.read(printerServiceProvider);
    final ok = await printer.connectByAddress(address);
    if (ok) {
      final cfg = state.config.copyWith(
          printerAddress: address,
          printerName: name ?? state.config.printerName);
      await _saveConfig(cfg);
      state = state.copyWith(
          config: cfg,
          printer: state.printer.copyWith(
              connected: true, address: address, name: name, error: null));

      // M3.5-3: Reset printer reconnect attempts on successful connection
      final store = ref.read(queueStoreProvider);
      final jobs = await store.all();
      for (final job in jobs.where((j) => j.printerReconnectAttempts > 0)) {
        await store.updateJob(
            job.printEventId,
            (old) => old.copyWith(
                  printerReconnectAttempts: 0,
                  lastPrinterReconnectAttempt: null,
                ));
      }
      state = state.copyWith(queue: await store.all());
      return true;
    } else {
      state = state.copyWith(
          printer: state.printer
              .copyWith(connected: false, error: 'Connect failed'));
      return false;
    }
  }

  // M3.5-3: Printer reconnect backoff - checks if job has exceeded max reconnect attempts
  Future<bool> _shouldReconnectPrinter(PrintJob job) async {
    final attempts = job.printerReconnectAttempts;
    if (attempts <= 0) return true;

    final lastAttempt = job.lastPrinterReconnectAttempt;
    if (lastAttempt == null) return true;

    // Backoff progression: [1, 2, 5, 10, 30] seconds
    final backoffSeconds = _printerReconnectBackoffSeconds[attempts - 1];
    final nextRetryTime = lastAttempt.add(Duration(seconds: backoffSeconds));
    final now = DateTime.now().toUtc();

    // If backoff window hasn't elapsed yet, don't reconnect
    if (now.isBefore(nextRetryTime)) {
      log.d(
          'Printer reconnect backoff active for job ${job.printEventId} (attempt $attempts/5, wait ${nextRetryTime.difference(now).inSeconds}s)');
      return false;
    }

    return true;
  }

  Future<void> disconnectPrinter() async {
    await ref.read(printerServiceProvider).disconnect();
    state = state.copyWith(printer: state.printer.copyWith(connected: false));
  }

  Future<void> testPrint() async {
    final ok = await ref.read(printerServiceProvider).testPrint();
    if (!ok) {
      state = state.copyWith(
          lastError: 'Test print failed (printer not connected?)');
    }
  }

  Future<void> retryJob(int printEventId) async {
    final store = ref.read(queueStoreProvider);
    await store.updateJob(
        printEventId,
        (old) => old.copyWith(
            status: PrintJobStatus.pending, retryCount: 0, lastError: null));
    state = state.copyWith(queue: await store.all());
  }

  Future<void> cancelJob(int printEventId) async {
    final store = ref.read(queueStoreProvider);
    await store.updateJob(
        printEventId, (old) => old.copyWith(status: PrintJobStatus.cancelled));
    state = state.copyWith(queue: await store.all());
  }

  Future<void> clearQueue() async {
    await ref.read(queueStoreProvider).clear();
    state = state.copyWith(queue: const []);
  }

  Future<void> forcePoll() async {
    final polling = _polling;
    log.i('Force poll requested');
    log.i('Polling service: ${polling != null ? "INITIALIZED" : "NULL"}');
    log.i('Session ID: ${state.sessionId ?? "NULL"}');
    log.i('Device ID: ${state.config.deviceId ?? "NULL"}');

    if (polling == null) {
      log.w('⚠️ Force poll FAILED: Polling service not initialized');
      log.w(
          'Reason: Polling requires session ID, currently: ${state.sessionId ?? "NULL"}');
      log.w(
          'Workaround: WebSocket is active and will receive print events automatically');
      return;
    }

    log.i('Executing force poll...');
    await polling.forceTick(state.config);
    log.i('✅ Force poll complete');
  }

  Future<void> _processQueue() async {
    // P3-RELX-1: Single-worker print engine (Gate 1)
    // The _jobStateLock mutex ensures only ONE job can be in 'printing' state at any time.
    // No parallel print operations are possible; jobs are processed sequentially.
    // M3.5-1: This lock is SHARED with flushPendingAcks() to prevent state collision.
    await _jobStateLock.synchronized(() async {
      try {
        final printer = ref.read(printerServiceProvider);
        final isConnected = await printer.isConnected();

        if (!isConnected && (state.config.printerAddress ?? '').isNotEmpty) {
          // M3.5-3: Check printer reconnect backoff before attempting reconnection
          final store = ref.read(queueStoreProvider);
          final jobs = await store.all();
          final pendingJobs =
              jobs.where((j) => j.status == PrintJobStatus.pending).toList();
          final next = pendingJobs.isEmpty ? null : pendingJobs.first;

          if (next != null) {
            if (next.printerReconnectAttempts >= 5) {
              log.w(
                  'Printer reconnect max attempts (5) exceeded for job ${next.printEventId}, marking as failed');
              await store.updateJob(
                  next.printEventId,
                  (old) => old.copyWith(
                        status: PrintJobStatus.failed,
                        lastError: 'Printer reconnect max attempts exceeded',
                      ));
              state = state.copyWith(queue: await store.all());
              return;
            }

            final shouldReconnect = await _shouldReconnectPrinter(next);
            if (!shouldReconnect) {
              return;
            }

            final okReconnect = await connectPrinterByAddress(
                state.config.printerAddress!,
                name: state.config.printerName);
            if (!okReconnect) {
              final now = DateTime.now().toUtc();
              final newAttempts = next.printerReconnectAttempts + 1;
              final failed = newAttempts >= 5;

              await store.updateJob(
                  next.printEventId,
                  (old) => old.copyWith(
                        printerReconnectAttempts: newAttempts,
                        lastPrinterReconnectAttempt: now,
                        status: failed ? PrintJobStatus.failed : old.status,
                        lastError: failed
                            ? 'Printer reconnect max attempts exceeded'
                            : 'Printer reconnect failed',
                      ));
              state = state.copyWith(queue: await store.all());
              return;
            }
          } else {
            await connectPrinterByAddress(state.config.printerAddress!,
                name: state.config.printerName);
          }
        }

        final connected = await printer.isConnected();
        state = state.copyWith(
            printer: state.printer.copyWith(connected: connected));

        if (!connected) return;

        final store = ref.read(queueStoreProvider);
        final jobs = await store.all();
        final next =
            jobs.where((j) => j.status == PrintJobStatus.pending).isEmpty
                ? null
                : jobs.where((j) => j.status == PrintJobStatus.pending).first;

        if (next == null) return;

        await store.updateJob(next.printEventId,
            (old) => old.copyWith(status: PrintJobStatus.printing));
        state = state.copyWith(queue: await store.all());

        final okPrint = await printer.printLines(receipt.build(next.payload));
        if (!okPrint) {
          await _handlePrintFailure(next, 'Print command failed');
          return;
        }

        await printer.cut();

        // C2: Mark as printed_awaiting_ack first, queue for retry if ACK fails
        await store.updateJob(
            next.printEventId,
            (old) => old.copyWith(
                  status: PrintJobStatus.printed_awaiting_ack,
                  printedAt: DateTime.now().toUtc(),
                  lastError: null,
                  ackAttempts: 0,
                  lastAckAttempt: DateTime.now().toUtc(),
                ));

        final ackOk = await ref.read(apiProvider).markPrintEventPrinted(
              state.config,
              next.printEventId,
              token: state.config.authToken ?? '',
              printedAt: DateTime.now().toUtc(),
              printerId: state.config.printerId,
              printerName: state.config.printerName,
              bluetoothAddress: state.config.printerAddress,
              appVersion: '1.0.0+1',
            );

        if (ackOk) {
          // ACK succeeded: mark success
          await store.updateJob(
              next.printEventId,
              (old) => old.copyWith(
                  status: PrintJobStatus.success, lastError: null));
        } else {
          // ACK failed: leave as printed_awaiting_ack for flush service to retry
          await store.updateJob(next.printEventId,
              (old) => old.copyWith(lastError: 'ACK failed, queued for retry'));
        }
        state = state.copyWith(queue: await store.all());
      } catch (e) {
        state = state.copyWith(lastError: 'Queue error: $e');
      }
    });
  }

  Future<void> _handlePrintFailure(PrintJob job, String error) async {
    final store = ref.read(queueStoreProvider);
    final nextRetry = job.retryCount + 1;

    if (nextRetry >= AppConstants.maxPrintAttempts) {
      await store.updateJob(
          job.printEventId,
          (old) => old.copyWith(
              status: PrintJobStatus.failed,
              retryCount: nextRetry,
              lastError: error));
      state = state.copyWith(queue: await store.all());

      await ref.read(apiProvider).markPrintEventFailed(
            state.config,
            job.printEventId,
            token: state.config.authToken ?? '',
            failedAt: DateTime.now().toUtc(),
            error: error,
            attemptCount: nextRetry,
            printerName: state.config.printerName,
            appVersion: '1.0.0+1',
          );
      return;
    }

    final delaySeconds = 1 << (nextRetry - 1);
    await store.updateJob(
        job.printEventId,
        (old) => old.copyWith(
            status: PrintJobStatus.pending,
            retryCount: nextRetry,
            lastError: error));
    state = state.copyWith(queue: await store.all());
    await Future.delayed(Duration(seconds: delaySeconds));
  }

  // C3: Flush pending ACKs with exponential backoff and retry limits
  Future<void> flushPendingAcks() async {
    // M3.5-1: Share _jobStateLock with _processQueue to prevent simultaneous state mutations
    await _jobStateLock.synchronized(() async {
      try {
        final store = ref.read(queueStoreProvider);
        final jobs = await store.all();

        // Find jobs waiting for ACK acknowledgement
        final pending = jobs
            .where((j) => j.status == PrintJobStatus.printed_awaiting_ack)
            .toList();
        if (pending.isEmpty) return;

        log.i('Flushing ${pending.length} pending ACKs');

        for (final job in pending) {
          final ackAttempts = job.ackAttempts ?? 0;
          final lastAttempt = job.lastAckAttempt;

          // Check if we should retry: max 3 attempts with exponential backoff (2s, 4s, 8s)
          if (ackAttempts >= 3) {
            log.w(
                'ACK max retries exceeded for print_event_id=${job.printEventId}, marking as failed');
            await store.updateJob(
                job.printEventId,
                (old) => old.copyWith(
                      status: PrintJobStatus.failed,
                      lastError: 'ACK failed after 3 retries',
                    ));
            state = state.copyWith(queue: await store.all());
            continue;
          }

          // Exponential backoff based on CURRENT ackAttempts (count of failures that happened):
          // ackAttempts=0 (no failures) → no backoff, can attempt immediately
          // ackAttempts=1 (one failure) → need to wait backoff[0]=2s before next attempt
          // ackAttempts=2 (two failures) → need to wait backoff[1]=4s before next attempt
          final backoffSeconds =
              ackAttempts > 0 ? [2, 4, 8][ackAttempts - 1] : 0;
          final nextRetryTime =
              lastAttempt?.add(Duration(seconds: backoffSeconds));

          // If we have a last attempt time and backoff window is active, skip
          if (nextRetryTime != null && DateTime.now().isBefore(nextRetryTime)) {
            log.d(
                'Skipping ACK retry for print_event_id=${job.printEventId}, backoff in progress');
            continue;
          }

          // Special case: if lastAckAttempt is very recent (< 1 second), also skip
          // This prevents rapid retry loops even if ackAttempts hasn't been incremented yet
          if (lastAttempt != null &&
              DateTime.now().difference(lastAttempt).inSeconds < 1) {
            log.d(
                'Skipping ACK retry for print_event_id=${job.printEventId}, too soon since last attempt');
            continue;
          }

          // Attempt ACK
          log.i(
              'Retrying ACK for print_event_id=${job.printEventId} (attempt ${ackAttempts + 1}/3)');
          final ackOk = await ref.read(apiProvider).markPrintEventPrinted(
                state.config,
                job.printEventId,
                token: state.config.authToken ?? '',
                printedAt: job.printedAt ?? DateTime.now().toUtc(),
                printerId: state.config.printerId,
                printerName: state.config.printerName,
                bluetoothAddress: state.config.printerAddress,
                appVersion: '1.0.0+1',
              );

          if (ackOk) {
            log.i('ACK succeeded for print_event_id=${job.printEventId}');
            await store.updateJob(
                job.printEventId,
                (old) => old.copyWith(
                      status: PrintJobStatus.success,
                      lastError: null,
                    ));
          } else {
            // Increment attempt counter and update last attempt time
            final newAttempts = (job.ackAttempts ?? 0) + 1;

            // Check if we've exceeded max retries after this failure
            if (newAttempts >= 3) {
              log.w(
                  'ACK max retries exceeded for print_event_id=${job.printEventId}, marking as failed');
              await store.updateJob(
                  job.printEventId,
                  (old) => old.copyWith(
                        status: PrintJobStatus.failed,
                        lastError: 'ACK failed after 3 retries',
                      ));
            } else {
              await store.updateJob(
                  job.printEventId,
                  (old) => old.copyWith(
                        ackAttempts: newAttempts,
                        lastAckAttempt: DateTime.now().toUtc(),
                        lastError: 'ACK failed, retry scheduled',
                      ));
            }
          }
          state = state.copyWith(queue: await store.all());
        }
      } catch (e) {
        log.e('ACK flush error: $e');
      }
    });
  }

  Future<void> updateConfig(DeviceConfig cfg) async {
    await _saveConfig(cfg);
    state = state.copyWith(config: cfg);
    _startWs();
    await _startPolling();
    _startHeartbeat();
  }

  /// Register this device with the backend using a one-time code.
  /// On success saves the returned auth token + device ID and reconnects.
  /// Returns null on success, or an error message string on failure.
  Future<String?> registerDevice(
      {required String name, required String code}) async {
    final apiBaseUrl = state.config.apiBaseUrl;
    log.i('Registering device: name=$name, apiBaseUrl=$apiBaseUrl');

    Map<String, dynamic>? res;
    try {
      res = await ref.read(apiProvider).registerDevice(apiBaseUrl,
          name: name, code: code, appVersion: '1.0.0+1');
    } catch (e) {
      log.e('registerDevice exception: $e');
      return 'Network error: $e';
    }

    if (res == null) return 'No response from server';

    if (res['_error'] == true) {
      final body = res['body'];
      final msg = (body is Map ? body['message'] ?? body['error'] : null) ??
          'Registration failed (${res['status']})';
      log.w('registerDevice failed: $msg');
      return msg.toString();
    }

    final token = (res['token'] ?? '').toString();
    final device = res['device'];
    final deviceId = (device is Map ? device['id'] : null)?.toString() ?? '';

    if (token.isEmpty || deviceId.isEmpty) {
      return 'Invalid response: missing token or device id';
    }

    final next = state.config.copyWith(authToken: token, deviceId: deviceId);
    await _saveConfig(next);
    state = state.copyWith(config: next);
    log.i('✅ Device registered: device_id=$deviceId');

    // Reconnect with new credentials
    _startWs();
    await _resolveSession();
    await _startPolling();
    _startHeartbeat();

    return null; // success
  }

  Future<void> _loadConfig() async {
    final sp = await SharedPreferences.getInstance();

    // Migration: Auto-upgrade old HTTP URLs to HTTPS
    var apiBaseUrl =
        sp.getString('apiBaseUrl') ?? AppConstants.defaultApiBaseUrl;
    final reverbAppKey =
        sp.getString('reverbAppKey') ?? AppConstants.defaultReverbAppKey;

    if (apiBaseUrl.startsWith('http://')) {
      apiBaseUrl = apiBaseUrl.replaceFirst('http://', 'https://');
      await sp.setString('apiBaseUrl', apiBaseUrl);
      log.i('Migrated API URL to HTTPS: $apiBaseUrl');
    }

    // Always re-derive the WS URL from apiBaseUrl + reverbAppKey so it stays in sync.
    // This replaces the old :6001 / ws:// migration and ensures any server change
    // automatically propagates to the WebSocket connection.
    final wsUrl = AppConstants.deriveWsUrl(apiBaseUrl, appKey: reverbAppKey);
    await sp.setString('wsUrl', wsUrl);

    final cfg = DeviceConfig(
      apiBaseUrl: apiBaseUrl,
      wsUrl: wsUrl,
      reverbAppKey: reverbAppKey,
      deviceId: sp.getString('deviceId'),
      authToken: sp.getString('authToken'),
      printerName: sp.getString('printerName'),
      printerAddress: sp.getString('printerAddress'),
      printerId: sp.getString('printerId') ?? 'kitchen-printer-01',
    );
    state = state.copyWith(config: cfg);
  }

  Future<void> _saveConfig(DeviceConfig cfg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('apiBaseUrl', cfg.apiBaseUrl);
    await sp.setString('wsUrl', cfg.wsUrl);
    await sp.setString('reverbAppKey', cfg.reverbAppKey);
    if (cfg.deviceId != null) await sp.setString('deviceId', cfg.deviceId!);
    if (cfg.authToken != null) await sp.setString('authToken', cfg.authToken!);
    if (cfg.printerName != null) {
      await sp.setString('printerName', cfg.printerName!);
    }
    if (cfg.printerAddress != null) {
      await sp.setString('printerAddress', cfg.printerAddress!);
    }
    await sp.setString('printerId', cfg.printerId);
  }

  /// Reprint an order by creating a new print job with the same payload
  Future<void> reprintOrder(PrintJob original) async {
    log.i(
        'Reprint requested for order_id=${original.orderId}, print_event_id=${original.printEventId}');

    final store = ref.read(queueStoreProvider);

    // Create a new print job with a unique ID (use negative IDs for reprints to avoid conflicts)
    final reprintId = -(DateTime.now().millisecondsSinceEpoch);

    final reprintJob = PrintJob(
      printEventId: reprintId,
      deviceId: original.deviceId,
      orderId: original.orderId,
      sessionId: original.sessionId,
      printType: '${original.printType}-REPRINT',
      refillNumber: original.refillNumber,
      payload: original.payload,
      status: PrintJobStatus.pending,
      retryCount: 0,
      lastError: null,
      createdAt: DateTime.now().toUtc(),
      printedAt: null,
      ackAttempts: 0,
      lastAckAttempt: null,
    );

    await store.upsert(reprintJob);
    state = state.copyWith(queue: await store.all());

    log.i(
        'Reprint job created with temp ID=$reprintId for order_id=${original.orderId}');
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    _ackFlushTimer?.cancel();
    _wsStatusTimer?.cancel();
    _printerStatusTimer?.cancel();
    _polling?.stop();
    _hb?.stop();
    _ws?.disconnect();
    _connectivitySub?.cancel();
    unawaited(ref.read(queueStoreProvider).close());
    log.dispose();
    super.dispose();
  }
}
