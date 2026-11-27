import 'package:customer/core/services/api/nertc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNertcExpiresAt', () {
    test('parses unix seconds from int', () {
      final at = parseNertcExpiresAt(1700000000);
      expect(at, isNotNull);
      expect(at!.isUtc, isTrue);
      expect(at.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('treats 0 as missing', () {
      expect(parseNertcExpiresAt(0), isNull);
      expect(parseNertcExpiresAt('0'), isNull);
    });

    test('parses unix seconds from decimal string', () {
      final at = parseNertcExpiresAt('1700000000');
      expect(at?.millisecondsSinceEpoch, 1700000000 * 1000);
    });
  });

  group('mapNertcConsent409', () {
    test('lock reason becomes tryToken', () {
      expect(
        mapNertcConsent409('existing_call_provider_locked'),
        NertcConsentStatus.tryToken,
      );
    });

    test('terminal reason becomes aborted', () {
      expect(
        mapNertcConsent409('call_terminal_or_invalid_state'),
        NertcConsentStatus.aborted,
      );
    });

    test('generic or empty 409 keeps waiting', () {
      expect(mapNertcConsent409('请求失败'), NertcConsentStatus.waiting);
      expect(mapNertcConsent409(''), NertcConsentStatus.waiting);
      expect(mapNertcConsent409('Request failed.'), NertcConsentStatus.waiting);
    });
  });

  group('NertcSession.sdkUid', () {
    test('accepts decimal string in int64 range', () {
      const session = NertcSession(
        appKey: 'abcdefghijklmnopqrstuvwxyz012345',
        channelName: 'ch',
        sessionId: 's',
        callId: '1',
        uid: '9223372036854775807',
        token: 't',
        expiresAt: null,
      );
      expect(session.sdkUid, 9223372036854775807);
    });

    test('rejects zero and non-decimal', () {
      expect(
        () => const NertcSession(
          appKey: 'k',
          channelName: 'ch',
          sessionId: 's',
          callId: '1',
          uid: '0',
          token: 't',
          expiresAt: null,
        ).sdkUid,
        throwsFormatException,
      );
    });
  });
}
