// 文件用途：提供每日签到状态、签到操作和历史记录展示。
// 核心逻辑：以服务端北京时间状态为准，防止重复提交，不在本地推导签到统计。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
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

class _CheckInPageState extends ConsumerState<CheckInPage> {
  CheckInStatus? _status;
  List<CheckInHistoryItem> _history = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
            ? (historyResponse.data as List<CheckInHistoryItem>? ?? const [])
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

  Future<void> _checkIn() async {
    if (_isSubmitting || _status?.checkedIn == true) return;
    HapticFeedback.lightImpact();
    setState(() => _isSubmitting = true);
    try {
      final response = await ref.read(checkInServiceProvider).checkIn();
      if (!mounted) return;
      if (!response.isSuccess || response.data == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response.message.isEmpty
              ? _checkInText(context,
                  zhCN: '签到失败，请稍后重试',
                  zhTW: '簽到失敗，請稍後重試',
                  en: 'Check-in failed. Please try again.')
              : response.message),
        ));
        return;
      }
      setState(() => _status = response.data);
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
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
    final checkedIn = _status?.checkedIn == true;
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
              color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
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
        SizedBox(
          width: 190,
          height: 46,
          child: FilledButton(
            onPressed: checkedIn || _isSubmitting ? null : _checkIn,
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
                : Text(checkedIn
                    ? _checkInText(context,
                        zhCN: '今日已签到', zhTW: '今日已簽到', en: 'Checked in')
                    : _checkInText(context,
                        zhCN: '立即签到', zhTW: '立即簽到', en: 'Check in now')),
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
                              zhCN: '已签到', zhTW: '已簽到', en: 'Checked in')),
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
                zhCN: '每天按北京时间可签到一次',
                zhTW: '每天按北京時間可簽到一次',
                en: 'Check in once per Beijing calendar day')),
        _rule(
            Icons.sync_outlined,
            _checkInText(context,
                zhCN: '签到规则：连续7天领取8.8元',
                zhTW: '簽到規則：連續7天領取8.8元',
                en: 'Check-in rule: receive ¥8.8 after 7 consecutive days')),
        _rule(
            Icons.info_outline,
            _checkInText(context,
                zhCN: '连续15天领取28.8元，连续30天领取68.8元；中途漏签重新计算天数',
                zhTW: '連續15天領取28.8元，連續30天領取68.8元；中途漏簽重新計算天數',
                en: 'Receive ¥28.8 after 15 days and ¥68.8 after 30 days; missing a day resets the streak')),
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

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
