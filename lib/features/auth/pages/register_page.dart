// 文件用途：实现单页注册流程，收集手机号、密码、姓名、邀请码和协议确认。
// 核心逻辑：本地校验必要字段并检查手机号可用性；短信码是否展示由公开 bridge 开关决定。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/router/redirect_utils.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validation.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/sms_registration_settings_bridge.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import 'agreement_page.dart';

String _registerText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage>
    with WidgetsBindingObserver {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _smsCodeController = TextEditingController();

  Timer? _usernameCheckTimer;
  Timer? _smsCountdownTimer;
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  bool _isLoadingSmsSettings = false;
  bool _smsSettingsLoadFailed = false;
  bool _isSendingSms = false;
  int _smsSecondsLeft = 0;
  SmsRegistrationBridgeSettings? _smsSettings;
  String? _usernameMessage;
  String? _errorMessage;

  bool get _showSmsCode => _smsSettings?.showSmsCode == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phoneController.addListener(_onPhoneChanged);
    unawaited(_loadSmsSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameCheckTimer?.cancel();
    _smsCountdownTimer?.cancel();
    _phoneController
      ..removeListener(_onPhoneChanged)
      ..dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSmsSettings());
    }
  }

  String _loginLocation() {
    final redirect = safeInAppRedirect(
      GoRouterState.of(context).uri.queryParameters['redirect'],
    );
    if (redirect == null) return '/login';
    return '/login?redirect=${Uri.encodeComponent(redirect)}';
  }

  void _goToLogin() {
    HapticFeedback.selectionClick();
    context.go(_loginLocation());
  }

  void _onPhoneChanged() {
    final phone = _phoneController.text.trim();
    _usernameCheckTimer?.cancel();
    _clearError();

    if (!isValidMainlandChinaMobile(phone)) {
      if (!mounted) return;
      setState(() {
        _isUsernameAvailable = null;
        _usernameMessage = null;
        _isCheckingUsername = false;
      });
      return;
    }

    _usernameCheckTimer = Timer(
      const Duration(milliseconds: 500),
      () => _checkUsernameAvailability(phone),
    );
  }

  Future<void> _checkUsernameAvailability(String phone) async {
    if (!isValidMainlandChinaMobile(phone) || !mounted) return;
    setState(() => _isCheckingUsername = true);

    try {
      final response = await ref.read(apiClientProvider).post(
        '/auth/check-username',
        data: {'username': phone},
      );
      if (!mounted || _phoneController.text.trim() != phone) return;
      setState(() {
        _isUsernameAvailable =
            response.isSuccess && response.data?['available'] == true;
        _usernameMessage = response.isSuccess
            ? localizeServerMessage(
                response.data?['message'] as String?,
                fallbackZhCN:
                    _isUsernameAvailable == true ? '该手机号可以注册' : '该手机号已注册',
                fallbackZhTW:
                    _isUsernameAvailable == true ? '該手機號碼可以註冊' : '該手機號碼已註冊',
                fallbackEn: _isUsernameAvailable == true
                    ? 'This mobile number is available'
                    : 'This mobile number is already registered',
              )
            : null;
        _isCheckingUsername = false;
      });
    } catch (_) {
      if (!mounted || _phoneController.text.trim() != phone) return;
      setState(() {
        _isUsernameAvailable = null;
        _usernameMessage = null;
        _isCheckingUsername = false;
      });
    }
  }

  Future<void> _loadSmsSettings() async {
    if (_isLoadingSmsSettings) return;
    setState(() {
      _isLoadingSmsSettings = true;
      _smsSettingsLoadFailed = false;
    });
    final settings = await loadSmsRegistrationBridgeSettings();
    debugPrint(
      '[SMS_BRIDGE] register_page settings=${settings == null ? 'null' : 'bind=${settings.smsBindReady} required=${settings.smsRegistrationRequired} show=${settings.showSmsCode}'} lastShow=$_showSmsCode failed=$_smsSettingsLoadFailed',
    );
    if (!mounted) return;
    setState(() {
      _isLoadingSmsSettings = false;
      if (settings != null) {
        _smsSettings = settings;
        _smsSettingsLoadFailed = false;
        if (!settings.showSmsCode) {
          _smsCodeController.clear();
          _smsCountdownTimer?.cancel();
          _smsSecondsLeft = 0;
        }
      } else if (_smsSettings == null) {
        _smsSettingsLoadFailed = true;
      }
    });
    debugPrint(
      '[SMS_BRIDGE] register_page applied show=$_showSmsCode failed=$_smsSettingsLoadFailed',
    );
  }

  Future<void> _sendSmsCode() async {
    if (!_showSmsCode || _isSendingSms || _smsSecondsLeft > 0) return;
    final phone = _phoneController.text.trim();
    if (!isValidMainlandChinaMobile(phone)) {
      return _showError(_registerText(
        context,
        zhCN: '请输入正确的11位手机号',
        zhTW: '請輸入正確的11位手機號碼',
        en: 'Enter a valid 11-digit mobile number',
      ));
    }

    setState(() {
      _isSendingSms = true;
      _errorMessage = null;
    });
    final response =
        await ref.read(authServiceProvider.notifier).sendRegistrationCode(phone);
    if (!mounted) return;
    setState(() => _isSendingSms = false);
    if (response.isSuccess) {
      _startSmsCountdown();
    } else {
      _showError(
        localizeServerMessage(
          response.message,
          fallbackZhCN: '验证码发送失败，请稍后重试',
          fallbackZhTW: '驗證碼傳送失敗，請稍後重試',
          fallbackEn: 'Failed to send the verification code.',
        ),
      );
    }
  }

  void _startSmsCountdown() {
    _smsCountdownTimer?.cancel();
    setState(() => _smsSecondsLeft = 60);
    _smsCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_smsSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _smsSecondsLeft = 0);
      } else {
        setState(() => _smsSecondsLeft--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (PlatformUtils.isPhysicalDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goToLogin,
        title: _registerText(
          context,
          zhCN: '注册账号',
          zhTW: '註冊帳號',
          en: 'Create Account',
        ),
        child: _buildRegisterContent(isDark),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          onPressed: _goToLogin,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: Text(
          _registerText(
            context,
            zhCN: '注册账号',
            zhTW: '註冊帳號',
            en: 'Create Account',
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: _buildRegisterContent(isDark),
        ),
      ),
    );
  }

  Widget _buildRegisterContent(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _registerText(
            context,
            zhCN: '欢迎加入',
            zhTW: '歡迎加入',
            en: 'Welcome',
          ),
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _registerText(
            context,
            zhCN: '创建账号，开启更美好的体验',
            zhTW: '建立帳號，開啟更美好的體驗',
            en: 'Create an account to get started',
          ),
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
        const SizedBox(height: 32),
        _buildPhoneField(isDark),
        if (_showSmsCode) ...[
          const SizedBox(height: 14),
          _buildSmsCodeField(),
        ] else if (_smsSettingsLoadFailed) ...[
          const SizedBox(height: 14),
          _buildSmsSettingsRetry(),
        ],
        const SizedBox(height: 14),
        _buildPasswordField(
          controller: _passwordController,
          hint: _registerText(
            context,
            zhCN: '请输入密码',
            zhTW: '請輸入密碼',
            en: 'Enter password',
          ),
          obscure: _obscurePassword,
          onToggle: () => setState(
            () => _obscurePassword = !_obscurePassword,
          ),
        ),
        const SizedBox(height: 14),
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: _registerText(
            context,
            zhCN: '请再次输入密码',
            zhTW: '請再次輸入密碼',
            en: 'Confirm password',
          ),
          obscure: _obscureConfirmPassword,
          onToggle: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
        ),
        const SizedBox(height: 14),
        _buildInputField(
          controller: _nicknameController,
          hint: _registerText(
            context,
            zhCN: '请输入姓名',
            zhTW: '請輸入姓名',
            en: 'Enter your name',
          ),
          icon: Icons.person_outline_rounded,
          inputFormatters: [LengthLimitingTextInputFormatter(50)],
        ),
        const SizedBox(height: 14),
        _buildInputField(
          controller: _inviteCodeController,
          hint: _registerText(
            context,
            zhCN: '请输入邀请码（必填）',
            zhTW: '請輸入邀請碼（必填）',
            en: 'Enter invitation code (required)',
          ),
          icon: Icons.card_giftcard_rounded,
          inputFormatters: [LengthLimitingTextInputFormatter(64)],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        _buildAgreementCheckbox(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _register,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryFor(context),
              foregroundColor: AppColors.onPrimaryFor(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimaryFor(context),
                    ),
                  )
                : Text(
                    _registerText(
                      context,
                      zhCN: '完成注册',
                      zhTW: '完成註冊',
                      en: 'Create Account',
                    ),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _registerText(
                context,
                zhCN: '已有账号？',
                zhTW: '已有帳號？',
                en: 'Already have an account?',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
            TextButton(
              onPressed: _goToLogin,
              child: Text(
                _registerText(
                  context,
                  zhCN: '立即登录',
                  zhTW: '立即登入',
                  en: 'Log in now',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhoneField(bool isDark) {
    return _inputContainer(
      child: TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        style: TextStyle(color: AppColors.textPrimaryFor(context)),
        decoration: InputDecoration(
          hintText: _registerText(
            context,
            zhCN: '请输入手机号',
            zhTW: '請輸入手機號碼',
            en: 'Enter mobile number',
          ),
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.phone_android_rounded,
            color: AppColors.inputIconFor(context),
          ),
          suffixIcon: _buildUsernameStatusIcon(),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _buildSmsCodeField() {
    return _inputContainer(
      child: TextField(
        controller: _smsCodeController,
        keyboardType: TextInputType.number,
        onChanged: (_) => _clearError(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: TextStyle(color: AppColors.textPrimaryFor(context)),
        decoration: InputDecoration(
          hintText: _registerText(
            context,
            zhCN: '请输入6位短信验证码',
            zhTW: '請輸入6位短信驗證碼',
            en: 'Enter the 6-digit SMS code',
          ),
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.sms_outlined,
            color: AppColors.inputIconFor(context),
          ),
          suffixIcon: TextButton(
            onPressed: (_smsSecondsLeft > 0 || _isSendingSms)
                ? null
                : _sendSmsCode,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.linkFor(context),
              disabledForegroundColor: AppColors.textTertiaryFor(context),
            ),
            child: _isSendingSms
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _smsSecondsLeft > 0
                        ? '${_smsSecondsLeft}s'
                        : _registerText(
                            context,
                            zhCN: '发送验证码',
                            zhTW: '發送驗證碼',
                            en: 'Send Code',
                          ),
                  ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _buildSmsSettingsRetry() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _registerText(
              context,
              zhCN: '短信注册设置读取失败',
              zhTW: '短信註冊設定讀取失敗',
              en: 'Could not load SMS registration settings',
            ),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ),
        TextButton(
          onPressed: _isLoadingSmsSettings ? null : _loadSmsSettings,
          child: _isLoadingSmsSettings
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _registerText(
                    context,
                    zhCN: '重试',
                    zhTW: '重試',
                    en: 'Retry',
                  ),
                ),
        ),
      ],
    );
  }

  Widget? _buildUsernameStatusIcon() {
    if (!isValidMainlandChinaMobile(_phoneController.text.trim())) return null;
    if (_isCheckingUsername) {
      return Padding(
        padding: const EdgeInsets.all(15),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textTertiaryFor(context),
        ),
      );
    }
    if (_isUsernameAvailable == null) return null;
    return Tooltip(
      message: _usernameMessage ?? '',
      child: Icon(
        _isUsernameAvailable == true
            ? Icons.check_circle_rounded
            : Icons.error_rounded,
        color:
            _isUsernameAvailable == true ? AppColors.success : AppColors.error,
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return _inputContainer(
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: (_) => _clearError(),
        inputFormatters: [LengthLimitingTextInputFormatter(20)],
        style: TextStyle(color: AppColors.textPrimaryFor(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: AppColors.inputIconFor(context),
          ),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.inputIconFor(context),
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return _inputContainer(
      child: TextField(
        controller: controller,
        onChanged: (_) => _clearError(),
        inputFormatters: inputFormatters,
        style: TextStyle(color: AppColors.textPrimaryFor(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(icon, color: AppColors.inputIconFor(context)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _inputContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _buildAgreementCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (value) => setState(() {
              _agreedToTerms = value ?? false;
              _clearError();
            }),
            activeColor: AppColors.controlActiveFor(context),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryFor(context),
              ),
              children: [
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '我已阅读并同意',
                    zhTW: '我已閱讀並同意',
                    en: 'I have read and agree to ',
                  ),
                ),
                _agreementSpan(
                  type: AgreementType.userAgreement,
                  zhCN: '《用户协议》',
                  zhTW: '《用戶協議》',
                  en: 'User Agreement',
                ),
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '和',
                    zhTW: '和',
                    en: ' and ',
                  ),
                ),
                _agreementSpan(
                  type: AgreementType.privacyPolicy,
                  zhCN: '《隐私政策》',
                  zhTW: '《隱私政策》',
                  en: 'Privacy Policy',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _agreementSpan({
    required AgreementType type,
    required String zhCN,
    required String zhTW,
    required String en,
  }) {
    return TextSpan(
      text: _registerText(context, zhCN: zhCN, zhTW: zhTW, en: en),
      style: TextStyle(color: AppColors.linkFor(context)),
      recognizer: TapGestureRecognizer()
        ..onTap = () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AgreementPage(type: type)),
            ),
    );
  }

  Future<void> _register() async {
    if (_isLoading) return;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final nickname = _nicknameController.text.trim();
    final inviteCode = _inviteCodeController.text.trim();

    if (!isValidMainlandChinaMobile(phone)) {
      return _showError(_registerText(
        context,
        zhCN: '请输入正确的11位手机号',
        zhTW: '請輸入正確的11位手機號碼',
        en: 'Enter a valid 11-digit mobile number',
      ));
    }
    if (_isCheckingUsername) {
      return _showError(_registerText(
        context,
        zhCN: '正在检查手机号，请稍候',
        zhTW: '正在檢查手機號碼，請稍候',
        en: 'Checking the mobile number. Please wait.',
      ));
    }
    if (_isUsernameAvailable == false) {
      return _showError(
        _usernameMessage ??
            _registerText(
              context,
              zhCN: '该手机号已注册',
              zhTW: '該手機號碼已註冊',
              en: 'This mobile number is already registered',
            ),
      );
    }
    if (password.length < 6 || password.length > 20) {
      return _showError(_registerText(
        context,
        zhCN: '密码长度必须为6至20位',
        zhTW: '密碼長度必須為6至20位',
        en: 'Password must be 6 to 20 characters',
      ));
    }
    if (_confirmPasswordController.text != password) {
      return _showError(_registerText(
        context,
        zhCN: '两次输入的密码不一致',
        zhTW: '兩次輸入的密碼不一致',
        en: 'The two passwords do not match',
      ));
    }
    if (nickname.isEmpty) {
      return _showError(_registerText(
        context,
        zhCN: '请输入姓名',
        zhTW: '請輸入姓名',
        en: 'Enter your name',
      ));
    }
    if (inviteCode.isEmpty) {
      return _showError(_registerText(
        context,
        zhCN: '请输入邀请码',
        zhTW: '請輸入邀請碼',
        en: 'Enter an invitation code',
      ));
    }
    if (!_agreedToTerms) {
      return _showError(_registerText(
        context,
        zhCN: '请先阅读并同意用户协议和隐私政策',
        zhTW: '請先閱讀並同意用戶協議和隱私政策',
        en: 'Please agree to the User Agreement and Privacy Policy',
      ));
    }
    final smsCode = _smsCodeController.text.trim();
    if (_showSmsCode && !RegExp(r'^\d{6}$').hasMatch(smsCode)) {
      return _showError(_registerText(
        context,
        zhCN: '请填写6位短信验证码',
        zhTW: '請填寫6位短信驗證碼',
        en: 'Enter the 6-digit SMS verification code',
      ));
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceResults = await Future.wait<String>([
        DeviceService.getDeviceId(),
        DeviceService.getDeviceName(),
      ]);
      if (!mounted) return;

      final response = await ref.read(authServiceProvider.notifier).register(
            username: phone,
            password: password,
            nickname: nickname,
            deviceId: deviceResults[0],
            deviceType: DeviceService.getDeviceType(),
            deviceName: deviceResults[1],
            referralCode: inviteCode,
            phone: phone,
            smsCode: _showSmsCode ? smsCode : null,
          );
      if (!mounted) return;
      if (!response.isSuccess) {
        setState(() {
          _isLoading = false;
          _errorMessage = localizeServerMessage(
            response.message,
            fallbackZhCN: '注册失败，请稍后重试',
            fallbackZhTW: '註冊失敗，請稍後重試',
            fallbackEn: 'Registration failed. Please try again later.',
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _registerText(
          context,
          zhCN: '注册失败，请稍后重试',
          zhTW: '註冊失敗，請稍後重試',
          en: 'Registration failed. Please try again later.',
        );
      });
    }
  }

  void _clearError() {
    if (_errorMessage != null && mounted) {
      setState(() => _errorMessage = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }
}
