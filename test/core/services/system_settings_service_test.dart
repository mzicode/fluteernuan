import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer/core/services/api/api_client.dart';
import 'package:customer/core/services/api/system_settings_service.dart';

class _CancellableSettingsApiClient extends ApiClient {
  _CancellableSettingsApiClient() : super.forTesting();

  bool? retryNetworkErrors;
  bool cancelled = false;

  @override
  Future<ApiResponse<T>> getForStartup<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    retryNetworkErrors = false;
    await cancelToken!.whenCancel;
    cancelled = true;
    return ApiResponse<T>(code: -1, message: 'cancelled');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('startup settings fetch is cancelled and never auto-retried', () async {
    final api = _CancellableSettingsApiClient();
    addTearDown(api.dispose);
    final service = SystemSettingsService(api);

    await service.getSettingsForStartup(
      timeout: const Duration(milliseconds: 20),
    );

    expect(api.cancelled, isTrue);
    expect(api.retryNetworkErrors, isFalse);
  });

  group('App display name', () {
    test('uses the new brand for empty and legacy server defaults', () {
      expect(SystemSettings.fromJson(const {}).displayName, '暖邻');
      expect(
        SystemSettings.fromJson(const {'system_name': '即时通信'}).displayName,
        '暖邻',
      );
    });

    test('preserves a non-legacy server-defined name', () {
      expect(
        SystemSettings.fromJson(
          const {'system_name': '企业通讯'},
        ).displayName,
        '企业通讯',
      );
    });
  });

