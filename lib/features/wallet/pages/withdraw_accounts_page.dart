import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';

String _withdrawAccountsText(BuildContext context,
    {required String zhCN, String? zhTW, required String en}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

enum _AccountType { bankCard, alipay }

class WithdrawAccountsPage extends ConsumerWidget {
  const WithdrawAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(payoutAccountsProvider);
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.primaryFor(context),
        foregroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
            _withdrawAccountsText(context,
                zhCN: '提现账户', zhTW: '提現帳戶', en: 'Withdrawal Accounts'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(payoutAccountsProvider.future),
        child: accounts.when(
          loading: () => ListView(children: const [
            SizedBox(height: 260),
            Center(child: CircularProgressIndicator())
          ]),
          error: (error, _) =>
              ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 120),
            Center(
                child: Text(_withdrawAccountsText(context,
                    zhCN: '加载提现账户失败',
                    zhTW: '載入提現帳戶失敗',
                    en: 'Failed to load withdrawal accounts'))),
            const SizedBox(height: 12),
            Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(payoutAccountsProvider),
                    child: Text(_withdrawAccountsText(context,
                        zhCN: '重新加载', zhTW: '重新載入', en: 'Retry')))),
          ]),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              _buildNotice(context),
              const SizedBox(height: 18),
              if (items.isEmpty)
                _EmptyAccounts(context: context)
              else ...[
                ...items.map((account) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AccountTile(account: account))),
                const SizedBox(height: 4),
              ],
              _AddAccountButton(onTap: () => _showTypePicker(context, ref)),
              const SizedBox(height: 16),
              Text(
                  _withdrawAccountsText(context,
                      zhCN: '账号信息由后台安全保存，页面仅显示脱敏账号。提现时可直接选择已绑定账户。',
                      zhTW: '帳號資訊由後台安全保存，頁面僅顯示脫敏帳號。提現時可直接選擇已綁定帳戶。',
                      en:
                          'Account information is securely stored by the server. Only masked accounts are shown.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textTertiaryFor(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotice(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.emphasisSoftFor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.controlBorderFor(context))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, color: AppColors.linkFor(context)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(
                  _withdrawAccountsText(context,
                      zhCN: '请绑定本人实名账户，仅支持银行卡或支付宝。',
                      zhTW: '請綁定本人實名帳戶，僅支援銀行卡或支付寶。',
                      en:
                          'Bind an account registered in your real name. Bank cards and Alipay are supported.'),
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondaryFor(context)))),
        ]),
      );

  void _showTypePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: Text(_withdrawAccountsText(context,
                      zhCN: '绑定银行卡', zhTW: '綁定銀行卡', en: 'Bind bank card')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openForm(context, ref, PayoutAccountType.bank);
                  }),
              ListTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: Text(_withdrawAccountsText(context,
                      zhCN: '绑定支付宝', zhTW: '綁定支付寶', en: 'Bind Alipay')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openForm(context, ref, PayoutAccountType.alipay);
                  }),
              const SizedBox(height: 8),
            ])));
  }

  void _openForm(BuildContext context, WidgetRef ref, PayoutAccountType type) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => WithdrawAccountFormPage(type: type)))
        .then((saved) {
      if (saved == true) ref.invalidate(payoutAccountsProvider);
    });
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.context});
  final BuildContext context;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(children: [
        Icon(Icons.account_balance_wallet_outlined,
            size: 52, color: AppColors.textTertiaryFor(context)),
        const SizedBox(height: 12),
        Text(
            _withdrawAccountsText(context,
                zhCN: '暂无绑定账户', zhTW: '暫無綁定帳戶', en: 'No bound accounts'),
            style: TextStyle(color: AppColors.textSecondaryFor(context)))
      ]));
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});
  final PayoutAccount account;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBank = account.type == PayoutAccountType.bank;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: isBank
                      ? const Color(0xFFFF6B00)
                      : const Color(0xFF1677FF),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(
                  isBank ? Icons.account_balance : Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 23)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    isBank
                        ? (account.bankName?.isNotEmpty == true
                            ? account.bankName!
                            : '银行卡')
                        : '支付宝',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context))),
                const SizedBox(height: 4),
                Text('${account.accountName}  ${account.maskedAccountNo}',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryFor(context))),
                if (account.isDefault)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          _withdrawAccountsText(context,
                              zhCN: '默认账户', zhTW: '預設帳戶', en: 'Default'),
                          style: TextStyle(
                              fontSize: 12, color: AppColors.linkFor(context))))
              ])),
          PopupMenuButton<String>(
              onSelected: (action) => _handleAction(context, ref, action),
              itemBuilder: (_) => [
                    if (!account.isDefault)
                      PopupMenuItem(
                          value: 'default',
                          child: Text(_withdrawAccountsText(context,
                              zhCN: '设为默认',
                              zhTW: '設為預設',
                              en: 'Set as default'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text(_withdrawAccountsText(context,
                            zhCN: '删除', zhTW: '刪除', en: 'Delete')))
                  ]),
        ]));
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    final service = ref.read(walletServiceProvider);
    if (action == 'default') {
      final response = await service.setDefaultPayoutAccount(account);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response.isSuccess
              ? _withdrawAccountsText(context,
                  zhCN: '已设为默认账户',
                  zhTW: '已設為預設帳戶',
                  en: 'Default account updated')
              : response.message)));
      if (response.isSuccess) ref.invalidate(payoutAccountsProvider);
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(_withdrawAccountsText(context,
                    zhCN: '删除提现账户？',
                    zhTW: '刪除提現帳戶？',
                    en: 'Delete withdrawal account?')),
                content: Text(account.maskedAccountNo),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(_withdrawAccountsText(context,
                          zhCN: '取消', zhTW: '取消', en: 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(_withdrawAccountsText(context,
                          zhCN: '删除', zhTW: '刪除', en: 'Delete')))
                ]));
    if (confirmed != true || !context.mounted) return;
    final response = await service.deletePayoutAccount(account.id);
    if (!context.mounted) return;
    if (response.isSuccess) ref.invalidate(payoutAccountsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(response.isSuccess
            ? _withdrawAccountsText(context,
                zhCN: '已删除', zhTW: '已刪除', en: 'Deleted')
            : response.message)));
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add),
          label: Text(_withdrawAccountsText(context,
              zhCN: '添加提现账户', zhTW: '新增提現帳戶', en: 'Add withdrawal account')),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.linkFor(context),
              side: BorderSide(color: AppColors.controlActiveFor(context)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))));
}

