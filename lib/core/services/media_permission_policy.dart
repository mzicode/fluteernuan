// 文件用途：统一原生音视频权限的状态判断和单次请求编排。
// 核心逻辑：只有用户主动操作才能触发系统申请；拒绝结果只返回给 UI，绝不自动打开系统设置。
import 'package:permission_handler/permission_handler.dart';

typedef MediaPermissionStatusReader = Future<PermissionStatus> Function();
typedef MediaPermissionRequester = Future<PermissionStatus> Function();

enum MediaPermissionAction {
  proceed,
  blocked,
  showLightweightHint,
  showSettingsAction,
  fallbackToVoice,
}

class MediaPermissionResult {
  const MediaPermissionResult({
    required this.status,
    required this.action,
    required this.didRequest,
  });

  final PermissionStatus status;
  final MediaPermissionAction action;
  final bool didRequest;

  bool get isGranted => action == MediaPermissionAction.proceed;
  bool get canOpenSettings =>
      action == MediaPermissionAction.showSettingsAction ||
      (action == MediaPermissionAction.fallbackToVoice &&
          status.isPermanentlyDenied);
}

MediaPermissionAction decideMediaPermissionAction({
  required PermissionStatus status,
  required bool userInitiated,
  bool allowVoiceFallback = false,
}) {
  if (status.isGranted) return MediaPermissionAction.proceed;
  if (!userInitiated) return MediaPermissionAction.blocked;
  if (allowVoiceFallback) return MediaPermissionAction.fallbackToVoice;
  if (status.isPermanentlyDenied) {
    return MediaPermissionAction.showSettingsAction;
  }
  return MediaPermissionAction.showLightweightHint;
}

/// 读取当前状态，并且只在用户主动操作且权限仍可请求时申请一次。
///
/// `permission_handler` 在 iOS 上会把尚未决定的权限表示为 denied，用户明确
/// 拒绝后表示为 permanentlyDenied。因此 restricted、limited 和永久拒绝均不会
/// 再次调用系统申请接口。
Future<MediaPermissionResult> resolveMediaPermission({
  required MediaPermissionStatusReader readStatus,
  required MediaPermissionRequester requestPermission,
  required bool userInitiated,
  bool allowVoiceFallback = false,
}) async {
  var status = await readStatus();
  var didRequest = false;

  if (!status.isGranted && status.isDenied && userInitiated) {
    didRequest = true;
    status = await requestPermission();
  }

  return MediaPermissionResult(
    status: status,
    action: decideMediaPermissionAction(
      status: status,
      userInitiated: userInitiated,
      allowVoiceFallback: allowVoiceFallback,
    ),
    didRequest: didRequest,
  );
}