  group('Platform update settings', () {
    test('uses platform-specific URLs and preserves minimum versions', () {
      final settings = SystemSettings.fromJson(const {
        'latest_version_ios': '5.0.1',
        'latest_version_android': '5.0.2',
        'app_update_url': 'https://legacy.example.com/app',
        'app_update_url_ios': 'https://apps.apple.com/app/id123456789',
        'app_update_url_android': 'https://download.example.com/app.apk',
        'min_supported_version_ios': '5.0.0',
        'min_supported_version_android': '4.9.0',
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.appVersionIOS, '5.0.1');
      expect(restored.appVersionAndroid, '5.0.2');

      expect(
        restored.appUpdateUrlFor(ios: true),
        'https://apps.apple.com/app/id123456789',
      );
      expect(
        restored.appUpdateUrlFor(ios: false),
        'https://download.example.com/app.apk',
      );
      expect(restored.minSupportedVersionFor(ios: true), '5.0.0');
      expect(restored.minSupportedVersionFor(ios: false), '4.9.0');
    });

    test('falls back to the legacy URL when split fields are absent', () {
      final settings = SystemSettings.fromJson(const {
        'app_update_url': 'https://legacy.example.com/app',
      });

      expect(
        settings.appUpdateUrlFor(ios: true),
        'https://legacy.example.com/app',
      );
      expect(
        settings.appUpdateUrlFor(ios: false),
        'https://legacy.example.com/app',
      );
    });
  });

  group('Registration verification capabilities', () {
    test('SMS requirement is independent from provider readiness', () {
      final settings = SystemSettings.fromJson(const {
        'sms_registration_required': true,
        'sms_bind_ready': false,
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.smsRegistrationRequired, isTrue);
      expect(restored.smsBindReady, isFalse);
    });

    test('email readiness defaults off and survives cache serialization', () {
      final disabled = SystemSettings.fromJson(const {});
      expect(disabled.emailRegistrationReady, isFalse);

      final enabled = SystemSettings.fromJson(const {
        'email_registration_ready': true,
      });
      final restored = SystemSettings.fromJson(enabled.toJson());
      expect(restored.emailRegistrationReady, isTrue);
    });
  });

  group('Bot marketplace visibility', () {
    test('defaults off and survives cache serialization when enabled', () {
      final defaults = SystemSettings.fromJson(const {});
      expect(defaults.botMarketplaceEnabled, isFalse);

      final enabled = SystemSettings.fromJson(const {
        'bot_marketplace_enabled': true,
      });
      final restored = SystemSettings.fromJson(enabled.toJson());
      expect(restored.botMarketplaceEnabled, isTrue);
    });
  });

  group('Voice transcription capability', () {
    test('defaults to hidden and survives cache serialization', () {
      final disabled = SystemSettings.fromJson(const {});
      expect(disabled.voiceTranscriptionEnabled, isFalse);

      final enabled = SystemSettings.fromJson(const {
        'voice_transcription_enabled': true,
      });
      final restored = SystemSettings.fromJson(enabled.toJson());
      expect(restored.voiceTranscriptionEnabled, isTrue);
    });
  });

  group('Friend add mode', () {
    test('defaults to approval when config is absent or invalid', () {
      expect(
        SystemSettings.fromJson(const {}).friendAddMode,
        FriendAddMode.approval,
      );
      expect(
        SystemSettings.fromJson(
          const {'friend_add_mode': 'unexpected'},
        ).friendAddMode,
        FriendAddMode.approval,
      );
    });

    test('parses all supported modes and survives cache serialization', () {
      for (final mode in FriendAddMode.values) {
        final settings = SystemSettings.fromJson({
          'friend_add_mode': mode.value,
        });
        final restored = SystemSettings.fromJson(settings.toJson());

        expect(settings.friendAddMode, mode);
        expect(restored.friendAddMode, mode);
      }
    });
  });

  group('Global client feature settings', () {
    test('uses backward-compatible defaults when fields are absent', () {
      final settings = SystemSettings.fromJson(const {});

      expect(settings.phoneBindingEnabled, isTrue);
      expect(settings.clientSearchMode, ClientSearchMode.exact);
      expect(settings.walletEnabled, isTrue);
      expect(settings.vipEnabled, isTrue);
    });

    test('parses disabled features and preserves them in cache', () {
      final settings = SystemSettings.fromJson(const {
        'phone_binding_enabled': false,
        'client_search_mode': 'fuzzy',
        'wallet_enabled': false,
        'vip_enabled': false,
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.phoneBindingEnabled, isFalse);
      expect(restored.clientSearchMode, ClientSearchMode.fuzzy);
      expect(restored.walletEnabled, isFalse);
      expect(restored.vipEnabled, isFalse);
    });
  });

  group('iOS compliance settings', () {
    test('uses a safe restrictive default when config is absent', () {
      final settings = SystemSettings.fromJson(const {});

      expect(settings.iosCompliance.enabled, isTrue);
      expect(settings.iosCompliance.allowsVIP, isFalse);
      expect(settings.iosCompliance.allowsWallet, isFalse);
      expect(settings.iosCompliance.allowsMomentVideo, isFalse);
    });

    test('restores normal features only when mode is explicitly disabled', () {
      final settings = SystemSettings.fromJson({
        'ios_compliance': {'enabled': false},
      });

      expect(settings.iosCompliance.allowsVIP, isTrue);
      expect(settings.iosCompliance.allowsWallet, isTrue);
      expect(settings.iosCompliance.allowsMomentVideo, isTrue);
    });

    test('applies explicit restrictions and survives cache serialization', () {
      final settings = SystemSettings.fromJson({
        'ios_compliance': {
          'enabled': true,
          'vip_enabled': false,
          'wallet_enabled': true,
          'wallet_recharge_enabled': false,
          'moment_video_enabled': false,
          'custom_portal_enabled': true,
        },
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.iosCompliance.allowsVIP, isFalse);
      expect(restored.iosCompliance.allowsWallet, isTrue);
      expect(restored.iosCompliance.allowsWalletRecharge, isFalse);
      expect(restored.iosCompliance.allowsMomentVideo, isFalse);
      expect(restored.iosCompliance.allowsCustomPortal, isTrue);
    });

    test('never allows recharge when the wallet is disabled', () {
      final settings = SystemSettings.fromJson({
        'ios_compliance': {
          'enabled': true,
          'wallet_enabled': false,
          'wallet_recharge_enabled': true,
        },
      });

      expect(settings.iosCompliance.walletRechargeEnabled, isFalse);
      expect(settings.iosCompliance.allowsWalletRecharge, isFalse);
    });
  });

  group('ChatAttachmentMenuSettings', () {
    test('defaults every option to enabled when config is absent', () {
      final settings = SystemSettings.fromJson(const {});

      expect(settings.chatAttachmentMenu.enabled, isTrue);
      expect(settings.chatAttachmentMenu.hasEnabledItem, isTrue);
      expect(settings.chatAttachmentMenu.toJson().values, everyElement(isTrue));
    });

    test('preserves explicit false and defaults missing fields to true', () {
      final settings = SystemSettings.fromJson({
        'chat_attachment_menu': {
          'album': false,
          'file': false,
        },
      });

      expect(settings.chatAttachmentMenu.album, isFalse);
      expect(settings.chatAttachmentMenu.file, isFalse);
      expect(settings.chatAttachmentMenu.camera, isTrue);
      expect(settings.chatAttachmentMenu.call, isTrue);
    });

    test('falls back safely when config has the wrong type', () {
      final settings = SystemSettings.fromJson({
        'chat_attachment_menu': 'invalid',
      });

      expect(settings.chatAttachmentMenu.toJson().values, everyElement(isTrue));
    });

    test('availability respects chat type and master switch', () {
      const transferOnly = ChatAttachmentMenuSettings(
        album: false,
        camera: false,
        call: false,
        location: false,
        redPacket: false,
        favorite: false,
        file: false,
      );
      expect(
        transferOnly.hasAvailableItem(
          isPrivateChat: true,
          isGroupChat: false,
          burnAfterReadEnabled: false,
        ),
        isTrue,
      );
      expect(
        transferOnly.hasAvailableItem(
          isPrivateChat: false,
          isGroupChat: true,
          burnAfterReadEnabled: false,
        ),
        isFalse,
      );

      const disabled = ChatAttachmentMenuSettings(enabled: false);
      expect(
        disabled.hasAvailableItem(
          isPrivateChat: true,
          isGroupChat: false,
          burnAfterReadEnabled: true,
        ),
        isFalse,
      );
    });

    test('file upload master switch keeps the file action for its warning', () {
      const fileOnly = ChatAttachmentMenuSettings(
        album: false,
        camera: false,
        call: false,
        location: false,
        redPacket: false,
        transfer: false,
        favorite: false,
      );

      expect(
        fileOnly.hasAvailableItem(
          isPrivateChat: false,
          isGroupChat: false,
          burnAfterReadEnabled: false,
          fileUploadEnabled: true,
        ),
        isTrue,
      );
      expect(
        fileOnly.hasAvailableItem(
          isPrivateChat: false,
          isGroupChat: false,
          burnAfterReadEnabled: false,
          fileUploadEnabled: false,
        ),
        isTrue,
      );
    });

    test('system settings cache serialization keeps menu values', () {
      final settings = SystemSettings.fromJson({
        'chat_attachment_menu': {
          'enabled': true,
          'camera': false,
          'transfer': false,
        },
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.chatAttachmentMenu.camera, isFalse);
      expect(restored.chatAttachmentMenu.transfer, isFalse);
      expect(restored.chatAttachmentMenu.album, isTrue);
    });
  });

  group('File upload settings', () {
    test('defaults enabled for rolling upgrades and survives serialization',
        () {
      final defaults = SystemSettings.fromJson(const {});
      expect(defaults.fileUploadEnabled, isTrue);

      final disabled = SystemSettings.fromJson(const {
        'file_upload_enabled': false,
        'max_file_size': 250,
      });
      final restored = SystemSettings.fromJson(disabled.toJson());

      expect(restored.fileUploadEnabled, isFalse);
      expect(restored.maxFileSize, 250);
    });
  });

  group('ChatImageDirectUploadSettings', () {
    test('uses safe P0 defaults when config is absent', () {
      final settings = SystemSettings.fromJson(const {});

      expect(settings.chatImageDirectUpload.enabled, isFalse);
      expect(settings.chatImageDirectUpload.platforms, ['android', 'ios']);
      expect(settings.chatImageDirectUpload.rolloutPercent, 0);
      expect(settings.chatImageDirectUpload.maxConcurrency, 3);
    });

    test('parses and preserves direct-upload rollout config', () {
      final settings = SystemSettings.fromJson({
        'chat_image_direct_upload': {
          'enabled': true,
          'platforms': ['android'],
          'rollout_percent': 25,
          'max_concurrency': 2,
        },
      });
      final restored = SystemSettings.fromJson(settings.toJson());

      expect(restored.chatImageDirectUpload.enabled, isTrue);
      expect(restored.chatImageDirectUpload.platforms, ['android']);
      expect(restored.chatImageDirectUpload.rolloutPercent, 25);
      expect(restored.chatImageDirectUpload.maxConcurrency, 2);
    });
  });
}
