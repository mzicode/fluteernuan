import '../services/api/endpoint_manager.dart';

class SmsRegistrationBridgeSettings {
  final bool smsBindReady;
  final bool smsRegistrationRequired;
  final String? generatedAt;

  const SmsRegistrationBridgeSettings({
    required this.smsBindReady,
    required this.smsRegistrationRequired,
    this.generatedAt,
  });

  bool get showSmsCode => smsBindReady && smsRegistrationRequired;

  static SmsRegistrationBridgeSettings? tryParse(Object? raw) {
    Map<String, dynamic>? json;
    if (raw is Map<String, dynamic>) {
      json = raw;
    } else if (raw is Map) {
      json = Map<String, dynamic>.from(raw);
    }
    if (json == null) return null;

    final bindReady = json['sms_bind_ready'];
    final required = json['sms_registration_required'];
    if (bindReady is! bool || required is! bool) return null;

    final generatedAt = json['generated_at'];
    return SmsRegistrationBridgeSettings(
      smsBindReady: bindReady,
      smsRegistrationRequired: required,
      generatedAt: generatedAt is String ? generatedAt : null,
    );
  }
}

const List<String> kSmsRegistrationSettingsBridgeOrigins = [
  'https://web.cybndo.com',
  'https://web.ojyvn.com',
  'https://web.iexici.cn',
];

const String kSmsRegistrationSettingsBridgePath =
    '/sms-registration-settings.json';

List<String> smsRegistrationSettingsBridgeOrigins({String? preferredOrigin}) {
  final out = <String>[];
  final seen = <String>{};

  void add(String? value) {
    final origin = _originOf(value);
    if (origin == null || seen.contains(origin)) return;
    seen.add(origin);
    out.add(origin);
  }

  add(preferredOrigin);
  add(EndpointManager.instance.apiServerUrl);
  for (final origin in kSmsRegistrationSettingsBridgeOrigins) {
    add(origin);
  }
  for (final url in EndpointManager.fallbackServerUrls) {
    add(url);
  }
  return out;
}

List<Uri> smsRegistrationSettingsBridgeUris({
  String? preferredOrigin,
  int? nowMs,
}) {
  final timestamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return smsRegistrationSettingsBridgeOrigins(preferredOrigin: preferredOrigin)
      .map(
        (origin) => Uri.parse('$origin$kSmsRegistrationSettingsBridgePath')
            .replace(queryParameters: {'t': '$timestamp'}),
      )
      .toList(growable: false);
}

String? _originOf(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
  if (scheme != 'http' && scheme != 'https') return null;
  return Uri(
    scheme: scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}
