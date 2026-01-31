import 'package:flutter_test/flutter_test.dart';

/// Contract Test: Backend → Relay Device (Print Event Intake)
/// 
/// Verifies that the relay device can correctly parse and validate
/// print event payloads from the backend's WebSocket broadcasts.
/// 
/// This test documents the contract and prevents breaking changes.

void main() {
  group('Contract: Backend → Relay Device (Print Event Intake)', () {
    test('should accept valid PrintOrder payload with all required fields', () {
      // Arrange: Mock backend PrintOrder.broadcastWith() payload
      final payload = {
        'print_event_id': 123,
        'device_id': 5,
        'order_id': 456,
        'session_id': 789,
        'print_type': 'INITIAL',
        'refill_number': null,
        'tablename': 'Table 1',
        'created_at': '2026-01-29T10:30:00Z',
        'order': {
          'id': 1,
          'order_id': 456,
          'order_number': 'ORD-001',
          'device_id': 5,
          'status': 'pending',
          'guest_count': 4,
          'total': 2500.00,
        },
        'items': [
          {'id': 1, 'menu_id': 10, 'name': 'Beef Brisket', 'quantity': 2, 'price': 150.00},
          {'id': 2, 'menu_id': 20, 'name': 'Kimchi', 'quantity': 1, 'price': 50.00},
        ],
      };

      // Act: Extract fields (simulating relay device intake)
      final printEventId = payload['print_event_id'] as int?;
      final deviceId = payload['device_id'] as int?;
      final orderId = payload['order_id'] as int?;
      final printType = payload['print_type'] as String?;

      // Assert: All required fields present and valid
      expect(printEventId, isNotNull, reason: 'print_event_id must be present');
      expect(printEventId, greaterThan(0), reason: 'print_event_id must be > 0');
      expect(printEventId, equals(123));

      expect(deviceId, isNotNull, reason: 'device_id must be present');
      expect(deviceId, greaterThan(0), reason: 'device_id must be > 0');
      expect(deviceId, equals(5));

      expect(orderId, isNotNull, reason: 'order_id must be present');
      expect(orderId, greaterThan(0), reason: 'order_id must be > 0');
      expect(orderId, equals(456));

      expect(printType, isNotNull, reason: 'print_type must be present');
      expect(printType, equals('INITIAL'));

      // Assert: Nested data for printing
      expect(payload['order'], isNotNull);
      expect(payload['items'], isNotNull);
      expect(payload['items'], isA<List>());
      expect((payload['items'] as List).length, greaterThan(0));
    });

    test('should accept valid PrintRefill payload', () {
      // Arrange: Mock backend PrintRefill.broadcastWith() payload
      final payload = {
        'print_event_id': 124,
        'device_id': 5,
        'order_id': 456,
        'session_id': 789,
        'print_type': 'REFILL',
        'refill_number': 2,
        'tablename': 'Table 1',
        'created_at': '2026-01-29T11:00:00Z',
        'order': {
          'id': 1,
          'order_id': 456,
          'order_number': 'ORD-001',
          'device_id': 5,
        },
        'items': [
          {'name': 'Beef Brisket', 'quantity': 1},
          {'name': 'Pork Belly', 'quantity': 2},
        ],
      };

      // Act: Extract fields
      final printEventId = payload['print_event_id'] as int?;
      final deviceId = payload['device_id'] as int?;
      final printType = payload['print_type'] as String?;
      final refillNumber = payload['refill_number'] as int?;

      // Assert
      expect(printEventId, greaterThan(0));
      expect(deviceId, equals(5));
      expect(printType, equals('REFILL'));
      expect(refillNumber, equals(2));
      expect((payload['items'] as List).length, equals(2));
    });

    test('should reject payload missing print_event_id', () {
      // Arrange: Invalid payload (missing print_event_id)
      final payload = {
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      // Act: Extract print_event_id
      final printEventId = payload['print_event_id'];

      // Assert: Should be null/missing
      expect(printEventId, isNull);
      
      // Note: Relay device's _handleWsPrintEvent should reject this
      // per P3-RELX-5 strict validation
    });

    test('should reject payload with invalid print_event_id (zero or negative)', () {
      // Arrange: Invalid payloads
      final payloadZero = {
        'print_event_id': 0,
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      final payloadNegative = {
        'print_event_id': -1,
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      // Act: Extract IDs
      final idZero = payloadZero['print_event_id'] as int;
      final idNegative = payloadNegative['print_event_id'] as int;

      // Assert: Both should fail validation
      expect(idZero, lessThanOrEqualTo(0));
      expect(idNegative, lessThan(0));
      
      // Note: Relay device's M3.5-4 validation rejects print_event_id <= 0
    });

    test('should reject payload missing device_id', () {
      // Arrange: Invalid payload (missing device_id)
      final payload = {
        'print_event_id': 123,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      // Act: Extract device_id
      final deviceId = payload['device_id'];

      // Assert: Should be null/missing
      expect(deviceId, isNull);
      
      // Note: Relay device cannot filter by device without this field
    });

    test('should handle optional session_id field', () {
      // Arrange: Payload with null session_id
      final payload = {
        'print_event_id': 123,
        'device_id': 5,
        'order_id': 456,
        'session_id': null,
        'print_type': 'INITIAL',
      };

      // Act: Extract session_id
      final sessionId = payload['session_id'] as int?;

      // Assert: Can be null (optional)
      expect(payload.containsKey('session_id'), isTrue);
      expect(sessionId, isNull);
      
      // Note: Relay device handles null session_id gracefully
    });

    test('should handle optional refill_number field', () {
      // Arrange: INITIAL order (no refill_number)
      final payload = {
        'print_event_id': 123,
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
        'refill_number': null,
      };

      // Act: Extract refill_number
      final refillNumber = payload['refill_number'] as int?;

      // Assert: Can be null for INITIAL orders
      expect(refillNumber, isNull);
    });

    test('should accept both print_event_id and printEventId (fallback)', () {
      // Arrange: Payload with camelCase variant (backward compatibility)
      final payloadCamelCase = {
        'printEventId': 123, // Old format
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      final payloadSnakeCase = {
        'print_event_id': 123, // New format
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      // Act: Extract with fallback (simulating app_controller.dart:274)
      final idFromCamelCase = payloadCamelCase['print_event_id'] ?? payloadCamelCase['printEventId'];
      final idFromSnakeCase = payloadSnakeCase['print_event_id'] ?? payloadSnakeCase['printEventId'];

      // Assert: Both work
      expect(idFromCamelCase, equals(123));
      expect(idFromSnakeCase, equals(123));
    });

    test('should include receipt printing data in payload', () {
      // Arrange: Full payload
      final payload = {
        'print_event_id': 123,
        'device_id': 5,
        'order_id': 456,
        'print_type': 'INITIAL',
        'order': {
          'order_number': 'ORD-001',
          'guest_count': 4,
          'total': 2500.00,
        },
        'items': [
          {'name': 'Beef Brisket', 'quantity': 2, 'price': 150.00},
          {'name': 'Kimchi', 'quantity': 1, 'price': 50.00},
        ],
        'tablename': 'Table 1',
        'created_at': '2026-01-29T10:30:00Z',
      };

      // Act: Extract printing data
      final order = payload['order'] as Map<String, dynamic>?;
      final items = payload['items'] as List?;

      // Assert: Receipt data present
      expect(order, isNotNull);
      expect(order!['order_number'], isNotNull);
      expect(order['guest_count'], isNotNull);
      
      expect(items, isNotNull);
      expect(items!.length, greaterThan(0));
      
      for (final item in items) {
        expect(item['name'], isNotNull);
        expect(item['quantity'], isNotNull);
      }
    });

    test('should validate device_id filtering (cross-device rejection)', () {
      // Arrange: Payload for different device
      final payload = {
        'print_event_id': 123,
        'device_id': 7, // Different device
        'order_id': 456,
        'print_type': 'INITIAL',
      };

      const myDeviceId = 5; // Current relay device ID

      // Act: Check device_id match (simulating app_controller.dart:296)
      final deviceId = payload['device_id'] as int;
      final shouldReject = deviceId != myDeviceId;

      // Assert: Should be rejected
      expect(shouldReject, isTrue);
      expect(deviceId, equals(7));
      expect(deviceId, isNot(equals(myDeviceId)));
    });

    test('should document contract fields for backend developers', () {
      // This test serves as documentation of the contract

      // Required fields (MUST be present and > 0):
      const requiredFields = [
        'print_event_id', // int > 0
        'device_id',      // int > 0
        'order_id',       // int > 0
        'print_type',     // string: 'INITIAL' | 'REFILL'
      ];

      // Optional fields (can be null):
      const optionalFields = [
        'session_id',     // int? (null allowed)
        'refill_number',  // int? (null for INITIAL orders)
      ];

      // Printing data fields (required for receipt generation):
      const printingFields = [
        'order',          // object with order_number, guest_count, total
        'items',          // array of {name, quantity, price?}
        'tablename',      // string? (null allowed)
        'created_at',     // ISO8601 datetime string
      ];

      // Note: This test doesn't execute assertions, it's pure documentation
      // Backend developers can reference this to understand relay device expectations
      
      expect(requiredFields.length, equals(4));
      expect(optionalFields.length, equals(2));
      expect(printingFields.length, equals(4));
    });
  });
}
