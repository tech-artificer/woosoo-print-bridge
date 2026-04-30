import '../../core/constants.dart';

class ReceiptBuilder58mm {
  final int width;
  ReceiptBuilder58mm({this.width = AppConstants.receiptCharsPerLine});

  List<String> build(Map<String, dynamic> payload) {
    final lines = <String>[];

    final tablename = (payload['tablename'] ?? '').toString();
    final orderNumber =
        (payload['order_number'] ?? payload['orderNumber'] ?? '').toString();
    final guestCount = payload['guest_count'] ?? payload['guestCount'];
    final createdAtRaw = payload['created_at'] ?? payload['createdAt'];
    final createdAt =
        createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;
    final printType =
        (payload['print_type'] ?? payload['printType'] ?? 'INITIAL')
            .toString()
            .toUpperCase();
    final isRefill = printType == 'REFILL';

    final items = (payload['items'] as List?) ?? const [];

    // Initial order payloads include the package as the first item.
    // Refill payloads only include refill items, so do not skip the first item.
    final packageItem = items.isNotEmpty ? items.first : null;
    final packageName = packageItem != null
        ? (Map<String, dynamic>.from(packageItem as Map)['name'] ??
                'Unknown Package')
            .toString()
        : 'Unknown Package';

    // Format date and time for same-line display
    final dateStr = createdAt?.toLocal().toString().split(' ').first ??
        DateTime.now().toLocal().toString().split(' ').first;
    final timeStr = createdAt != null
        ? _formatTime12Hour(createdAt)
        : _formatTime12Hour(DateTime.now());

    // HEADER: DINE IN centered with === borders
    lines.add('');
    lines.add(_equals());
    lines.add(_center(isRefill ? 'REFILL' : 'DINE IN'));
    lines.add('');

    // DATE AND TIME on same line with spacing
    final dateTimeCount =
        dateStr.length + timeStr.length + 4; // 4 for spacing/padding
    final spacesNeeded = width - dateTimeCount;
    lines.add(
        '$dateStr    ${' ' * (spacesNeeded > 0 ? spacesNeeded : 0)}$timeStr');

    lines.add(_equals());

    if (!isRefill) {
      lines.add('Package: $packageName');
    }

    // META: Table and Guests
    if (tablename.isNotEmpty) lines.add('Table: $tablename');
    if (guestCount != null) lines.add('Guests: $guestCount');

    lines.add(_hr());

    final itemsToDisplay =
        isRefill ? items : (items.length > 1 ? items.sublist(1) : <dynamic>[]);

    if (itemsToDisplay.isEmpty && items.isEmpty) {
      lines.add('(No items)');
    } else {
      for (final it in itemsToDisplay) {
        final m = Map<String, dynamic>.from(it as Map);
        final name = (m['name'] ?? '').toString();
        final qty = (m['quantity'] ?? 1).toString();

        // Format: {qty} {name}
        lines.add('$qty $name');
      }
    }

    lines.add('');

    // FOOTER: Order ID with *** borders
    lines.add(_stars());
    if (orderNumber.isNotEmpty) {
      lines.add(_center('Order #: $orderNumber'));
    }
    lines.add(_stars());
    lines.add('');
    lines.add('');
    lines.add('');

    return lines;
  }

  /// Format DateTime to 12-hour format: "h:mm A"
  String _formatTime12Hour(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:$minute $period';
  }

  String _center(String s) {
    s = s.trim();
    if (s.length >= width) return s.substring(0, width);
    final left = ((width - s.length) / 2).floor();
    return ' ' * left + s;
  }

  String _hr() => '-' * width;

  String _equals() => '=' * width;

  String _stars() => '*' * width;
}
