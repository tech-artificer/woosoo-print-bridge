import 'dart:convert';
import 'dart:async';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import '../logger_service.dart';
import 'printer_service.dart';

class PrinterBlueThermal implements PrinterService {
  final LoggerService log;
  final BlueThermalPrinter _bt = BlueThermalPrinter.instance;
  Future<bool>? _connectInFlight;

  PrinterBlueThermal(this.log);

  @override
  Future<void> init() async {}

  @override
  Future<List<Map<String, String>>> bondedDevices() async {
    final devices = await _bt.getBondedDevices();
    return devices
        .map((d) => {'name': d.name ?? '', 'address': d.address ?? ''})
        .where((d) => (d['address'] ?? '').isNotEmpty)
        .toList();
  }

  @override
  Future<bool> connectByAddress(String address) async {
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      log.d('Printer connect already in-flight for $address; joining request');
      return inFlight;
    }

    final future = _connectByAddressInternal(address);
    _connectInFlight = future;
    future.whenComplete(() {
      if (identical(_connectInFlight, future)) {
        _connectInFlight = null;
      }
    });
    return future;
  }

  Future<bool> _connectByAddressInternal(String address) async {
    try {
      if (await isConnected()) {
        log.i('Printer already connected; skipping reconnect');
        return true;
      }

      final devices = await _bt.getBondedDevices();
      final match = devices.firstWhere(
        (d) => (d.address ?? '').toUpperCase() == address.toUpperCase(),
        orElse: () => BluetoothDevice(address, address),
      );
      final ok = await _bt
          .connect(match)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      log.i('Printer connectByAddress($address) => $ok');
      return ok == true;
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (e.code == 'connect_error' && msg.contains('already connected')) {
        log.w('Printer connectByAddress($address): already connected');
        return true;
      }

      final socketReadFailed = e.code == 'connect_error' &&
          (msg.contains('read failed') ||
              msg.contains('socket might closed') ||
              msg.contains('timeout'));
      if (socketReadFailed) {
        log.w(
            'Printer connect read-failed; forcing disconnect then retry once');
        try {
          await _bt.disconnect();
        } catch (_) {}

        try {
          final devices = await _bt.getBondedDevices();
          final retryMatch = devices.firstWhere(
            (d) => (d.address ?? '').toUpperCase() == address.toUpperCase(),
            orElse: () => BluetoothDevice(address, address),
          );
          final retryOk = await _bt
              .connect(retryMatch)
              .timeout(const Duration(seconds: 8), onTimeout: () => false);
          log.i('Printer reconnect retry($address) => $retryOk');
          return retryOk == true;
        } catch (retryError, retryStack) {
          log.e('Printer reconnect retry failed', retryError, retryStack);
          return false;
        }
      }

      log.e('Printer connect error', e, StackTrace.current);
      return false;
    } catch (e, st) {
      log.e('Printer connect error', e, st);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _bt.disconnect();
    } catch (_) {}
  }

  @override
  Future<bool> isConnected() async {
    try {
      return (await _bt.isConnected) == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<PrinterConnectionStatus> watchConnectionStatus() {
    return _bt.onStateChanged().map((state) {
      switch (state) {
        case BlueThermalPrinter.CONNECTED:
          return PrinterConnectionStatus.connected;
        case BlueThermalPrinter.DISCONNECTED:
          return PrinterConnectionStatus.disconnected;
        case BlueThermalPrinter.DISCONNECT_REQUESTED:
          return PrinterConnectionStatus.disconnectRequested;
        case BlueThermalPrinter.STATE_OFF:
        case BlueThermalPrinter.STATE_TURNING_OFF:
          return PrinterConnectionStatus.bluetoothOff;
        default:
          return PrinterConnectionStatus.unknown;
      }
    });
  }

  @override
  Future<PrinterHealthResult> checkHealth({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!await isConnected()) return PrinterHealthResult.disconnected();

    final printer = await _queryStatus(1, timeout);
    final offline = await _queryStatus(2, timeout);
    final paper = await _queryStatus(4, timeout);
    if (printer == null || offline == null || paper == null) {
      return PrinterHealthResult.unsupported(
        message: 'No DLE EOT response from printer.',
      );
    }

    return healthFromEscPosStatus(printer, offline, paper);
  }

  static PrinterHealthResult healthFromEscPosStatus(
    int printer,
    int offline,
    int paper,
  ) {
    final isOffline = (printer & 0x08) != 0 || (offline & 0x08) != 0;
    final coverClosed = (offline & 0x04) == 0;
    final paperOk = (paper & 0x60) == 0;
    final message = !paperOk
        ? 'Printer paper is out.'
        : !coverClosed
            ? 'Printer cover is open.'
            : isOffline
                ? 'Printer is offline.'
                : null;

    return PrinterHealthResult(
      connected: true,
      statusSupported: true,
      paperOk: paperOk,
      coverClosed: coverClosed,
      offline: isOffline,
      rawStatus: [printer, offline, paper],
      checkedAt: DateTime.now().toUtc(),
      message: message,
    );
  }

  Future<int?> _queryStatus(int statusType, Duration timeout) async {
    StreamSubscription<Uint8List>? sub;
    final completer = Completer<int?>();
    try {
      sub = _bt.onReadRaw().listen((bytes) {
        if (!completer.isCompleted && bytes.isNotEmpty) {
          completer.complete(bytes.first);
        }
      });
      await _bt.writeBytes(Uint8List.fromList([0x10, 0x04, statusType]));
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e, st) {
      log.w('Printer DLE EOT $statusType failed: $e');
      log.e('Printer status query failure', e, st);
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  @override
  Future<bool> printLines(List<String> lines) async {
    try {
      if (!await isConnected()) return false;

      // Preferred path for broad device compatibility.
      // Some printer/driver combinations silently ignore raw writeBytes payloads.
      for (final line in lines) {
        final normalized = line.replaceAll('\r', '').replaceAll('\n', ' ');
        if (normalized.isEmpty) {
          await _bt.printNewLine();
        } else {
          await _bt.printCustom(normalized, 0, 0);
        }
      }
      await _bt.printNewLine();
      await _bt.printNewLine();
      if (!await isConnected()) {
        log.w('Printer disconnected after printCustom write');
        return false;
      }
      log.i('Printed ${lines.length} lines via printCustom');
      return true;
    } catch (e) {
      log.w('printCustom path failed, trying raw ESC/POS bytes: $e');
      try {
        if (!await isConnected()) return false;
        final bytes = escPosBytesForLines(lines);
        log.i('Writing ${bytes.length} ESC/POS bytes to printer');
        await _bt.writeBytes(bytes);
        if (!await isConnected()) {
          log.w('Printer disconnected after raw ESC/POS write');
          return false;
        }
        return true;
      } catch (fallbackError, fallbackStack) {
        log.e('printLines failed', fallbackError, fallbackStack);
        return false;
      }
    }
  }

  static Uint8List escPosBytesForLines(List<String> lines) {
    final bytes = <int>[
      0x1B, 0x40, // ESC @ - initialize printer
    ];

    for (final line in lines) {
      final normalized = line.replaceAll('\r', '').replaceAll('\n', ' ');
      bytes.addAll(utf8.encode(normalized));
      bytes.add(0x0A);
    }

    bytes.addAll([0x0A, 0x0A, 0x0A]);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> testPrint() =>
      printLines(['WOOSOO RELAY DEVICE', 'PB-58H TEST OK', '']);

  @override
  Future<void> cut() async {
    try {
      await _bt.paperCut();
    } catch (_) {}
  }
}
