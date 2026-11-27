import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

void debugPrintNertcConsent409(String reason) {
  debugPrint(
    '[NertcService] session 409 reason=${reason.isEmpty ? "(empty)" : reason}',
  );
}

const _nertcTerminalConsentReasons = <String>{
  'stale_call_session',
  'call_terminal_or_invalid_state',
  'native_provider_not_compatible',
  'missing_native_session',
  'invalid_session_consent',
};

/// Maps POST /rtc/nertc/session HTTP 409 message → consent outcome.
@visibleForTesting
NertcConsentStatus mapNertcConsent409(String reason) {
  final normalized = reason.trim();
  if (_nertcTerminalConsentReasons.contains(normalized)) {
    return NertcConsentStatus.aborted;
  }
  // Only lock-style 409 means "go GET token". Generic/localized "请求失败"
  // (plain-body parse miss) must keep waiting so the callee can finish consent.
  if (normalized == 'existing_call_provider_locked' ||
      normalized.contains('provider_locked') ||
      normalized.contains('already_locked')) {
    return NertcConsentStatus.tryToken;
  }
  return NertcConsentStatus.waiting;
}

/// Outcome of POST /rtc/nertc/session.
///
/// Backend contract (暖鄰 NERTC 2.0):
/// - ready=false: own consent recorded, keep polling while still calling
/// - ready=true: both consented, NERTC lock formed → GET token
/// - HTTP 409 after peer accept: not always failure → try GET token
enum NertcConsentStatus {
  waiting,
  ready,
  tryToken,
  aborted,
}

/// Server-issued NERTC session values. Secrets are deliberately not logged.
class NertcSession {
  const NertcSession({
    required this.appKey,
    required this.channelName,
    required this.sessionId,
    required this.callId,
    required this.uid,
    required this.token,
    required this.expiresAt,
  });

  /// From credential only — member /rtc/nertc/config does not return AppKey.
  final String appKey;
  final String channelName;
  final String sessionId;
  final String callId;
  final String uid;
  final String token;
  final DateTime? expiresAt;

  int get sdkUid {
    final parsed = int.tryParse(uid);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(uid) ||
        parsed == null ||
        parsed <= 0 ||
        parsed > 9223372036854775807) {
      throw FormatException('Invalid NERTC uid');
    }
    return parsed;
  }
}

DateTime? parseNertcExpiresAt(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) {
    final seconds = raw.toInt();
    if (seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
  final text = raw.toString().trim();
  if (text.isEmpty || text == '0') return null;
  final asInt = int.tryParse(text);
  if (asInt != null && asInt > 0) {
    // Wire DTO: expires_at is Unix seconds (not ISO-8601).
    if (asInt < 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
  }
  return DateTime.tryParse(text)?.toUtc();
}

class NertcService {
  NertcService(this._api);

  final ApiClient _api;

  Future<NertcConsentStatus> consent({
    required String channelName,
    required String callId,
    required String sessionId,
    CancelToken? cancelToken,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/rtc/nertc/session',
      responseType: ResponseType.plain,
      data: <String, dynamic>{
        'channel_name': channelName,
        'call_id': callId,
        'session_id': sessionId,
        'sdk_capability': 'nertc-basic-v1',
      },
      cancelToken: cancelToken,
      receiveTimeout: const Duration(seconds: 15),
      retryNetworkErrors: false,
    );
    if (response.isSuccess && response.data != null) {
      return response.data!['ready'] == true
          ? NertcConsentStatus.ready
          : NertcConsentStatus.waiting;
    }
    if (response.code == 409) {
      final reason = response.message.trim();
      debugPrintNertcConsent409(reason);
      return mapNertcConsent409(reason);
    }
    throw StateError(response.message);
  }

  Future<NertcSession> token({
    required String channelName,
    required String expectedCallId,
    required String expectedSessionId,
    CancelToken? cancelToken,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/rtc/nertc/token',
      queryParameters: <String, dynamic>{'channel_name': channelName},
      responseType: ResponseType.plain,
      cancelToken: cancelToken,
    );
    if (!response.isSuccess || response.data == null) {
      // Preserve server reason (e.g. both_updated_apps_must_consent_before_accept).
      final reason = response.message.trim();
      throw StateError(reason.isEmpty ? 'NERTC token failed' : reason);
    }
    return _sessionFromCredential(
      response.data!,
      channelName: channelName,
      expectedCallId: expectedCallId,
      expectedSessionId: expectedSessionId,
    );
  }

  Future<NertcSession?> renew(
    String channelName, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/rtc/nertc/renew',
      responseType: ResponseType.plain,
      data: <String, dynamic>{'channel_name': channelName},
      cancelToken: cancelToken,
      receiveTimeout: const Duration(seconds: 15),
      retryNetworkErrors: false,
    );
    if (!response.isSuccess) throw StateError(response.message);
    final data = response.data;
    if (data == null || data['token'] == null) return null;
    final appKey = data['app_key']?.toString() ?? '';
    final token = data['token'].toString();
    if (appKey.isEmpty || token.isEmpty) return null;
    return NertcSession(
      appKey: appKey,
      channelName: data['channel_name']?.toString() ?? channelName,
      sessionId: data['session_id']?.toString() ?? '',
      callId: data['call_id']?.toString() ?? '',
      uid: data['uid']?.toString() ?? '',
      token: token,
      expiresAt: parseNertcExpiresAt(data['expires_at']),
    );
  }

  NertcSession _sessionFromCredential(
    Map<String, dynamic> data, {
    required String channelName,
    required String expectedCallId,
    required String expectedSessionId,
  }) {
    final responseChannel = data['channel_name']?.toString() ?? '';
    final responseCallId = data['call_id']?.toString() ?? expectedCallId;
    final responseSessionId =
        data['session_id']?.toString() ?? expectedSessionId;
    final token = data['token']?.toString() ?? '';
    final appKey = data['app_key']?.toString() ?? '';
    if (responseChannel != channelName ||
        responseCallId != expectedCallId ||
        responseSessionId != expectedSessionId ||
        token.isEmpty ||
        appKey.isEmpty) {
      throw StateError('Invalid NERTC token response');
    }
    return NertcSession(
      appKey: appKey,
      channelName: channelName,
      sessionId: expectedSessionId,
      callId: expectedCallId,
      uid: data['uid']?.toString() ?? '',
      token: token,
      expiresAt: parseNertcExpiresAt(data['expires_at']),
    );
  }
}
