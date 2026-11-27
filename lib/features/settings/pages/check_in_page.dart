// 文件用途：提供每日签到状态、签到操作和历史记录展示。
// 核心逻辑：以服务端北京时间状态为准，防止重复提交，不在本地推导签到统计。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../identity/pages/real_name_page.dart';
import '../services/check_in_service.dart';

String _checkInText(BuildContext context,
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

class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({super.key});

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage>
    with WidgetsBindingObserver {
  CheckInStatus? _status;
  List<CheckInHistoryItem> _history = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    final service = ref.read(checkInServiceProvider);
    try {
      final responses = await Future.wait([
        service.getStatus(),
        service.getHistory(page: 1, pageSize: 20),
      ]);
      if (!mounted) return;
      final statusResponse = responses[0];
      final historyResponse = responses[1];
      if (!statusResponse.isSuccess || statusResponse.data == null) {
        setState(() {
          _isLoading = false;
          _error = statusResponse.message.isEmpty
              ? _checkInText(context,
                  zhCN: '签到状态加载失败',
                  zhTW: '簽到狀態載入失敗',
                  en: 'Failed to load check-in status')
              : statusResponse.message;
        });
        return;
      }
      setState(() {
        _status = statusResponse.data as CheckInStatus;
        _history = historyResponse.isSuccess
            ? _dedupeHistory(
                historyResponse.data as List<CheckInHistoryItem>? ?? const [],
              )
            : const [];
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _checkInText(context,
            zhCN: '签到服务暂时不可用，请稍后重试',
            zhTW: '簽到服務暫時不可用，請稍後重試',
            en: 'Check-in is temporarily unavailable. Please try again.');
      });
    }
  }

  Future<void> _openRealName() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RealNamePage()),
    );
    if (!mounted) return;
    await _load(silent: true);
  }

  Future<void> _checkIn() async {
    final status = _status;
    if (_isSubmitting || status == null || !status.canCheckIn) return;
    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);
    try {
      final response = await ref.read(checkInServiceProvider).checkIn();
      if (!mounted) return;
      if (!response.isSuccess || response.data == null) {
        await _handleCheckInFailure(
          ApiResponse<Object?>(
            code: response.code,
            message: response.message,
            errorCode: response.errorCode,
            httpStatus: response.httpStatus,
            rawData: response.rawData,
          ),
        );
        return;
      }
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_checkInText(context,
            zhCN: '今日签到成功', zhTW: '今日簽到成功', en: 'Checked in today')),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_checkInText(context,
            zhCN: '签到服务暂时不可用，请稍后重试',
            zhTW: '簽到服務暫時不可用，請稍後重試',
            en: 'Check-in is temporarily unavailable. Please try again.')),
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCheckInFailure(ApiResponse<Object?> response) async {
    final failure = CheckInFailure.fromResponse(response);
    if (failure.isKycUnavailable) {
      _showMessage(_checkInText(context,
          zhCN: '暂时无法确认实名状态，请稍后重试',
          zhTW: '暫時無法確認實名狀態，請稍後重試',
          en: 'Unable to confirm identity verification. Please try again later.'));
      return;
    }
    if (failure.isKycStateChanged) {
      _showMessage(failure.message.isEmpty
          ? _checkInText(context,
              zhCN: '实名状态已变化，请稍后重试',
              zhTW: '實名狀態已變化，請稍後重試',
              en: 'Verification status changed. Please try again.')
          : failure.message);
      await _load(silent: true);
      return;
    }
    if (failure.isKycRequired) {
      _showMessage(failure.message.isEmpty
          ? _kycHint(_statusFromFailure(failure))
          : failure.message);
      await _load(silent: true);
      if (!mounted) return;
      if (failure.action == 'open_real_name') {
        await _openRealName();
      }
      return;
    }
    _showMessage(failure.message.isEmpty
        ? _checkInText(context,
            zhCN: '签到失败，请稍后重试',
            zhTW: '簽到失敗，請稍後重試',
            en: 'Check-in failed. Please try again.')
        : failure.message);
    await _load(silent: true);
  }

  CheckInStatus _statusFromFailure(CheckInFailure failure) {
    return CheckInStatus(
      kycRequired: true,
      kycStatus: failure.kycStatus,
      canCheckIn: false,
      action: failure.action,
    );
  }

  void _showMessage(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _kycHint(CheckInStatus? status) {
    switch (status?.kycStatus) {
      case 'pending':
        return _checkInText(context,
            zhCN: '实名认证审核中',
            zhTW: '實名認證審核中',
            en: 'Identity verification is under review');
      case 'rejected':
        return _checkInText(context,
            zhCN: '实名认证未通过，请重新提交',
            zhTW: '實名認證未通過，請重新提交',
            en: 'Identity verification was rejected. Please submit again');
      case 'not_submitted':
      default:
        return _checkInText(context,
            zhCN: '请先完成实名认证',
            zhTW: '請先完成實名認證',
            en: 'Complete identity verification first');
    }
  }

  String _buttonLabel(CheckInStatus? status) {
    if (status?.checkedIn == true ||
        status?.blockReason == 'ALREADY_CHECKED_IN') {
      return _checkInText(context,
          zhCN: '今日已签到', zhTW: '今日已簽到', en: 'Checked in');
    }
    if (status?.waitingForReview == true || status?.kycStatus == 'pending') {
      return _checkInText(context,
          zhCN: '实名认证审核中', zhTW: '實名認證審核中', en: 'Under review');
    }
    if (status?.needsRealNamePage == true ||
        (status?.kycRequired == true && status?.canCheckIn != true)) {
      return status?.kycStatus == 'rejected'
          ? _checkInText(context,
              zhCN: '重新提交实名', zhTW: '重新提交實名', en: 'Resubmit verification')
          : _checkInText(context,
              zhCN: '去实名认证', zhTW: '去實名認證', en: 'Verify identity');
    }
    return _checkInText(context,
        zhCN: '立即签到', zhTW: '立即簽到', en: 'Check in now');
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
        title: Text(
          _checkInText(context,
              zhCN: '签到中心', zhTW: '簽到中心', en: 'Check-in Center'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          color: Colors.white,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: _isLoading
            ? ListView(children: const [
                SizedBox(height: 260),
                Center(child: CircularProgressIndicator()),
              ])
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 140),
        Icon(Icons.cloud_off_outlined,
            size: 50, color: AppColors.textTertiaryFor(context)),
        const SizedBox(height: 14),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _load,
            child: Text(
                _checkInText(context, zhCN: '重新加载', zhTW: '重新載入', en: 'Retry')),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildWeekCard(),
        const SizedBox(height: 16),
        _buildHistoryCard(),
        const SizedBox(height: 16),
        _buildRulesCard(),
      ],
    );
  }

  Widget _buildHeader() {
    final status = _status;
    final checkedIn = status?.checkedIn == true;
    final canSubmit = status?.canCheckIn == true && !_isSubmitting;
    final openRealName = status?.needsRealNamePage == true && !_isSubmitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primaryFor(context),
          AppColors.primaryFor(context).withOpacity(0.78),
        ]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Icon(checkedIn ? Icons.check_circle : Icons.calendar_month_rounded,
            color: Colors.white, size: 56),
        const SizedBox(height: 12),
        Text(
          checkedIn
              ? _checkInText(context,
                  zhCN: '今日已签到', zhTW: '今日已簽到', en: 'Checked in today')
              : _checkInText(context,
                  zhCN: '每日签到', zhTW: '每日簽到', en: 'Daily Check-in'),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _checkInText(context,
              zhCN:
                  '连续 ${_status?.streakDays ?? 0} 天 · 累计 ${_status?.totalDays ?? 0} 天',
              zhTW:
                  '連續 ${_status?.streakDays ?? 0} 天 · 累計 ${_status?.totalDays ?? 0} 天',
              en: '${_status?.streakDays ?? 0}-day streak · ${_status?.totalDays ?? 0} total'),
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
        ),
        const SizedBox(height: 18),
        if (status?.kycRequired == true && !checkedIn && status?.canCheckIn != true)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _kycHint(status),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 13),
            ),
          ),
        SizedBox(
          width: 190,
          height: 46,
          child: FilledButton(
            onPressed: canSubmit
                ? _checkIn
                : (openRealName ? _openRealName : null),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryFor(context),
              disabledBackgroundColor: Colors.white.withOpacity(0.72),
              disabledForegroundColor: AppColors.primaryFor(context),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_buttonLabel(status)),
          ),
        ),
      ]),
    );
  }

  Widget _buildWeekCard() {
    final today = _status?.date ?? DateTime.now();
    final historyDays = _history.map((item) => _dateKey(item.date)).toSet();
    if (_status?.checkedIn == true) historyDays.add(_dateKey(today));
    final days =
        List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    return _card(
      title: _checkInText(context,
          zhCN: '最近 7 天', zhTW: '最近 7 天', en: 'Last 7 days'),
      child: Row(
        children: days.map((date) {
          final checked = historyDays.contains(_dateKey(date));
          return Expanded(
            child: Column(children: [
              Text('${date.month}/${date.day}',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiaryFor(context))),
              const SizedBox(height: 7),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked
                      ? AppColors.primaryFor(context)
                      : AppColors.inputBackgroundFor(context),
                ),
                child: Icon(checked ? Icons.check : Icons.remove,
                    size: 17,
                    color: checked
                        ? AppColors.onPrimaryFor(context)
                        : AppColors.textTertiaryFor(context)),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryCard() {
    final items = _history.take(5).toList();
    return _card(
      title: _checkInText(context,
          zhCN: '签到记录', zhTW: '簽到記錄', en: 'Check-in History'),
      child: items.isEmpty
          ? Text(
              _checkInText(context,
                  zhCN: '暂无签到记录', zhTW: '暫無簽到記錄', en: 'No check-in history'),
              style: TextStyle(color: AppColors.textTertiaryFor(context)),
            )
          : Column(
              children: items
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(children: [
                          Icon(Icons.check_circle_outline,
                              size: 19, color: AppColors.linkFor(context)),
                          const SizedBox(width: 10),
                          Text(_formatDate(item.date)),
                          const Spacer(),
                          Text(_checkInText(context,
                              zhCN: '签到奖励1元',
                              zhTW: '簽到獎勵1元',
                              en: 'Check-in reward ¥1')),
                        ]),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _buildRulesCard() {
    return _card(
      title: _checkInText(context,
          zhCN: '签到说明', zhTW: '簽到說明', en: 'Check-in Rules'),
      child: Column(children: [
        _rule(
            Icons.access_time_outlined,
            _checkInText(context,
                zhCN: '签到资格每日0:00刷新',
                zhTW: '簽到資格每日0:00刷新',
                en: 'Check-in eligibility refreshes daily at 00:00')),
        _rule(
            Icons.sync_outlined,
            _checkInText(context,
                zhCN: '每日签到固定奖励1元',
                zhTW: '每日簽到固定獎勵1元',
                en: 'Daily check-in gives a fixed ¥1 reward')),
        _rule(
            Icons.info_outline,
            _checkInText(context,
                zhCN: '漏签不影响次日继续签到（奖励自动到达暖邻钱包）',
                zhTW: '漏簽不影響次日繼續簽到（獎勵自動到達暖鄰錢包）',
                en: 'Missing a day does not block the next check-in (reward goes to Nuanlin Wallet)')),
      ]),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryFor(context))),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _rule(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.linkFor(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondaryFor(context))),
        ),
      ]),
    );
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<CheckInHistoryItem> _dedupeHistory(
    List<CheckInHistoryItem> items,
  ) {
    final seen = <String>{};
    return items.where((item) => seen.add(_dateKey(item.date))).toList();
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
