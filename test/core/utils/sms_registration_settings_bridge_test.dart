import 'package:customer/core/utils/sms_registration_settings_bridge_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsRegistrationBridgeSettings.tryParse', () {
    test('accepts strict JSON booleans', () {
      final settings = SmsRegistrationBridgeSettings.tryParse(const {
        'sms_bind_ready': true,
        'sms_registration_required': true,
        'generated_at': '2026-09-17T11:12:42Z',
      });

      expect(settings, isNotNull);
      expect(settings!.smsBindReady, isTrue);
      expect(settings.smsRegistrationRequired, isTrue);
      expect(settings.showSmsCode, isTrue);
      expect(settings.generatedAt, '2026-09-17T11:12:42Z');
    });

    test('hides SMS code unless both flags are true', () {
      expect(
        SmsRegistrationBridgeSettings.tryParse(const {
          'sms_bind_ready': true,
          'sms_registration_required': false,
        })!.showSmsCode,
        isFalse,
      );
      expect(
        SmsRegistrationBridgeSettings.tryParse(const {
          'sms_bind_ready': false,
          'sms_registration_required': true,
        })!.showSmsCode,
        isFalse,
      );
    });

    test('rejects string, numeric, and missing fields', () {
      expect(
        SmsRegistrationBridgeSettings.tryParse(const {
          'sms_bind_ready': 'true',
          'sms_registration_required': true,
        }),
        isNull,
      );
      expect(
        SmsRegistrationBridgeSettings.tryParse(const {
          'sms_bind_ready': 1,
          'sms_registration_required': true,
        }),
        isNull,
      );
      expect(
        SmsRegistrationBridgeSettings.tryParse(const {
          'sms_bind_ready': true,
        }),
        isNull,
      );
      expect(SmsRegistrationBridgeSettings.tryParse(null), isNull);
    });
  });

  group('smsRegistrationSettingsBridgeUris', () {
    test('puts the preferred origin first and appends cache-busting t', () {
      final uris = smsRegistrationSettingsBridgeUris(
        preferredOrigin: 'https://web.ojyvn.com/api/v1',
        nowMs: 1726560000000,
      );

      expect(uris.first.toString(),
          'https://web.ojyvn.com/sms-registration-settings.json?t=1726560000000');
      expect(
        uris.map((uri) => uri.origin).toSet(),
        containsAll([
          'https://web.cybndo.com',
          'https://web.ojyvn.com',
          'https://web.iexici.cn',
        ]),
      );
    });
  });
}
