import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'sms_registration_settings_bridge_contract.dart';

typedef SmsRegistrationSettingsGetter = Future<Object?> Function(Uri uri);

Future<SmsRegistrationBridgeSettings?> loadSmsRegistrationBridgeSettings({
  SmsRegistrationSettingsGetter? getter,
  String? preferredOrigin,
  int? nowMs,
}) async {
  final get = getter ?? _getBridgeJson;
  for (final uri in smsRegistrationSettingsBridgeUris(
    preferredOrigin: preferredOrigin,
    nowMs: nowMs,
  )) {
    try {
      debugPrint('[SMS_BRIDGE] GET $uri');
      final raw = await get(uri);
      debugPrint('[SMS_BRIDGE] raw=$raw');
      final parsed = SmsRegistrationBridgeSettings.tryParse(raw);
      if (parsed != null) {
        debugPrint(
          '[SMS_BRIDGE] ok bind=${parsed.smsBindReady} required=${parsed.smsRegistrationRequired} show=${parsed.showSmsCode} generatedAt=${parsed.generatedAt}',
        );
        return parsed;
      }
      debugPrint('[SMS_BRIDGE] skip invalid json from $uri');
    } catch (e) {
      debugPrint('[SMS_BRIDGE] fail $uri err=$e');
    }
  }
  debugPrint('[SMS_BRIDGE] no valid settings');
  return null;
}

Future<Object?> _getBridgeJson(Uri uri) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );
  final response = await dio.getUri(uri);
  return response.data;
}
