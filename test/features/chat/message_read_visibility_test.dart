import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/utils/message_read_visibility.dart';

void main() {
  group('message read visibility', () {
    test('does not read an incoming message before it is exposed', () {
      expect(
        shouldMarkMessageAsExposed(
          isIncoming: true,
          sequence: 12,
          appIsResumed: true,
          visibleFraction: 0.1,
          itemHeight: 80,
        ),
        isFalse,
      );
    });

    test('reads a normal incoming message after half is visible', () {
      expect(
        shouldMarkMessageAsExposed(
          isIncoming: true,
          sequence: 12,
          appIsResumed: true,
          visibleFraction: 0.5,
          itemHeight: 80,
        ),
        isTrue,
      );
    });

    test('reads a tall incoming message after 48 visible pixels', () {
      expect(
        shouldMarkMessageAsExposed(
          isIncoming: true,
          sequence: 12,
          appIsResumed: true,
          visibleFraction: 0.12,
          itemHeight: 400,
        ),
        isTrue,
      );
    });

    test('never derives read state from outgoing or background rows', () {
      expect(
        shouldMarkMessageAsExposed(
          isIncoming: false,
          sequence: 12,
          appIsResumed: true,
          visibleFraction: 1,
          itemHeight: 80,
        ),
        isFalse,
      );
      expect(
        shouldMarkMessageAsExposed(
          isIncoming: true,
          sequence: 12,
          appIsResumed: false,
          visibleFraction: 1,
          itemHeight: 80,
        ),
        isFalse,
      );
    });
  });
}
