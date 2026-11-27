import 'package:customer/core/services/desktop/desktop_instance_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopInstanceService profile isolation', () {
    test('keeps the default profile on the existing storage keys', () {
      expect(
        DesktopInstanceService.storageKeyFor('default', 'auth_token'),
        'auth_token',
      );
      expect(
        DesktopInstanceService.databaseDirectoryFor(
          'default',
          r'C:\Users\me\Documents',
          r'\',
        ),
        r'C:\Users\me\Documents',
      );
    });

    test('gives an additional profile its own keys and database directory', () {
      expect(
        DesktopInstanceService.storageKeyFor('instance_abc', 'auth_token'),
        'auth_token__profile_instance_abc',
      );
      expect(
        DesktopInstanceService.databaseDirectoryFor(
          'instance_abc',
          r'C:\Users\me\Documents',
          r'\',
        ),
        r'C:\Users\me\Documents\profiles\instance_abc',
      );
    });

    test('normalizes profile ids and rejects the default name', () {
      expect(DesktopInstanceService.normalizeProfileId(null), isNull);
      expect(DesktopInstanceService.normalizeProfileId(' default '), isNull);
      expect(
        DesktopInstanceService.normalizeProfileId('room 1'),
        'room_1',
      );
      expect(
        DesktopInstanceService.normalizeProfileId('a' * 60)!.length,
        48,
      );
    });

    test('creates a profile id the Windows launcher can pass through', () {
      expect(
        DesktopInstanceService.createProfileId(36),
        'instance_10',
      );
    });
  });
}
