import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/system_settings_service.dart';
import 'package:customer/features/chat/pages/qr_scanner_page.dart';

void main() {
  group('QR scanner friend add policy', () {
    test('uses friend request flow when approval is required', () {
      expect(
        scanFriendAddActionForMode(FriendAddMode.approval),
        ScanFriendAddAction.request,
      );
    });

    test('keeps direct and disabled modes distinct', () {
      expect(
        scanFriendAddActionForMode(FriendAddMode.direct),
        ScanFriendAddAction.direct,
      );
      expect(
        scanFriendAddActionForMode(FriendAddMode.disabled),
        ScanFriendAddAction.disabled,
      );
    });
  });
}
