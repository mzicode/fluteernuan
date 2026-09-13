// 文件用途：实现 WithdrawMethodType 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 WithdrawMethodType 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
import 'withdraw_accounts_page.dart';
import '../widgets/pay_password_input.dart';

String _withdrawText(
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

bool _withdrawContainsHan(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

String _withdrawTitleFromKey(String key) {
  final parts = key
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
    final normalized = part.trim().toLowerCase();
    return normalized.isEmpty
        ? normalized
        : normalized[0].toUpperCase() + normalized.substring(1);
  }).toList();
  return parts.isEmpty ? 'Field' : parts.join(' ');
}

String _localizedWithdrawMethodName(
  BuildContext context,
  WithdrawMethodConfig method,
) {
  if (AppLocalizations.of(context).language != AppLanguage.en) {
    return method.name;
  }
  final rawName = method.name.trim();
  final rawIcon = method.icon.trim().toLowerCase();
  final fingerprint = '$rawName $rawIcon ${method.id}'.toLowerCase();
  if (fingerprint.contains('alipay') || rawName.contains('支付宝')) {
    return 'Alipay';
  }
  if (fingerprint.contains('wechat') ||
      fingerprint.contains('weixin') ||
      rawName.contains('微信')) {
    return 'WeChat Pay';
  }
  if (fingerprint.contains('bank') ||
      fingerprint.contains('card') ||
      rawName.contains('银行卡') ||
      rawName.contains('银行')) {
    return 'Bank Card';
  }
  if (fingerprint.contains('usdt') ||
      fingerprint.contains('trc20') ||
      fingerprint.contains('erc20') ||
      fingerprint.contains('crypto')) {
    return 'USDT';
  }
  if (rawName.isNotEmpty && !_withdrawContainsHan(rawName)) {
    return rawName;
  }
  return _withdrawTitleFromKey(method.id);
}

String _localizedWithdrawFieldLabel(
    BuildContext context, FormFieldConfig field) {
  if (AppLocalizations.of(context).language != AppLanguage.en) {
    return field.label;
  }
  final key = field.key.trim().toLowerCase();
  switch (key) {
    case 'name':
    case 'real_name':
    case 'full_name':
    case 'account_name':
    case 'payee_name':
      return 'Account Name';
    case 'account':
    case 'account_no':
    case 'account_number':
      return 'Account Number';
    case 'bank_card':
    case 'bank_card_no':
    case 'bank_card_number':
    case 'card_no':
    case 'card_number':
      return 'Bank Card Number';
    case 'bank':
    case 'bank_name':
      return 'Bank Name';
    case 'branch':
    case 'branch_name':
      return 'Branch Name';
    case 'phone':
    case 'mobile':
    case 'phone_number':
    case 'mobile_number':
      return 'Phone Number';
    case 'id_card':
    case 'id_no':
    case 'id_number':
      return 'ID Number';
    case 'wallet':
    case 'wallet_address':
    case 'address':
      return 'Wallet Address';
    case 'network':
    case 'chain':
      return 'Network';
    case 'remark':
    case 'note':
      return 'Note';
    case 'qrcode':
    case 'qr_code':
      return 'QR Code';
    default:
      if (field.label.trim().isNotEmpty && !_withdrawContainsHan(field.label)) {
        return field.label.trim();
      }
      return _withdrawTitleFromKey(key);
  }
}

String _localizedWithdrawFieldHint(
    BuildContext context, FormFieldConfig field) {
  final rawHint = field.hint?.trim() ?? '';
  if (AppLocalizations.of(context).language != AppLanguage.en) {
    return rawHint;
  }
  if (rawHint.isNotEmpty && !_withdrawContainsHan(rawHint)) {
    return rawHint;
  }
  final label = _localizedWithdrawFieldLabel(context, field);
  return field.type == FormFieldType.select ? 'Select $label' : 'Enter $label';
}

// 关键声明：withdraw page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 提现方式类型
enum WithdrawMethodType {
  alipay,
  wechat,
  bankCard,
  custom,
}

/// 表单字段类型
enum FormFieldType {
  text,
  phone,
  number,
  idCard,
  bankCard,
  select,
}

/// 表单字段配置
class FormFieldConfig {
  final String key;
  final String label;
  final String? hint;
  final FormFieldType type;
  final bool required;
  final List<String>? options; // 用于 select 类型
  final int? maxLength;
  final String? regex; // 验证正则

