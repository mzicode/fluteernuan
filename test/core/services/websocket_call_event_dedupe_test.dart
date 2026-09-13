import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/websocket_service.dart';

void main() {
  test('call event id is dispatched at most once', () {
    final deduplicator = CallRealtimeEventDeduplicator();
    final event = <String, dynamic>{
      'type': WSMessageType.callEnded,
      'event_id': 'event-1',
      'data': <String, dynamic>{'call_id': 7},
    };

    expect(deduplicator.shouldDispatch(WSMessageType.callEnded, event), isTrue);
    expect(
      deduplicator.shouldDispatch(WSMessageType.callEnded, event),
      isFalse,
    );
  });

  test('nested event id and bounded eviction are supported', () {
    final deduplicator = CallRealtimeEventDeduplicator(capacity: 2);
    Map<String, dynamic> event(String id) => <String, dynamic>{
          'data': <String, dynamic>{'event_id': id},
        };

    expect(
      deduplicator.shouldDispatch(WSMessageType.incomingCall, event('a')),
      isTrue,
    );
    expect(
      deduplicator.shouldDispatch(WSMessageType.callAccepted, event('b')),
      isTrue,
    );
    expect(
      deduplicator.shouldDispatch(WSMessageType.callEnded, event('c')),
      isTrue,
    );
    expect(
      deduplicator.shouldDispatch(WSMessageType.incomingCall, event('a')),
      isTrue,
    );
  });

  test('legacy call events and non-call events remain dispatchable', () {
    final deduplicator = CallRealtimeEventDeduplicator();
    expect(
      deduplicator.shouldDispatch(
        WSMessageType.callEnded,
        <String, dynamic>{
          'data': <String, dynamic>{'call_id': 7}
        },
      ),
      isTrue,
    );
    final message = <String, dynamic>{'event_id': 'shared'};
    expect(
        deduplicator.shouldDispatch(WSMessageType.newMessage, message), isTrue);
    expect(
        deduplicator.shouldDispatch(WSMessageType.newMessage, message), isTrue);
  });
}
