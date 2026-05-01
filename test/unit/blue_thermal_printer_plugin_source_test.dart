import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Bluetooth event sinks are emitted through guarded helpers', () {
    final source = File(
      'packages/blue_thermal_printer/android/src/main/java/id/kakzaki/blue_thermal_printer/BlueThermalPrinterPlugin.java',
    ).readAsStringSync();

    expect(source, contains('private void emitStatus'));
    expect(source, contains('private void emitRead'));
    expect(source, isNot(contains('statusSink.success')));
    expect(source, isNot(contains('readSink.success')));
  });
}
