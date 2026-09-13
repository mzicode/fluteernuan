import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:customer/shared/widgets/mini_app_bridge_protocol.dart';

void main() {
  test('parses an allowlisted bridge request', () {
    final request = MiniAppBridgeRequest.tryParse(jsonEncode({
      'request_id': 'request-1',
      'bridge_nonce': 'a' * 43,
      'method': 'setMainButton',
      'params': {'text': 'Pay', 'visible': true},
    }));
    expect(request, isNotNull);
    expect(request!.requestId, 'request-1');
    expect(request.bridgeNonce, 'a' * 43);
    expect(request.method, 'setMainButton');
    expect(request.params['visible'], isTrue);
  });

  test('rejects unknown malformed and oversized bridge messages', () {
    expect(
      MiniAppBridgeRequest.tryParse(
        '{"request_id":"1","bridge_nonce":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","method":"readContacts"}',
      ),
      isNull,
    );
    expect(MiniAppBridgeRequest.tryParse('not-json'), isNull);
    expect(
      MiniAppBridgeRequest.tryParse(
        '{"request_id":"1","method":"ready","params":{}}',
      ),
      isNull,
    );
    expect(
      MiniAppBridgeRequest.tryParse(jsonEncode({
        'request_id': '1',
        'bridge_nonce': 'a' * 43,
        'method': 'share',
        'params': {'text': 'x' * MiniAppBridgeRequest.maxMessageBytes},
      })),
      isNull,
    );
  });
}
