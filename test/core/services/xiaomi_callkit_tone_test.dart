import 'dart:async';

import 'package:customer/core/services/android_callkit_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_callkit_incoming');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<dynamic> active;
  late bool current;

  Map<String, dynamic> call(String id,
          {int callId = 305, String session = 's1'}) =>
      {
        'id': id,
        'extra': {'call_id': callId, 'session_id': session},
      };

  Future<void> stop({bool xiaomi = true}) => stopXiaomiIncomingCallkitTone(
        callId: 305,
        sessionId: 's1',
        isCurrentCall: () => current,
        isXiaomiDevice: () async => xiaomi,
      );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    active = [call('call-305')];
    current = true;
    messenger.setMockMethodCallHandler(channel, (method) async {
      calls.add(method);
      if (method.method == 'activeCalls') return active;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Xiaomi hides both same-call IDs without ending any call', () async {
    active.add(call('call-305-s1'));
    await stop();
    expect(calls.map((c) => c.method), [
      'activeCalls',
      'hideCallkitIncoming',
      'hideCallkitIncoming',
    ]);
    expect(calls.skip(1).map((c) => c.arguments['id']),
        ['call-305', 'call-305-s1']);
  });

  test('other manufacturers do not invoke CallKit', () async {
    await stop(xiaomi: false);
    expect(calls, isEmpty);
  });

  test('iOS does not invoke device lookup or CallKit', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await stopXiaomiIncomingCallkitTone(
      callId: 305,
      sessionId: 's1',
      isCurrentCall: () => true,
      isXiaomiDevice: () => throw StateError('must not look up iOS'),
    );
    expect(calls, isEmpty);
  });

  test('other call or newer session prevents shared player cleanup', () async {
    for (final other in [
      call('other', callId: 306),
      call('new', session: 's2')
    ]) {
      calls.clear();
      active = [call('call-305'), other];
      await stop();
      expect(calls.map((c) => c.method), ['activeCalls']);
    }
  });

  test('stale local call after native lookup is not hidden', () async {
    messenger.setMockMethodCallHandler(channel, (method) async {
      calls.add(method);
      current = false;
      return active;
    });
    await stop();
    expect(calls.map((c) => c.method), ['activeCalls']);
  });

  test('cleanup waits for native hide completion', () async {
    final hidden = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (method) async {
      calls.add(method);
      if (method.method == 'activeCalls') return active;
      await hidden.future;
      return null;
    });
    var completed = false;
    final pending = stop().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'hideCallkitIncoming');
    expect(completed, isFalse);
    hidden.complete();
    await pending;
    expect(completed, isTrue);
  });

  test('missing or malformed active calls do not stop the shared player',
      () async {
    for (final entries in <List<dynamic>>[
      [],
      [{}],
      [call('')]
    ]) {
      calls.clear();
      active = entries;
      await stop();
      expect(calls.map((c) => c.method), ['activeCalls']);
    }
  });

  test('platform failure does not block accepting or ending a call', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await expectLater(stop(), completes);
  });
}