class WithdrawAccountFormPage extends ConsumerStatefulWidget {
  const WithdrawAccountFormPage({super.key, required this.type});
  final PayoutAccountType type;
  @override
  ConsumerState<WithdrawAccountFormPage> createState() =>
      _WithdrawAccountFormPageState();
}

class _WithdrawAccountFormPageState
    extends ConsumerState<WithdrawAccountFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  final _bankController = TextEditingController();
  final _branchController = TextEditingController();
  bool _isLoading = false;
  bool _isDefault = true;
  bool get _isBank => widget.type == PayoutAccountType.bank;
  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    _bankController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.primaryFor(context),
        foregroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _withdrawAccountsText(
            context,
            zhCN: _isBank ? '绑定银行卡' : '绑定支付宝',
            zhTW: _isBank ? '綁定銀行卡' : '綁定支付寶',
            en: _isBank ? 'Bind Bank Card' : 'Bind Alipay',
          ),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            Text(
              _withdrawAccountsText(context,
                  zhCN: '请填写本人实名收款信息',
                  zhTW: '請填寫本人實名收款資訊',
                  en: 'Enter your real-name payout information'),
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondaryFor(context)),
            ),
            const SizedBox(height: 14),
            _field(_nameController, _isBank ? '持卡人姓名' : '支付宝实名姓名',
                _isBank ? '请输入持卡人姓名' : '请输入支付宝实名姓名'),
            _field(_accountController, _isBank ? '银行卡号' : '支付宝账号',
                _isBank ? '请输入银行卡号' : '请输入手机号或邮箱',
                keyboard:
                    _isBank ? TextInputType.number : TextInputType.emailAddress,
                formatters:
                    _isBank ? [FilteringTextInputFormatter.digitsOnly] : null),
            if (_isBank) ...[
              _field(_bankController, '开户银行', '请输入开户银行'),
              _field(_branchController, '开户支行', '请输入开户支行'),
            ],
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
                title: Text(_withdrawAccountsText(context,
                    zhCN: '设为默认提现账户',
                    zhTW: '設為預設提現帳戶',
                    en: 'Set as default withdrawal account'))),
            const SizedBox(height: 18),
            SizedBox(
                height: 50,
                child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(_withdrawAccountsText(context,
                            zhCN: '确认绑定',
                            zhTW: '確認綁定',
                            en: 'Confirm Binding')))),
            const SizedBox(height: 12),
            Text(
                _withdrawAccountsText(context,
                    zhCN: '完整账号仅用于提交绑定，不会保存在手机本地。',
                    zhTW: '完整帳號僅用於提交綁定，不會保存在手機本地。',
                    en:
                        'The full account number is only used for binding and is not stored locally.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiaryFor(context))),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: formatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppColors.inputBackgroundFor(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? _withdrawAccountsText(
                    context,
                    zhCN: '请输入$label',
                    zhTW: '請輸入$label',
                    en: 'Please enter $label',
                  )
                : null
            : null,
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    final response = await ref.read(walletServiceProvider).createPayoutAccount(
        type: widget.type,
        accountName: _nameController.text.trim(),
        accountNo: _accountController.text.trim(),
        bankName: _isBank ? _bankController.text.trim() : null,
        branchName: _isBank ? _branchController.text.trim() : null,
        isDefault: _isDefault);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (response.isSuccess) {
      Navigator.pop(context, true);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(response.message)));
  }
}
