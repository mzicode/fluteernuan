import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer/core/services/call_terminal_outbox.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('terminal action survives a new outbox instance', () async {
    final now = DateTime.utc(2026, 8, 7, 1);
    final action = CallTerminalAction(
      ownerUserId: 'alice',
      callId: 77,
      sessionId: 'session-77',
      action: 'end',
      reason: 'hangup',
      createdAt: now,
    );
    await CallTerminalOutbox().enqueue(action);

    final restored = await CallTerminalOutbox().loadForOwner(
      'alice',
      now: now.add(const Duration(minutes: 1)),
    );
    expect(restored, hasLength(1));
    expect(restored.single.callId, 77);
    expect(restored.single.sessionId, 'session-77');
  });

  test('actions are isolated by account and removed by call session', () async {
    final outbox = CallTerminalOutbox();
    final alice = CallTerminalAction(
      ownerUserId: 'alice',
      callId: 1,
      sessionId: 'alice-session',
      action: 'cancel',
      reason: 'cancelled',
      createdAt: DateTime.now().toUtc(),
    );
    final bob = CallTerminalAction(
      ownerUserId: 'bob',
      callId: 2,
      sessionId: 'bob-session',
      action: 'reject',
      reason: 'busy',
      createdAt: DateTime.now().toUtc(),
    );
    await outbox.enqueue(alice);
    await outbox.enqueue(bob);

    expect(await outbox.loadForOwner('alice'), hasLength(1));
    expect(await outbox.loadForOwner('bob'), hasLength(1));
    await outbox.remove(alice);
    expect(await outbox.loadForOwner('alice'), isEmpty);
    expect(await outbox.loadForOwner('bob'), hasLength(1));
  });

  test('latest terminal intent replaces the same immutable call session',
      () async {
    final outbox = CallTerminalOutbox();
    final started = DateTime.now().toUtc();
    await outbox.enqueue(CallTerminalAction(
      ownerUserId: 'alice',
      callId: 3,
      sessionId: 'session-3',
      action: 'cancel',
      reason: 'cancelled',
      createdAt: started,
    ));
    await outbox.enqueue(CallTerminalAction(
      ownerUserId: 'alice',
      callId: 3,
      sessionId: 'session-3',
      action: 'end',
      reason: 'hangup',
      createdAt: started.add(const Duration(milliseconds: 1)),
    ));

    final pending = await outbox.loadForOwner('alice');
    expect(pending, hasLength(1));
    expect(pending.single.action, 'end');
  });

  test('removing an account does not touch another account', () async {
    final outbox = CallTerminalOutbox();
    final createdAt = DateTime.now().toUtc();
    for (final owner in <String>['alice', 'bob']) {
      await outbox.enqueue(CallTerminalAction(
        ownerUserId: owner,
        callId: owner == 'alice' ? 10 : 11,
        sessionId: '$owner-session',
        action: 'end',
        reason: 'hangup',
        createdAt: createdAt,
      ));
    }

    await outbox.removeOwner('alice');
    expect(await outbox.loadForOwner('alice'), isEmpty);
    expect(await outbox.loadForOwner('bob'), hasLength(1));
  });
}
