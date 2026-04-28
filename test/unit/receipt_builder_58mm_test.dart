import 'package:flutter_test/flutter_test.dart';
import 'package:woosoo_relay_device/services/receipt/receipt_builder_58mm.dart';

void main() {
  test('initial receipt skips package item and prints ordered items', () {
    final lines = ReceiptBuilder58mm(width: 32).build({
      'print_type': 'INITIAL',
      'tablename': 'A1',
      'order_number': '1001',
      'items': [
        {'name': 'Lunch Set', 'quantity': 1},
        {'name': 'Kimchi Soup', 'quantity': 2},
      ],
    });

    expect(lines, contains('Package: Lunch Set'));
    expect(lines, contains('2 Kimchi Soup'));
    expect(lines.any((line) => line == '1 Lunch Set'), isFalse);
  });

  test('refill receipt prints refill header and keeps first refill item', () {
    final lines = ReceiptBuilder58mm(width: 32).build({
      'print_type': 'REFILL',
      'tablename': 'A1',
      'order_number': '1002',
      'items': [
        {'name': 'Rice', 'quantity': 1},
        {'name': 'Side Dish', 'quantity': 2},
      ],
    });

    expect(lines.any((line) => line.trim() == 'REFILL'), isTrue);
    expect(lines, isNot(contains('Package: Rice')));
    expect(lines, contains('1 Rice'));
    expect(lines, contains('2 Side Dish'));
  });
}
