// 文件用途：解析桌面多实例参数，并为账号凭证、本地数据库和窗口状态提供隔离命名空间。
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

class DesktopInstanceService {
  DesktopInstanceService._();

  static final DesktopInstanceService instance = DesktopInstanceService._();
  static final RegExp _unsafeProfilePattern = RegExp(r'[^a-zA-Z0-9_-]');

  String _profileId = 'default';
  bool _configured = false;

  String get profileId => _profileId;
  bool get isDefault => _profileId == 'default';

  void configure(List<String> arguments) {
    if (_configured) return;
    _configured = true;

    String? requested;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index].trim();
      if (argument.startsWith('--profile-id=')) {
        requested = argument.substring('--profile-id='.length);
        break;
      }
      if (argument == '--profile-id' && index + 1 < arguments.length) {
        requested = arguments[index + 1];
        break;
      }
    }

    final normalized = _normalizeProfileId(requested);
    if (normalized != null) _profileId = normalized;
    debugPrint('[DesktopInstance] profile=$_profileId');
  }

  String storageKey(String baseKey) {
    if (isDefault) return baseKey;
    return '${baseKey}__profile_$_profileId';
  }

  String databaseDirectory(String applicationDocumentsPath) {
    if (isDefault) return applicationDocumentsPath;
    final separator = Platform.pathSeparator;
    return '$applicationDocumentsPath${separator}profiles$separator$_profileId';
  }

  Future<void> launchNewInstance() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    final profile =
        'instance_${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
    await Process.start(
      Platform.resolvedExecutable,
      ['--profile-id=$profile'],
      mode: ProcessStartMode.detached,
    );
  }

  String? _normalizeProfileId(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty || value == 'default') return null;
    value = value.replaceAll(_unsafeProfilePattern, '_');
    if (value.length > 48) value = value.substring(0, 48);
    return value.isEmpty ? null : value;
  }
}
