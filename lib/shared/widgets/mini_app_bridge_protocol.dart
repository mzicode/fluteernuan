import 'dart:convert';

class MiniAppBridgeRequest {
  static const int maxMessageBytes = 16 * 1024;
  static const Set<String> supportedMethods = {
    'ready',
    'close',
    'back',
    'setTitle',
    'setMainButton',
    'share',
    'openLink',
    'hapticFeedback',
    'getTheme',
  };

  final String requestId;
  final String bridgeNonce;
  final String method;
  final Map<String, dynamic> params;

  const MiniAppBridgeRequest({
    required this.requestId,
    required this.bridgeNonce,
    required this.method,
    required this.params,
  });

  static MiniAppBridgeRequest? tryParse(String raw) {
    if (utf8.encode(raw).length > maxMessageBytes) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final requestId = decoded['request_id']?.toString().trim() ?? '';
      final bridgeNonce = decoded['bridge_nonce']?.toString().trim() ?? '';
      final method = decoded['method']?.toString().trim() ?? '';
      if (requestId.isEmpty ||
          requestId.length > 80 ||
          bridgeNonce.length < 32 ||
          bridgeNonce.length > 128 ||
          !supportedMethods.contains(method)) {
        return null;
      }
      final rawParams = decoded['params'];
      final params = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : <String, dynamic>{};
      return MiniAppBridgeRequest(
        requestId: requestId,
        bridgeNonce: bridgeNonce,
        method: method,
        params: params,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
