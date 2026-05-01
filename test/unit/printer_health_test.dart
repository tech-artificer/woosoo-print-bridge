import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/services/printer/printer_blue_thermal.dart';

void main() {
  test('ESC/POS status reports ready when printer, offline, and paper are OK',
      () {
    final health = PrinterBlueThermal.healthFromEscPosStatus(0x12, 0x12, 0x12);

    expect(health.ready, isTrue);
    expect(health.statusSupported, isTrue);
    expect(health.paperOk, isTrue);
    expect(health.coverClosed, isTrue);
    expect(health.offline, isFalse);
    expect(health.rawStatus, [0x12, 0x12, 0x12]);
  });

  test('ESC/POS paper-end bits block printer health', () {
    final health = PrinterBlueThermal.healthFromEscPosStatus(0x12, 0x12, 0x60);

    expect(health.ready, isFalse);
    expect(health.blockReason, 'printer_paper_out');
    expect(health.operatorMessage, contains('paper'));
  });

  test('ESC/POS cover-open bit blocks printer health', () {
    final health = PrinterBlueThermal.healthFromEscPosStatus(0x12, 0x16, 0x12);

    expect(health.ready, isFalse);
    expect(health.blockReason, 'printer_cover_open');
    expect(health.operatorMessage, contains('cover'));
  });

  test('ESC/POS offline bit blocks printer health', () {
    final health = PrinterBlueThermal.healthFromEscPosStatus(0x1A, 0x12, 0x12);

    expect(health.ready, isFalse);
    expect(health.blockReason, 'printer_offline');
    expect(health.operatorMessage, contains('offline'));
  });
}
