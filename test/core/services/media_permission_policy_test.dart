import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:customer/core/services/media_permission_policy.dart';

void main() {
  test('granted permission proceeds without requesting again', () async {
    var requests = 0;
    final result = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.granted,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: true,
    );

    expect(result.action, MediaPermissionAction.proceed);
    expect(result.didRequest, isFalse);
    expect(requests, 0);
  });

  test('only a user action can trigger the first system request', () async {
    var requests = 0;
    final backgroundResult = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.denied,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: false,
    );

    expect(backgroundResult.action, MediaPermissionAction.blocked);
    expect(backgroundResult.didRequest, isFalse);
    expect(requests, 0);

    final userResult = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.denied,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: true,
    );

    expect(userResult.action, MediaPermissionAction.proceed);
    expect(userResult.didRequest, isTrue);
    expect(requests, 1);
  });

  test('permanent denial never requests and only offers settings to user',
      () async {
    var requests = 0;
    final userResult = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.permanentlyDenied,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: true,
    );
    final automaticResult = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.permanentlyDenied,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: false,
    );

    expect(userResult.action, MediaPermissionAction.showSettingsAction);
    expect(userResult.canOpenSettings, isTrue);
    expect(automaticResult.action, MediaPermissionAction.blocked);
    expect(requests, 0);
  });

  test(
      'first iOS denial returns a lightweight settings action without retrying',
      () async {
    var requests = 0;
    final result = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.denied,
      requestPermission: () async {
        requests++;
        return PermissionStatus.permanentlyDenied;
      },
      userInitiated: true,
    );

    expect(result.action, MediaPermissionAction.showSettingsAction);
    expect(result.didRequest, isTrue);
    expect(result.canOpenSettings, isTrue);
    expect(requests, 1);
  });

  test('camera denial can downgrade to voice without another request',
      () async {
    final result = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.permanentlyDenied,
      requestPermission: () async => PermissionStatus.granted,
      userInitiated: true,
      allowVoiceFallback: true,
    );

    expect(result.action, MediaPermissionAction.fallbackToVoice);
    expect(result.canOpenSettings, isTrue);
    expect(result.didRequest, isFalse);
  });

  test('restricted permission is a lightweight user-visible block', () async {
    var requests = 0;
    final result = await resolveMediaPermission(
      readStatus: () async => PermissionStatus.restricted,
      requestPermission: () async {
        requests++;
        return PermissionStatus.granted;
      },
      userInitiated: true,
    );

    expect(result.action, MediaPermissionAction.showLightweightHint);
    expect(result.canOpenSettings, isFalse);
    expect(requests, 0);
  });
}
