import 'package:customer/core/utils/sms_registration_settings_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps last valid settings out of the loader and skips invalid JSON',
      () async {
    final calls = <Uri>[];
    final settings = await loadSmsRegistrationBridgeSettings(
      nowMs: 1,
      getter: (uri) async {
        calls.add(uri);
        if (calls.length == 1) {
          return {
            'sms_bind_ready': 'true',
            'sms_registration_required': true,
          };
        }
        return {
          'sms_bind_ready': true,
          'sms_registration_required': true,
        };
      },
    );

    expect(settings, isNotNull);
    expect(settings!.showSmsCode, isTrue);
    expect(calls.length, greaterThanOrEqualTo(2));
  });

  test('returns null when every origin fails or is invalid', () async {
    final settings = await loadSmsRegistrationBridgeSettings(
      getter: (_) async => {'sms_bind_ready': true},
    );
    expect(settings, isNull);
  });
}
