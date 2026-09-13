import 'package:flutter_test/flutter_test.dart';
import 'package:customer/shared/widgets/mini_app_navigation_policy.dart';

void main() {
  group('MiniAppNavigationPolicy', () {
    const allowed = <String>['mini.example.com', 'api.example.com'];

    test('allows only exact approved HTTPS origins', () {
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://mini.example.com/path?next=1',
          allowed,
        ).allowed,
        isTrue,
      );
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://api.example.com/v1',
          allowed,
        ).allowed,
        isTrue,
      );
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://evil.mini.example.com',
          allowed,
        ).reason,
        MiniAppNavigationBlockReason.domainNotAllowed,
      );
    });

    test('blocks insecure schemes credentials and non-default ports', () {
      expect(
        MiniAppNavigationPolicy.evaluate(
          'http://mini.example.com',
          allowed,
        ).reason,
        MiniAppNavigationBlockReason.insecureScheme,
      );
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://user:pass@mini.example.com',
          allowed,
        ).reason,
        MiniAppNavigationBlockReason.credentialsInUrl,
      );
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://mini.example.com:8443',
          allowed,
        ).reason,
        MiniAppNavigationBlockReason.disallowedPort,
      );
      for (final value in <String>[
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,hello',
        'intent://scan',
      ]) {
        expect(
          MiniAppNavigationPolicy.evaluate(value, allowed).allowed,
          isFalse,
          reason: value,
        );
      }
    });

    test('blocks local names and private address ranges', () {
      for (final value in <String>[
        'https://localhost',
        'https://router.local',
        'https://service.internal',
        'https://127.0.0.1',
        'https://10.0.0.1',
        'https://172.16.1.1',
        'https://192.168.1.1',
        'https://169.254.169.254',
        'https://[::1]',
        'https://[fc00::1]',
      ]) {
        final uri = Uri.parse(value);
        expect(
          MiniAppNavigationPolicy.evaluate(value, <String>[uri.host]).allowed,
          isFalse,
          reason: value,
        );
      }
    });

    test('accepts public literal addresses only when explicitly approved', () {
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://8.8.8.8/',
          const <String>['8.8.8.8'],
        ).allowed,
        isTrue,
      );
      expect(
        MiniAppNavigationPolicy.evaluate(
          'https://8.8.8.8/',
          const <String>['1.1.1.1'],
        ).allowed,
        isFalse,
      );
    });
  });
}
