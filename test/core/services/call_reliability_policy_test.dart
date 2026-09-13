import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/call_service.dart';

void main() {
  test('reconnect countdown rounds up and reaches zero at deadline', () {
    final deadline = DateTime.utc(2026, 7, 16, 12, 0, 20);

    expect(
      callReconnectSecondsRemaining(
        deadline,
        DateTime.utc(2026, 7, 16, 12, 0, 0, 1),
      ),
      20,
    );
    expect(
      callReconnectSecondsRemaining(
        deadline,
        DateTime.utc(2026, 7, 16, 12, 0, 19, 999),
      ),
      1,
    );
    expect(callReconnectSecondsRemaining(deadline, deadline), 0);
  });

  test('only camera denial offers voice downgrade', () {
    expect(
      callPermissionSupportsVoiceFallback(CallPermissionIssue.cameraDenied),
      isTrue,
    );
    expect(
      callPermissionSupportsVoiceFallback(
        CallPermissionIssue.cameraPermanentlyDenied,
      ),
      isTrue,
    );
    expect(
      callPermissionSupportsVoiceFallback(
        CallPermissionIssue.microphoneDenied,
      ),
      isFalse,
    );
  });

  test('only permanent permission denial offers settings', () {
    expect(
      callPermissionCanOpenSettings(
        CallPermissionIssue.microphonePermanentlyDenied,
      ),
      isTrue,
    );
    expect(
      callPermissionCanOpenSettings(
        CallPermissionIssue.cameraPermanentlyDenied,
      ),
      isTrue,
    );
    expect(
      callPermissionCanOpenSettings(CallPermissionIssue.microphoneDenied),
      isFalse,
    );
    expect(
      callPermissionCanOpenSettings(CallPermissionIssue.cameraDenied),
      isFalse,
    );
  });

  test('elapsed call time is based on server connection time', () {
    final now = DateTime.utc(2026, 7, 16, 12, 5);
    expect(
      callElapsedSeconds(now.subtract(const Duration(minutes: 2)), now),
      120,
    );
    expect(callElapsedSeconds(now.add(const Duration(seconds: 3)), now), 0);
    expect(callElapsedSeconds(null, now), 0);
  });

  test('server clock offset removes local wall clock skew', () {
    final requestStarted = DateTime.utc(2026, 8, 7, 12, 0, 0);
    final responseReceived =
        requestStarted.add(const Duration(milliseconds: 200));
    final serverAtMidpoint = DateTime.utc(2026, 8, 7, 12, 0, 2, 100);
    final offset = estimateServerClockOffset(
      serverTime: serverAtMidpoint,
      localRequestStarted: requestStarted,
      localResponseReceived: responseReceived,
    );

    expect(offset, const Duration(seconds: 2));
    expect(
      callElapsedSecondsWithClockOffset(
        DateTime.utc(2026, 8, 7, 11, 59, 57),
        DateTime.utc(2026, 8, 7, 12, 0, 0),
        offset,
      ),
      5,
    );
  });

  test('expired incoming call payload is rejected', () {
    final now = DateTime.utc(2026, 7, 16, 12, 0, 30);
    expect(incomingCallIsExpired('2026-07-16T12:00:29Z', now), isTrue);
    expect(incomingCallIsExpired('2026-07-16T12:00:31Z', now), isFalse);
    expect(incomingCallIsExpired('1784203229', now), isTrue);
    expect(incomingCallIsExpired('1784203231000', now), isFalse);
    expect(incomingCallIsExpired(null, now), isFalse);
  });

  test('outgoing preparation and failure keep the call page lifecycle active',
      () {
    final provisionalInfo = CallInfo(
      channelName: '',
      remoteUserId: 'user-b',
      remoteName: 'User B',
      type: CallType.video,
      isOutgoing: true,
    );

    expect(
      CallServiceState(
        state: CallState.preparing,
        callInfo: provisionalInfo,
      ).isInCall,
      isTrue,
    );
    expect(
      CallServiceState(
        state: CallState.failed,
        callInfo: provisionalInfo,
        errorMessage: 'network unavailable',
      ).isInCall,
      isTrue,
    );
    expect(const CallServiceState().isInCall, isFalse);
  });

  test('terminal events require the exact non-null call id', () {
    expect(
      callEventMatchesCurrentCall(currentCallId: 42, eventCallId: 42),
      isTrue,
    );
    expect(
      callEventMatchesCurrentCall(currentCallId: 42, eventCallId: 41),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(currentCallId: 42, eventCallId: null),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(currentCallId: null, eventCallId: 42),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(currentCallId: 0, eventCallId: 0),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(
        currentCallId: 42,
        eventCallId: 42,
        currentSessionId: 'new-session',
        eventSessionId: 'old-session',
      ),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(
        currentCallId: 42,
        eventCallId: 42,
        currentSessionId: 'new-session',
        eventSessionId: null,
      ),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(
        currentCallId: 42,
        eventCallId: 42,
        currentSessionId: 'new-session',
        eventSessionId: 'new-session',
        currentRevision: 7,
        eventRevision: 6,
      ),
      isFalse,
    );
    expect(
      callEventMatchesCurrentCall(
        currentCallId: 42,
        eventCallId: 42,
        currentSessionId: 'new-session',
        eventSessionId: 'new-session',
        currentRevision: 7,
        eventRevision: 8,
      ),
      isTrue,
    );
  });

  test('stale CallKit accept is ignored for the active call session', () {
    expect(
      callKitAcceptIsActiveReplay(
        currentState: CallState.connected,
        currentCallId: 368,
        eventCallId: 368,
        currentSessionId: 'session-368',
        eventSessionId: 'session-368',
      ),
      isTrue,
    );
    expect(
      callKitAcceptIsActiveReplay(
        currentState: CallState.connecting,
        currentCallId: 368,
        eventCallId: 368,
        currentSessionId: 'session-368',
        eventSessionId: 'session-368',
      ),
      isTrue,
    );
  });

  test('CallKit accept replay cannot suppress a rapid redial', () {
    expect(
      callKitAcceptIsActiveReplay(
        currentState: CallState.connected,
        currentCallId: 369,
        eventCallId: 368,
        currentSessionId: 'new-session',
        eventSessionId: 'old-session',
      ),
      isFalse,
    );
    expect(
      callKitAcceptIsActiveReplay(
        currentState: CallState.incoming,
        currentCallId: 368,
        eventCallId: 368,
        currentSessionId: 'session-368',
        eventSessionId: 'session-368',
      ),
      isFalse,
    );
  });

  test('active callee ringing snapshot restores an incoming call', () {
    final payload = incomingCallPayloadFromActiveSnapshot(
      <String, dynamic>{
        'active': true,
        'status': 'calling',
        'role': 'callee',
        'call_id': 91,
        'session_id': 'session-91',
        'revision': 1,
        'call_type': 'voice',
        'channel_name': 'channel-91',
        'provider': 'agora',
        'remote_id': 'caller-uuid',
        'remote_name': 'Caller',
        'expires_at': '2026-08-07T12:00:30Z',
      },
      now: DateTime.parse('2026-08-07T12:00:10Z'),
    );

    expect(payload, isNotNull);
    expect(payload!['caller_id'], 'caller-uuid');
    expect(payload['call_id'], 91);
    expect(payload['session_id'], 'session-91');
  });

  test('expired or non-callee active snapshot is not restored', () {
    final base = <String, dynamic>{
      'active': true,
      'status': 'calling',
      'role': 'callee',
      'call_id': 92,
      'channel_name': 'channel-92',
      'remote_id': 'caller-uuid',
      'remote_name': 'Caller',
      'expires_at': '2026-08-07T12:00:30Z',
    };
    expect(
      incomingCallPayloadFromActiveSnapshot(
        base,
        now: DateTime.parse('2026-08-07T12:00:31Z'),
      ),
      isNull,
    );
    expect(
      incomingCallPayloadFromActiveSnapshot(
        <String, dynamic>{...base, 'role': 'caller'},
        now: DateTime.parse('2026-08-07T12:00:10Z'),
      ),
      isNull,
    );
  });

  test('iOS CallKit UUID is deterministic and session isolated', () {
    final first = stableIosCallKitUuid(42, sessionId: 'session-a');
    final replay = stableIosCallKitUuid(42, sessionId: 'session-a');
    final rapidRedial = stableIosCallKitUuid(42, sessionId: 'session-b');

    expect(first, replay);
    expect(first, isNot(rapidRedial));
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(first),
      isTrue,
    );
  });

  test('stale local call cannot reject a server-authoritative new call', () {
    expect(
      serverConfirmsExistingCallBeforeBusy(
        localCallId: 10,
        incomingCallId: 11,
        serverActive: true,
        serverCallId: 11,
      ),
      isFalse,
    );
    expect(
      serverConfirmsExistingCallBeforeBusy(
        localCallId: 10,
        incomingCallId: 11,
        serverActive: false,
        serverCallId: null,
      ),
      isFalse,
    );
  });

  test('busy is sent only when the server confirms the old local call', () {
    expect(
      serverConfirmsExistingCallBeforeBusy(
        localCallId: 10,
        incomingCallId: 11,
        serverActive: true,
        serverCallId: 10,
      ),
      isTrue,
    );
  });
}
