import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/services/printer/printer_blue_thermal.dart';

void main() {
  test('ESC/POS payload initializes printer and line-feeds each line', () {
    final bytes = PrinterBlueThermal.escPosBytesForLines([
      'WOOSOO RELAY DEVICE',
      '',
      '2 Pork Belly',
    ]);

    expect(bytes.take(2).toList(), [0x1B, 0x40]);
    expect(utf8.decode(bytes), contains('WOOSOO RELAY DEVICE\n\n2 Pork Belly'));
    expect(bytes.where((b) => b == 0x0A).length, greaterThanOrEqualTo(6));
  });

  test('ESC/POS payload strips embedded newlines from one logical row', () {
    final bytes = PrinterBlueThermal.escPosBytesForLines(['A\nB']);

    expect(utf8.decode(bytes), contains('A B\n'));
  });
}
