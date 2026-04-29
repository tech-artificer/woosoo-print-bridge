import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import '../logger_service.dart';
import 'printer_service.dart';

class PrinterBlueThermal implements PrinterService {
  final LoggerService log;
  final BlueThermalPrinter _bt = BlueThermalPrinter.instance;

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
      final ok = await _bt.connect(match);
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
          final retryOk = await _bt.connect(retryMatch);
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
      log.i('Printed ${lines.length} lines via printCustom');
      return true;
    } catch (e) {
      log.w('printCustom path failed, trying raw ESC/POS bytes: $e');
      try {
        if (!await isConnected()) return false;
        final bytes = escPosBytesForLines(lines);
        log.i('Writing ${bytes.length} ESC/POS bytes to printer');
        await _bt.writeBytes(bytes);
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
