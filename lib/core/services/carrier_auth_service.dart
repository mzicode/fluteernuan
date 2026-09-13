// 文件用途：封装极光认证 Flutter SDK，只向登录页返回一次性 loginToken。
// 安全边界：客户端不接收 Master Secret、RSA 私钥或可信明文手机号。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jverify/jverify.dart';

import '../utils/platform_utils.dart';

class CarrierAuthorizationResult {
  final bool success;
  final bool cancelled;
  final String loginToken;
  final String operatorName;
  final String message;

  const CarrierAuthorizationResult({
    required this.success,
    this.cancelled = false,
    this.loginToken = '',
    this.operatorName = '',
    this.message = '',
  });
}

class CarrierAuthService {
  CarrierAuthService._();

  static final CarrierAuthService instance = CarrierAuthService._();

  final Jverify _jverify = Jverify();
  String _initializedAppKey = '';
  Future<bool>? _initializing;

  Future<bool> _initialize(String appKey) async {
    if (!PlatformUtils.isMobile || appKey.trim().isEmpty) return false;
    if (_initializedAppKey == appKey) {
      try {
        final state = await _jverify.isInitSuccess();
        if (state['result'] == true) return true;
      } catch (_) {
        _initializedAppKey = '';
      }
    }
    final active = _initializing;
    if (active != null) return active;

    final future = _performInitialize(appKey.trim());
    _initializing = future;
    try {
      return await future;
    } finally {
      _initializing = null;
    }
  }

  Future<bool> _performInitialize(String appKey) async {
    final completer = Completer<bool>();
    _jverify.setDebugMode(kDebugMode);
    // This is invoked only after the app-level agreement checkbox is selected.
    _jverify.setCollectionAuth(true);
    _jverify.addSDKSetupCallBackListener((event) {
      if (!completer.isCompleted) completer.complete(event.code == 8000);
    });
    _jverify.setup(
      appKey: appKey,
      channel: 'official',
      timeout: 10000,
      setControlWifiSwitch: true,
    );
    final ready = await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => false,
    );
    _jverify.addSDKSetupCallBackListener(null);
    if (ready) _initializedAppKey = appKey;
    return ready;
  }

  Future<CarrierAuthorizationResult> authorize({
    required String appKey,
  }) async {
    try {
      if (!await _initialize(appKey)) {
        return const CarrierAuthorizationResult(
          success: false,
          message: '运营商认证初始化失败',
        );
      }
      final capability = await _jverify.checkVerifyEnable();
      if (capability['result'] != true) {
        return const CarrierAuthorizationResult(
          success: false,
          message: '当前网络或手机卡不支持本机号码认证',
        );
      }

      final preLogin = await _jverify.preLogin(
        timeOut: 10000,
        enableSms: false,
      );
      if (preLogin['code'] != 7000) {
        return CarrierAuthorizationResult(
          success: false,
          message: preLogin['message']?.toString() ?? '本机号码预认证失败',
        );
      }

      final result = await _jverify.loginAuth(true, timeout: 15000);
      final code = int.tryParse(result['code']?.toString() ?? '') ?? -1;
      final token = result['message']?.toString().trim() ?? '';
      if (code == 6000 && token.isNotEmpty) {
        return CarrierAuthorizationResult(
          success: true,
          loginToken: token,
          operatorName: result['operator']?.toString() ?? '',
        );
      }
      return CarrierAuthorizationResult(
        success: false,
        cancelled: code == 6002,
        message: result['message']?.toString() ?? '本机号码认证未完成',
      );
    } catch (e) {
      debugPrint('[CarrierAuth] authorization failed: ${e.runtimeType}');
      return const CarrierAuthorizationResult(
        success: false,
        message: '本机号码认证暂不可用',
      );
    }
  }
}
