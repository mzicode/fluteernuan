import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/android_notification_settings_service.dart';

void main() {
  test('background restriction status reports either restriction source', () {
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': false,
        'background_restricted': false,
      }).needsAttention,
      isTrue,
    );
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': true,
        'background_restricted': true,
      }).needsAttention,
      isTrue,
    );
    expect(
      AndroidBackgroundRestrictionStatus.fromMap({
        'ignoring_battery_optimizations': true,
        'background_restricted': false,
      }).needsAttention,
      isFalse,
    );
  });

  test('incoming call permissions only require Xiaomi guide when incomplete',
      () {
    final complete = AndroidIncomingCallPermissionStatus.fromMap({
      'notification_granted': true,
      'full_screen_intent_granted': true,
      'is_xiaomi': true,
      'xiaomi_background_popup_granted': true,
      'xiaomi_lock_screen_granted': true,
    });
    expect(complete.needsXiaomiPermissionGuide, isFalse);

    final incomplete = AndroidIncomingCallPermissionStatus.fromMap({
      'notification_granted': true,
      'full_screen_intent_granted': true,
      'is_xiaomi': true,
      'xiaomi_background_popup_granted': false,
      'xiaomi_lock_screen_granted': true,
    });
    expect(incomplete.needsXiaomiPermissionGuide, isTrue);

    final otherAndroid = AndroidIncomingCallPermissionStatus.fromMap({
      'notification_granted': true,
      'full_screen_intent_granted': true,
      'is_xiaomi': false,
    });
    expect(otherAndroid.needsXiaomiPermissionGuide, isFalse);
    expect(otherAndroid.needsVendorPermissionGuide, isFalse);
    expect(complete.needsVendorPermissionGuide, isFalse);
    expect(incomplete.needsVendorPermissionGuide, isTrue);
    for (final vendor in ['oppo', 'realme', 'oneplus', 'vivo', 'iqoo', 'huawei', 'honor']) {
      final status = AndroidIncomingCallPermissionStatus.fromMap({
        'notification_granted': true,
        'full_screen_intent_granted': true,
        'vendor': vendor,
      });
      expect(status.needsVendorPermissionGuide, isTrue, reason: vendor);
    }
  });
}
