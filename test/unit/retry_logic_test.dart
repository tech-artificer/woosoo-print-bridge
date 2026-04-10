import 'package:flutter_test/flutter_test.dart';

import 'package:woosoo_relay_device/core/constants.dart';

/// Retry backoff logic extracted for unit testing.
/// The _retry() method in ApiService uses: delay = Duration(seconds: 1 << (attempt - 1))
/// i.e., attempt 1 → 1s, attempt 2 → 2s, attempt 3 → 4s
int _backoffSeconds(int attempt) => 1 << (attempt - 1);

void main() {
  group('Retry backoff — exponential schedule', () {
    test('attempt 1 → 1 second delay', () {
      expect(_backoffSeconds(1), 1);
    });

    test('attempt 2 → 2 second delay', () {
      expect(_backoffSeconds(2), 2);
    });

    test('attempt 3 → 4 second delay', () {
      expect(_backoffSeconds(3), 4);
    });

    test('attempt 4 → 8 second delay', () {
      expect(_backoffSeconds(4), 8);
    });

    test('backoff doubles on every attempt', () {
      int prev = _backoffSeconds(1);
      for (int i = 2; i <= AppConstants.maxApiRetries; i++) {
        final curr = _backoffSeconds(i);
        expect(curr, prev * 2, reason: 'Attempt $i should be double attempt ${i - 1}');
        prev = curr;
      }
    });
  });

  group('Max retries constant', () {
    test('maxApiRetries is 3', () {
      expect(AppConstants.maxApiRetries, 3);
    });

    test('maxPrintAttempts is 3', () {
      expect(AppConstants.maxPrintAttempts, 3);
    });
  });

  group('Trusted local hosts', () {
    test('Pi IP is trusted', () {
      expect(AppConstants.trustedLocalHosts.contains('192.168.100.7'), isTrue);
    });

    test('woosoo.local is trusted', () {
      expect(AppConstants.trustedLocalHosts.contains('woosoo.local'), isTrue);
    });

    test('api.woosoo.local is trusted', () {
      expect(AppConstants.trustedLocalHosts.contains('api.woosoo.local'), isTrue);
    });

    test('external host is NOT trusted', () {
      expect(AppConstants.trustedLocalHosts.contains('google.com'), isFalse);
      expect(AppConstants.trustedLocalHosts.contains('192.168.1.1'), isFalse);
      expect(AppConstants.trustedLocalHosts.contains(''), isFalse);
    });
  });

  group('WS URL derivation', () {
    test('https base produces wss ws URL', () {
      final url = AppConstants.deriveWsUrl('https://192.168.100.7:8443');
      expect(url, startsWith('wss://'));
    });

    test('http base produces ws ws URL', () {
      final url = AppConstants.deriveWsUrl('http://192.168.100.7:8080');
      expect(url, startsWith('ws://'));
    });

    test('derived URL contains /app/ segment', () {
      final url = AppConstants.deriveWsUrl('https://192.168.100.7:8443', appKey: 'testkey123');
      expect(url, contains('/app/testkey123'));
    });

    test('port is preserved in derived URL', () {
      final url = AppConstants.deriveWsUrl('https://192.168.100.7:8443');
      expect(url, contains(':8443'));
    });
  });
}
