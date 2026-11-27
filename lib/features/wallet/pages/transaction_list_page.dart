// 文件用途：实现 TransactionListPage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 TransactionListPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';

/// 交易记录列表页面
String _transactionText(
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

// 关键声明：transaction list page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class TransactionListPage extends ConsumerStatefulWidget {
  const TransactionListPage({super.key});

  @override
  ConsumerState<TransactionListPage> createState() =>
      _TransactionListPageState();
}

class _TransactionListPageState extends ConsumerState<TransactionListPage> {
  final _scrollController = ScrollController();

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadTransactions();
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(walletProvider);
      if (!state.isTransactionsLoading && state.hasMoreTransactions) {
        ref.read(walletProvider.notifier).loadTransactions(loadMore: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        title: Text(
          _transactionText(
            context,
            zhCN: '交易记录',
            zhTW: '交易記錄',
            en: 'Transaction History',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(isDark, walletState),
    );
  }

  Widget _buildBody(bool isDark, WalletState state) {
    if (state.isTransactionsLoading && state.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: AppColors.textTertiaryFor(context).withOpacity(0.72),
            ),
            const SizedBox(height: 16),
            Text(
              _transactionText(
                context,
                zhCN: '暂无交易记录',
                zhTW: '暫無交易記錄',
                en: 'No transaction history yet',
              ),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(walletProvider.notifier).loadTransactions(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount:
            state.transactions.length + (state.isTransactionsLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.transactions.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildTransactionItem(isDark, state.transactions[index]);
        },
      ),
    );
  }

  /// 获取交易类型对应的颜色（按类型区分，金额正负另看 amount）
  Color _getTransactionColor(TransactionType type) {
    switch (type) {
      case TransactionType.redPacketSend:
      case TransactionType.redPacketReceive:
        return const Color(0xFFE84C3D);
      case TransactionType.transferOut:
      case TransactionType.transferIn:
        return const Color(0xFFFFA940);
      case TransactionType.recharge:
      case TransactionType.adminRecharge:
        return const Color(0xFF07C160);
      case TransactionType.checkInReward:
        return const Color(0xFFFAAD14);
      case TransactionType.withdraw:
        return const Color(0xFF4A90D9);
      case TransactionType.adminDeduct:
        return const Color(0xFF5C6BC0);
      case TransactionType.vipPurchase:
        return const Color(0xFF9B59B6);
      case TransactionType.refund:
        return const Color(0xFF13C2C2);
      case TransactionType.rechargeRejected:
        return const Color(0xFFF56C6C);
      case TransactionType.unknown:
        return const Color(0xFF8E8E93);
    }
  }

  Widget _buildTransactionItem(bool isDark, Transaction transaction) {
    final amount = transaction.amount;
    final isIncome = amount > 0;
    final icon = _getTransactionIcon(transaction.type);
    final typeLabel = _getTransactionTypeLabel(context, transaction.type);
    final typeColor = _getTransactionColor(transaction.type);
    final amountText = amount > 0
        ? '+${amount.toStringAsFixed(2)}'
        : amount.toStringAsFixed(2);
    // 提现 / 签到奖励：只显示主标题，不渲染 remark（如「连续签到7天奖励」）
    final showRemark = !transaction.type.hideRemarkSubtitle &&
        transaction.remark != null &&
        transaction.remark!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      ),
      child: Row(
        children: [
          // 彩色图标（前端按 type 映射，非接口下发）
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: typeColor, size: 20),
          ),

          const SizedBox(width: 12),

          // 类型和备注
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF1D1D1F),
                  ),
                ),
                if (showRemark) ...[
                  const SizedBox(height: 2),
                  Text(
                    transaction.remark!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiaryFor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // 金额和时间
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isIncome
                      ? const Color(0xFF07C160)
                      : (isDark ? Colors.white : const Color(0xFF1D1D1F)),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatBeijingTime(context, transaction.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getTransactionIcon(TransactionType type) {
    switch (type) {
      case TransactionType.recharge:
        return Icons.account_balance_wallet_outlined;
      case TransactionType.adminRecharge:
        return Icons.add_circle_outline;
      case TransactionType.checkInReward:
        return Icons.event_available_outlined;
      case TransactionType.withdraw:
        return Icons.payments_outlined;
      case TransactionType.adminDeduct:
        return Icons.remove_circle_outline;
      case TransactionType.vipPurchase:
        return Icons.workspace_premium_outlined;
      case TransactionType.redPacketSend:
        return Icons.card_giftcard_outlined;
      case TransactionType.redPacketReceive:
        return Icons.redeem;
      case TransactionType.transferOut:
        return Icons.call_made_rounded;
      case TransactionType.transferIn:
        return Icons.call_received_rounded;
      case TransactionType.refund:
        // 退款：货币兑换/回退语义，区别于普通重播箭头
        return Icons.currency_exchange;
      case TransactionType.rechargeRejected:
        return Icons.cancel_outlined;
      case TransactionType.unknown:
        return Icons.receipt_long_outlined;
    }
  }

  String _getTransactionTypeLabel(BuildContext context, TransactionType type) {
    switch (type) {
      case TransactionType.recharge:
        return _transactionText(context,
            zhCN: '充值', zhTW: '充值', en: 'Recharge');
      case TransactionType.withdraw:
        return _transactionText(context,
            zhCN: '提现', zhTW: '提現', en: 'Withdraw');
      case TransactionType.transferOut:
        return _transactionText(context,
            zhCN: '转账转出', zhTW: '轉帳轉出', en: 'Transfer Out');
      case TransactionType.transferIn:
        return _transactionText(context,
            zhCN: '转账转入', zhTW: '轉帳轉入', en: 'Transfer In');
      case TransactionType.redPacketSend:
        return _transactionText(context,
            zhCN: '发出红包', zhTW: '發出紅包', en: 'Sent Red Packet');
      case TransactionType.redPacketReceive:
        return _transactionText(context,
            zhCN: '领取红包', zhTW: '領取紅包', en: 'Received Red Packet');
      case TransactionType.refund:
        return _transactionText(context, zhCN: '退款', zhTW: '退款', en: 'Refund');
      case TransactionType.adminRecharge:
        return _transactionText(context,
            zhCN: '后台充值', zhTW: '後台儲值', en: 'Admin Recharge');
      case TransactionType.adminDeduct:
        return _transactionText(context,
            zhCN: '后台扣款', zhTW: '後台扣款', en: 'Admin Deduction');
      case TransactionType.rechargeRejected:
        return _transactionText(context,
            zhCN: '充值被拒绝', zhTW: '充值被拒絕', en: 'Recharge Rejected');
      case TransactionType.vipPurchase:
        return _transactionText(context,
            zhCN: '会员购买', zhTW: '會員購買', en: 'VIP Purchase');
      case TransactionType.checkInReward:
        return _transactionText(context,
            zhCN: '签到奖励', zhTW: '簽到獎勵', en: 'Check-in Reward');
      case TransactionType.unknown:
        return _transactionText(context,
            zhCN: '交易记录', zhTW: '交易記錄', en: 'Transaction');
    }
  }

  /// 固定 Asia/Shanghai（UTC+8，无夏令时）完整时间，不受手机时区影响。
  String _formatBeijingTime(BuildContext context, DateTime? time) {
    if (time == null) {
      return _transactionText(
        context,
        zhCN: '未知时间',
        zhTW: '未知時間',
        en: 'Unknown time',
      );
    }
    final shanghai = time.toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${shanghai.year}-${two(shanghai.month)}-${two(shanghai.day)} '
        '${two(shanghai.hour)}:${two(shanghai.minute)}:${two(shanghai.second)}';
  }
}