  const FormFieldConfig({
    required this.key,
    required this.label,
    this.hint,
    this.type = FormFieldType.text,
    this.required = true,
    this.options,
    this.maxLength,
    this.regex,
  });
}

/// 提现方式配置
class WithdrawMethodConfig {
  final String id;
  final String name;
  final String icon;
  final WithdrawMethodType type;
  final List<FormFieldConfig> fields;
  final double? minAmount;
  final double? maxAmount;
  final String? tips;
  final bool enabled;

  const WithdrawMethodConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.fields,
    this.minAmount,
    this.maxAmount,
    this.tips,
    this.enabled = true,
  });
}

/// 提现页面
class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  static const _withdrawAmounts = <int>[200, 300, 500, 1000, 3000, 5000];

  String get _currency => ref.read(walletCurrencyProvider);
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fieldControllers = {};
  final Map<String, String?> _fieldValues = {};

  WithdrawMethodConfig? _selectedMethod;
  PayoutAccount? _selectedPayoutAccount;
  bool _isLoading = false;

  List<WithdrawMethodConfig> _withdrawMethods = [];
  bool _isLoadingMethods = true;
  String? _methodsLoadError;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadMethodsFromServer();
  }

  /// 从后端 API 加载提现方式
  Future<void> _loadMethodsFromServer() async {
    try {
      final walletService = ref.read(walletServiceProvider);
      final response = await walletService.getWithdrawMethods();
      debugPrint(
        '[Withdraw] Methods response: code=${response.code}, '
        'count=${response.data?.length ?? 0}, message=${response.message}',
      );
      if (response.isSuccess && response.data != null && mounted) {
        final methods = response.data!.map((m) {
          // 从后端 JSON fields 解析表单字段
          List<FormFieldConfig> fields = [];
          try {
            final fieldsList = jsonDecode(m.fields) as List;
            fields = fieldsList.map((f) {
              final map = f as Map<String, dynamic>;
              return FormFieldConfig(
                key: map['key'] as String? ?? '',
                label: map['label'] as String? ?? '',
                hint: map['hint'] as String?,
                type: _parseFieldType(map['type'] as String? ?? 'text'),
                required: map['required'] as bool? ?? true,
                options: (map['options'] as List?)?.cast<String>(),
                maxLength: map['maxLength'] as int?,
                regex: map['regex'] as String?,
              );
            }).toList();
          } catch (e) {
            debugPrint('[Withdraw] Parse form fields error: $e');
          }

          return WithdrawMethodConfig(
            id: m.id.toString(),
            name: m.name,
            icon: m.icon ?? m.name.toLowerCase(),
            type: WithdrawMethodType.custom,
            fields: fields,
            minAmount: m.minAmount,
            maxAmount: m.maxAmount,
            tips: m.fee > 0
                ? _withdrawText(
                    context,
                    zhCN: '手续费 ${m.fee}%',
                    zhTW: '手續費 ${m.fee}%',
                    en: 'Fee ${m.fee}%',
                  )
                : _withdrawText(
                    context,
                    zhCN: '免手续费',
                    zhTW: '免手續費',
                    en: 'No fee',
                  ),
            enabled: m.status == 1,
          );
        }).toList();
        if (!mounted) return;
        setState(() {
          _withdrawMethods = methods;
          _isLoadingMethods = false;
        });
        final enabled = methods.where((m) => m.enabled).toList();
        if (enabled.isNotEmpty) _selectMethod(enabled.first);
      } else {
        debugPrint('[Withdraw] Methods unavailable: ${response.message}');
        if (mounted) {
          setState(() {
            _isLoadingMethods = false;
            _methodsLoadError = response.message.trim().isEmpty
                ? _withdrawText(
                    context,
                    zhCN: '提现方式加载失败',
                    zhTW: '提現方式載入失敗',
                    en: 'Failed to load withdrawal methods',
                  )
                : response.message;
          });
        }
      }
    } catch (e) {
      debugPrint('[Withdraw] Load methods error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMethods = false;
          _methodsLoadError = _withdrawText(
            context,
            zhCN: '提现方式加载失败，请稍后重试',
            zhTW: '提現方式載入失敗，請稍後重試',
            en: 'Failed to load withdrawal methods. Please try again later.',
          );
        });
      }
    }
  }

  FormFieldType _parseFieldType(String type) {
    switch (type) {
      case 'phone':
        return FormFieldType.phone;
      case 'number':
        return FormFieldType.number;
      case 'bankCard':
        return FormFieldType.bankCard;
      case 'idCard':
        return FormFieldType.idCard;
      case 'select':
        return FormFieldType.select;
      default:
        return FormFieldType.text;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectMethod(WithdrawMethodConfig method) {
    // 清理旧的控制器
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    _fieldControllers.clear();
    _fieldValues.clear();
    _selectedPayoutAccount = null;

    // 创建新的控制器
    for (final field in method.fields) {
      _fieldControllers[field.key] = TextEditingController();
    }

    setState(() {
      _selectedMethod = method;
    });
  }

  double get _amount {
    return double.tryParse(_amountController.text) ?? 0;
  }

  void _selectAmount(int amount) {
    _amountController.text = amount.toString();
    setState(() {});
  }

  bool get _canSubmit {
    if (_selectedMethod == null) return false;
    if (_usesBoundAccount) {
      final accounts = ref.read(payoutAccountsProvider).valueOrNull ??
          const <PayoutAccount>[];
      final account = _selectedPayoutAccount;
      if (account == null ||
          account.type != _boundAccountType ||
          !accounts.any((item) => item.id == account.id)) {
        return false;
      }
    }
    if (!_withdrawAmounts.contains(_amount.toInt()) ||
        _amount != _amount.toInt()) {
      return false;
    }

    // 检查金额限制
    if (_selectedMethod!.minAmount != null &&
        _amount < _selectedMethod!.minAmount!) {
      return false;
    }
    if (_selectedMethod!.maxAmount != null &&
        _amount > _selectedMethod!.maxAmount!) {
      return false;
    }

    // 检查必填字段
    if (!_usesBoundAccount) {
      for (final field in _selectedMethod!.fields) {
        if (field.required) {
          final value = _fieldControllers[field.key]?.text ?? '';
          if (value.isEmpty) return false;
        }
      }
    }

    return true;
  }

  bool get _usesBoundAccount {
    final method = _selectedMethod;
    if (method == null) return false;
    final fingerprint = '${method.name} ${method.icon}'.toLowerCase();
    return fingerprint.contains('alipay') ||
        fingerprint.contains('支付宝') ||
        fingerprint.contains('bank') ||
        fingerprint.contains('card') ||
        fingerprint.contains('银行卡') ||
        fingerprint.contains('银行');
  }

  PayoutAccountType? get _boundAccountType {
    if (!_usesBoundAccount) return null;
    final fingerprint =
        '${_selectedMethod!.name} ${_selectedMethod!.icon}'.toLowerCase();
    return fingerprint.contains('alipay') || fingerprint.contains('支付宝')
        ? PayoutAccountType.alipay
        : PayoutAccountType.bank;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    // 验证表单
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // 显示密码输入
    final password = await showPayPasswordDialog(
      context: context,
      title: _withdrawText(
        context,
        zhCN: '确认提现',
        zhTW: '確認提現',
        en: 'Confirm Withdrawal',
      ),
      amount: '$_currency${_amount.toStringAsFixed(2)}',
      subtitle: _withdrawText(
        context,
        zhCN: '提现至${_selectedMethod!.name}',
        zhTW: '提現至${_selectedMethod!.name}',
        en: 'Withdraw to ${_localizedWithdrawMethodName(context, _selectedMethod!)}',
      ),
    );

    if (password == null) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    // 收集表单数据（密码由服务端在 createWithdrawRequest 中一并校验，避免两次明文传输）
    final formData = <String, String>{};
    for (final field in _selectedMethod!.fields) {
      formData[field.key] = _fieldControllers[field.key]?.text ?? '';
    }

    try {
      // 调用提现API
      final success =
          await ref.read(walletProvider.notifier).createWithdrawRequest(
                methodId: int.tryParse(_selectedMethod!.id) ?? 0,
                amount: _amount,
                formData: _usesBoundAccount ? null : jsonEncode(formData),
                payoutAccountId: _selectedPayoutAccount?.id,
                payPassword: password,
              );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(walletProvider).error ??
                  _withdrawText(
                    context,
                    zhCN: '提现申请失败',
                    zhTW: '提現申請失敗',
                    en: 'Withdrawal request failed',
                  ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _withdrawText(
                context,
                zhCN: '提现申请失败: $e',
                zhTW: '提現申請失敗: $e',
                en: 'Withdrawal request failed: $e',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Widget _buildPayoutAccountSelector(
    AsyncValue<List<PayoutAccount>> payoutAccounts,
  ) {
    final expectedType = _boundAccountType;
    final accounts = payoutAccounts.valueOrNull
            ?.where((account) => account.type == expectedType)
            .toList() ??
        const <PayoutAccount>[];

    if (payoutAccounts.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.emphasisSoftFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _withdrawText(
                  context,
                  zhCN: expectedType == PayoutAccountType.alipay
                      ? '请先绑定支付宝账户'
                      : '请先绑定银行卡',
                  zhTW: expectedType == PayoutAccountType.alipay
                      ? '請先綁定支付寶帳戶'
                      : '請先綁定銀行卡',
                  en: expectedType == PayoutAccountType.alipay
                      ? 'Bind an Alipay account first'
                      : 'Bind a bank card first',
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => WithdrawAccountFormPage(
                      type: expectedType ?? PayoutAccountType.bank,
                    ),
                  ),
                );
                if (saved == true && mounted) {
                  ref.invalidate(payoutAccountsProvider);
                }
              },
              child: Text(
                _withdrawText(
                  context,
                  zhCN: '去绑定',
                  zhTW: '去綁定',
                  en: 'Bind now',
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selected =
        accounts.any((account) => account.id == _selectedPayoutAccount?.id)
            ? _selectedPayoutAccount
            : null;
    return DropdownButtonFormField<int>(
      value: selected?.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _withdrawText(
          context,
          zhCN: '选择已绑定账户',
          zhTW: '選擇已綁定帳戶',
          en: 'Select bound account',
        ),
        filled: true,
        fillColor: AppColors.inputBackgroundFor(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: accounts
          .map(
            (account) => DropdownMenuItem<int>(
              value: account.id,
              child: Text(
                '${account.accountName}  ${account.maskedAccountNo}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id == null) return;
        setState(() {
          _selectedPayoutAccount =
              accounts.firstWhere((account) => account.id == id);
        });
      },
      validator: (_) => _selectedPayoutAccount == null
          ? _withdrawText(
              context,
              zhCN: '请选择提现账户',
              zhTW: '請選擇提現帳戶',
              en: 'Select a withdrawal account',
            )
          : null,
    );
  }

  void _showSuccessDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 36,
                  color: Color(0xFF34C759),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _withdrawText(
                  context,
                  zhCN: '提现申请已提交',
                  zhTW: '提現申請已提交',
                  en: 'Withdrawal request submitted',
                ),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _withdrawText(
                  context,
                  zhCN: '预计${_selectedMethod?.tips ?? "1-3个工作日到账"}',
                  zhTW: '預計${_selectedMethod?.tips ?? "1-3個工作日到帳"}',
                  en: 'Estimated ${_selectedMethod?.tips ?? "1-3 business days"}',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryFor(context),
                    foregroundColor: AppColors.onPrimaryFor(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _withdrawText(
                      context,
                      zhCN: '完成',
                      zhTW: '完成',
                      en: 'Done',
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(walletCurrencyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);
    final payoutAccounts = ref.watch(payoutAccountsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceFor(context),
        elevation: 0,
        title: Text(
          _withdrawText(
            context,
            zhCN: '提现',
            zhTW: '提現',
            en: 'Withdraw',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: AppColors.textPrimaryFor(context),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 可用余额
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardFor(context),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.emphasisSoftFor(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet,
                          color: AppColors.linkFor(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _withdrawText(
                              context,
                              zhCN: '可提现余额',
                              zhTW: '可提現餘額',
                              en: 'Available Balance',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_currency${(walletState.wallet?.balance ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimaryFor(context),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 提现金额
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardFor(context),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _withdrawText(
                          context,
                          zhCN: '提现金额',
                          zhTW: '提現金額',
                          en: 'Withdrawal Amount',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _withdrawAmounts.map((amount) {
                          final selected = _amount == amount;
                          return ChoiceChip(
                            label: Text('$_currency$amount'),
                            selected: selected,
                            onSelected: (_) => _selectAmount(amount),
                            selectedColor: AppColors.primaryFor(context),
                            labelStyle: TextStyle(
                              color: selected
                                  ? AppColors.onPrimaryFor(context)
                                  : AppColors.textPrimaryFor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _withdrawText(
                          context,
                          zhCN: '仅支持固定金额：200、300、500、1000、3000、5000',
                          zhTW: '僅支援固定金額：200、300、500、1000、3000、5000',
                          en: 'Fixed amounts only: 200, 300, 500, 1000, 3000, 5000',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 提现方式和表单
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardFor(context),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 提现方式下拉选择
                      Text(
                        _withdrawText(
                          context,
                          zhCN: '提现方式',
                          zhTW: '提現方式',
                          en: 'Withdrawal Method',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildMethodDropdown(isDark),

                      if (_selectedMethod != null) ...[
                        const SizedBox(height: 24),
                        Divider(
                          color: AppColors.dividerFor(context),
                        ),
                        const SizedBox(height: 16),

                        // 绑定收款账户优先；其他提现方式继续使用旧版动态表单。
                        Text(
                          _withdrawText(
                            context,
                            zhCN: '收款信息',
                            zhTW: '收款資訊',
                            en: 'Payout Info',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_usesBoundAccount)
                          _buildPayoutAccountSelector(payoutAccounts)
                        else
                          ..._selectedMethod!.fields.map(
                            (field) => _buildFormField(field, isDark),
                          ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  _withdrawText(
                    context,
                    zhCN: '提现申请时间：每日北京时间 8:00–20:00，具体以后台审核为准',
                    zhTW: '提現申請時間：每日北京時間 8:00–20:00，具體以後台審核為準',
                    en: 'Withdrawal requests are accepted daily from 8:00 to 20:00 Beijing time. Server rules prevail.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiaryFor(context),
                  ),
                ),
                const SizedBox(height: 10),

                // 提交按钮
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading || !_canSubmit ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryFor(context),
                      foregroundColor: AppColors.onPrimaryFor(context),
                      disabledBackgroundColor: AppColors.dividerFor(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimaryFor(context),
                            ),
                          )
                        : Text(
                            _amount > 0
                                ? _withdrawText(
                                    context,
                                    zhCN:
                                        '提现 $_currency${_amount.toStringAsFixed(2)}',
                                    zhTW:
                                        '提現 $_currency${_amount.toStringAsFixed(2)}',
                                    en: 'Withdraw $_currency${_amount.toStringAsFixed(2)}',
                                  )
                                : _withdrawText(
                                    context,
                                    zhCN: '提现',
                                    zhTW: '提現',
                                    en: 'Withdraw',
                                  ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                // 提示信息
                if (_selectedMethod?.tips != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: AppColors.textTertiaryFor(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedMethod!.tips!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodDropdown(bool isDark) {
    return GestureDetector(
      onTap: () => _showMethodPicker(isDark),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.inputBackgroundFor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedMethod != null
                ? AppColors.controlActiveFor(context).withOpacity(0.3)
                : AppColors.controlBorderFor(context),
            width: _selectedMethod != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (_selectedMethod != null) ...[
              _buildMethodIcon(_selectedMethod!.icon, true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedWithdrawMethodName(context, _selectedMethod!),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    if (_selectedMethod!.tips != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _selectedMethod!.tips!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 22,
                color: AppColors.inputIconFor(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _withdrawText(
                    context,
                    zhCN: '请选择提现方式',
                    zhTW: '請選擇提現方式',
                    en: 'Please select a withdrawal method',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.inputHintFor(context),
                  ),
                ),
              ),
            ],
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.inputIconFor(context),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _showMethodPicker(bool isDark) {
    final enabledMethods = _withdrawMethods.where((m) => m.enabled).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _withdrawText(
                    context,
                    zhCN: '选择提现方式',
                    zhTW: '選擇提現方式',
                    en: 'Select Withdrawal Method',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: AppColors.dividerFor(context),
              ),
              // 选项列表
              if (enabledMethods.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  child: Text(
                    _methodsLoadError ??
                        _withdrawText(
                          context,
                          zhCN: '暂无可用提现方式，请联系管理员配置',
                          zhTW: '暫無可用提現方式，請聯繫管理員配置',
                          en: 'No withdrawal methods are available. Please contact an administrator.',
                        ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                )
              else
                ...enabledMethods.map((method) {
                  final isSelected = _selectedMethod?.id == method.id;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _selectMethod(method);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            _buildMethodIcon(method.icon, isSelected),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _localizedWithdrawMethodName(
                                        context, method),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimaryFor(context),
                                    ),
                                  ),
                                  if (method.tips != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      method.tips!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            AppColors.textTertiaryFor(context),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: AppColors.controlActiveFor(context),
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodIcon(String icon, bool isSelected) {
    IconData iconData;
    Color iconColor;
    Color bgColor;

    switch (icon) {
      case 'alipay':
        iconData = Icons.account_balance_wallet;
        iconColor = Colors.white;
        bgColor = const Color(0xFF1677FF);
        break;
      case 'wechat':
        iconData = Icons.chat_bubble;
        iconColor = Colors.white;
        bgColor = const Color(0xFF07C160);
        break;
      case 'bank':
        iconData = Icons.account_balance;
        iconColor = Colors.white;
        bgColor = const Color(0xFFFF6B00);
        break;
      default:
        iconData = Icons.payment;
        iconColor = Colors.white;
        bgColor = AppColors.primaryFor(context);
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(iconData, size: 20, color: iconColor),
    );
  }

  Widget _buildFormField(FormFieldConfig field, bool isDark) {
    final controller = _fieldControllers[field.key];

    if (field.type == FormFieldType.select) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localizedWithdrawFieldLabel(context, field),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.inputBackgroundFor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.controlBorderFor(context),
                ),
              ),
              child: DropdownButtonFormField<String>(
                value: _fieldValues[field.key],
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  hintText: _localizedWithdrawFieldHint(context, field),
                  hintStyle: TextStyle(
                    color: AppColors.inputHintFor(context),
                  ),
                ),
                dropdownColor: AppColors.cardFor(context),
                items: field.options?.map((option) {
                  return DropdownMenuItem(
                    value: option,
                    child: Text(
                      option,
                      style: TextStyle(
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _fieldValues[field.key] = value;
                    controller?.text = value ?? '';
                  });
                },
                validator: field.required
                    ? (value) {
                        if (value == null || value.isEmpty) {
                          return _withdrawText(
                            context,
                            zhCN: '请选择${field.label}',
                            zhTW: '請選擇${field.label}',
                            en: 'Please select ${_localizedWithdrawFieldLabel(context, field)}',
                          );
                        }
                        return null;
                      }
                    : null,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localizedWithdrawFieldLabel(context, field),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: _getKeyboardType(field.type),
            maxLength: field.maxLength,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textPrimaryFor(context),
            ),
            decoration: InputDecoration(
              hintText: _localizedWithdrawFieldHint(context, field),
              hintStyle: TextStyle(
                color: AppColors.inputHintFor(context),
              ),
              filled: true,
              fillColor: AppColors.inputBackgroundFor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.controlBorderFor(context),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.controlBorderFor(context),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.controlActiveFor(context),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              counterText: '',
            ),
            inputFormatters: _getInputFormatters(field.type),
            validator: (value) {
              if (field.required && (value == null || value.isEmpty)) {
                return _withdrawText(
                  context,
                  zhCN: '请输入${field.label}',
                  zhTW: '請輸入${field.label}',
                  en: 'Please enter ${_localizedWithdrawFieldLabel(context, field)}',
                );
              }
              if (value != null && value.isNotEmpty && field.regex != null) {
                try {
                  if (!RegExp(field.regex!).hasMatch(value)) {
                    return _withdrawText(
                      context,
                      zhCN: '${field.label}格式不正确',
                      zhTW: '${field.label}格式不正確',
                      en: '${_localizedWithdrawFieldLabel(context, field)} format is invalid',
                    );
                  }
                } catch (_) {}
              }
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  TextInputType _getKeyboardType(FormFieldType type) {
    switch (type) {
      case FormFieldType.phone:
        return TextInputType.phone;
      case FormFieldType.number:
      case FormFieldType.bankCard:
        return TextInputType.number;
      case FormFieldType.idCard:
        return TextInputType.text;
      default:
        return TextInputType.text;
    }
  }

  List<TextInputFormatter> _getInputFormatters(FormFieldType type) {
    switch (type) {
      case FormFieldType.phone:
        return [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11)
        ];
      case FormFieldType.number:
        return [FilteringTextInputFormatter.digitsOnly];
      case FormFieldType.bankCard:
        return [FilteringTextInputFormatter.digitsOnly];
      case FormFieldType.idCard:
        return [FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx]'))];
      default:
        return [];
    }
  }
}
