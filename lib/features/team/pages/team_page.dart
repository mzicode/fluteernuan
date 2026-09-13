import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../identity/pages/real_name_page.dart';
import '../../identity/services/real_name_service.dart';
import '../services/team_service.dart';

class TeamPage extends ConsumerStatefulWidget {
  const TeamPage({super.key});

  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> {
  static const _pageSize = 20;

  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';
  int _selectedLevel = 1;
  int _page = 1;
  RealNameStatus? _realNameStatus;
  ReferralProfile _profile = const ReferralProfile();
  TeamStats _stats = const TeamStats();
  List<TeamMember> _members = const [];

  String _text({required String zhCN, String? zhTW, required String en}) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadInitial);
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final service = ref.read(teamServiceProvider);
      final statusResponse =
          await ref.read(realNameServiceProvider).getStatus();
      if (!mounted) return;
      if (!statusResponse.isSuccess || statusResponse.data == null) {
        setState(() {
          _loading = false;
          _error = statusResponse.message;
        });
        return;
      }

      final status = statusResponse.data!;
      if (!status.isApproved) {
        setState(() {
          _realNameStatus = status;
          _loading = false;
        });
        return;
      }

      final responses = await Future.wait([
        service.getReferralProfile(),
        service.getStats(),
        service.getMembers(level: _selectedLevel, pageSize: _pageSize),
      ]);
      if (!mounted) return;
      final profileResponse = responses[0] as dynamic;
      final statsResponse = responses[1] as dynamic;
      final membersResponse = responses[2] as dynamic;
      if (statsResponse.code == 1010 || membersResponse.code == 1010) {
        setState(() {
          _realNameStatus = const RealNameStatus(
            status: 'unsubmitted',
            canSubmit: true,
          );
          _loading = false;
        });
        return;
      }
      if (!profileResponse.isSuccess ||
          !statsResponse.isSuccess ||
          !membersResponse.isSuccess) {
        final message = !statsResponse.isSuccess
            ? statsResponse.message
            : (!membersResponse.isSuccess
                ? membersResponse.message
                : profileResponse.message);
        setState(() {
          _realNameStatus = status;
          _loading = false;
          _error = message?.toString() ?? '';
        });
        return;
      }

      setState(() {
        _realNameStatus = status;
        _profile =
            profileResponse.data as ReferralProfile? ?? const ReferralProfile();
        _stats = statsResponse.data as TeamStats? ?? const TeamStats();
        _members =
            (membersResponse.data as TeamMemberPage?)?.members ?? const [];
        _page = 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _selectLevel(int level) async {
    if (level == _selectedLevel || _loading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedLevel = level;
      _loading = true;
      _error = '';
    });
    final response = await ref
        .read(teamServiceProvider)
        .getMembers(level: level, pageSize: _pageSize);
    if (!mounted) return;
    if (response.code == 1010) {
      setState(() {
        _realNameStatus = const RealNameStatus(
          status: 'unsubmitted',
          canSubmit: true,
        );
        _members = const [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
      if (response.isSuccess && response.data != null) {
        _members = response.data!.members;
        _page = 1;
      } else {
        _members = const [];
        _error = response.message;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        _members.length >= _stats.countForLevel(_selectedLevel)) {
      return;
    }
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final response = await ref.read(teamServiceProvider).getMembers(
          level: _selectedLevel,
          page: nextPage,
          pageSize: _pageSize,
        );
    if (!mounted) return;
    if (response.code == 1010) {
      setState(() {
        _realNameStatus = const RealNameStatus(
          status: 'unsubmitted',
          canSubmit: true,
        );
        _loadingMore = false;
      });
      return;
    }
    setState(() {
      _loadingMore = false;
      if (response.isSuccess && response.data != null) {
        _page = nextPage;
        final knownIds =
            _members.map((item) => '${item.id}:${item.uuid}').toSet();
        _members = [
          ..._members,
          ...response.data!.members.where(
            (item) => knownIds.add('${item.id}:${item.uuid}'),
          ),
        ];
      } else {
        _error = response.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFFFFAF7),
      appBar: AppBar(
        title: Text(_text(zhCN: '我的团队', zhTW: '我的團隊', en: 'My Team')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading && _members.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty && _realNameStatus == null) {
      return _ErrorView(message: _error, onRetry: _loadInitial);
    }
    if (_realNameStatus?.isApproved != true) {
      return _buildRealNameGate(isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHeaderCard(isDark),
          const SizedBox(height: 16),
          _buildStats(isDark),
          const SizedBox(height: 22),
          Text(
            _text(zhCN: '团队成员', zhTW: '團隊成員', en: 'Team Members'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _buildLevelSelector(isDark),
          const SizedBox(height: 12),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          if (_members.isEmpty)
            _EmptyMembers(level: _selectedLevel)
          else
            ..._members.map((member) => _MemberCard(member: member)),
          if (_members.length < _stats.countForLevel(_selectedLevel))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: _loadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_text(zhCN: '加载更多', zhTW: '載入更多', en: 'Load More')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    final user = ref.watch(authServiceProvider).user;
    final parent = _profile.parent;
    final avatar = user?.avatar?.trim() ?? '';
    final yixinId =
        _profile.yixinId.isNotEmpty ? _profile.yixinId : (user?.shortId ?? '');
    final primary = AppColors.primaryFor(context);
    final foreground = AppColors.onPrimaryFor(context);
    final mutedForeground = foreground.withOpacity(0.72);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.primaryContainerFor(context),
                  const Color(0xFF121820)
                ]
              : const [AppColors.primary, Color(0xFF3F3F46)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: primary.withOpacity(0.18),
              blurRadius: 22,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(url: avatar, name: user?.nickname ?? '', size: 58),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.nickname.isNotEmpty == true
                          ? user!.nickname
                          : _text(zhCN: '我的团队', zhTW: '我的團隊', en: 'My Team'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      yixinId.isEmpty ? '' : '暖邻ID: $yixinId',
                      style: TextStyle(color: mutedForeground, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    '${_stats.total}',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _text(zhCN: '团队总人数', zhTW: '團隊總人數', en: 'Members'),
                    style: TextStyle(color: mutedForeground, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          if (parent != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Divider(height: 1, color: foreground.withOpacity(0.16)),
            ),
            Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 19, color: foreground),
                const SizedBox(width: 8),
                Text(
                  _text(zhCN: '我的邀请人', zhTW: '我的邀請人', en: 'My Referrer'),
                  style: TextStyle(color: mutedForeground, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${parent.nickname}${parent.yixinId.isEmpty ? '' : ' · 暖邻ID ${parent.yixinId}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: _text(zhCN: '已实名', zhTW: '已實名', en: 'Verified'),
                value: _stats.verified,
                color: const Color(0xFF4EAD7A),
                icon: Icons.verified_user_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: _text(zhCN: '未实名', zhTW: '未實名', en: 'Unverified'),
                value: _stats.unverified,
                color: const Color(0xFFE29A52),
                icon: Icons.person_search_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var level = 1; level <= 3; level++) ...[
              if (level > 1) const SizedBox(width: 10),
              Expanded(
                child: _LevelStatCard(
                  level: level,
                  value: _stats.countForLevel(level),
                  selected: _selectedLevel == level,
                  onTap: () => _selectLevel(level),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildLevelSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : AppColors.primaryWithOpacity(context, 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var level = 1; level <= 3; level++)
            Expanded(
              child: GestureDetector(
                onTap: () => _selectLevel(level),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedLevel == level
                        ? (isDark
                            ? AppColors.primaryContainerFor(context)
                            : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: _selectedLevel == level && !isDark
                        ? const [
                            BoxShadow(color: Color(0x14000000), blurRadius: 8)
                          ]
                        : null,
                  ),
                  child: Text(
                    _text(
                      zhCN: '$level级成员',
                      zhTW: '$level級成員',
                      en: 'Level $level',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _selectedLevel == level
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _selectedLevel == level
                          ? AppColors.primaryFor(context)
                          : AppColors.textSecondaryFor(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRealNameGate(bool isDark) {
    final status = _realNameStatus?.status ?? 'unsubmitted';
    final title = status == 'pending'
        ? _text(zhCN: '实名认证审核中', zhTW: '實名認證審核中', en: 'Verification Pending')
        : status == 'rejected'
            ? _text(
                zhCN: '实名认证未通过', zhTW: '實名認證未通過', en: 'Verification Rejected')
            : _text(
                zhCN: '完成实名认证后查看团队',
                zhTW: '完成實名認證後查看團隊',
                en: 'Verify to View Your Team');
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 24,
                    offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.primaryWithOpacity(context, 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_user_outlined,
                      color: AppColors.primaryFor(context), size: 38),
                ),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  _realNameStatus?.rejectReason.isNotEmpty == true
                      ? _realNameStatus!.rejectReason
                      : _text(
                          zhCN: '团队数据仅向已完成实名认证的会员开放。完成认证后，下拉刷新即可查看。',
                          zhTW: '團隊資料僅向已完成實名認證的會員開放。完成認證後，下拉重新整理即可查看。',
                          en: 'Team data is available after identity verification. Pull to refresh once approved.',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.5,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: status == 'pending'
                      ? _loadInitial
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RealNamePage(),
                            ),
                          );
                          if (mounted) await _loadInitial();
                        },
                  icon: Icon(status == 'pending'
                      ? Icons.refresh_rounded
                      : Icons.verified_user_outlined),
                  label: Text(status == 'pending'
                      ? _text(
                          zhCN: '刷新认证状态',
                          zhTW: '重新整理認證狀態',
                          en: 'Refresh Status')
                      : _text(zhCN: '去实名认证', zhTW: '前往實名認證', en: 'Verify Now')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelStatCard extends StatelessWidget {
  final int level;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _LevelStatCard({
    required this.level,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryWithOpacity(context, 0.08)
              : (Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurface
                  : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primaryWithOpacity(context, 0.28)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Text('$value',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text('$level级',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryFor(context))),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final TeamMember member;

  const _MemberCard({required this.member});

  String _date(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (member.realNameStatus) {
      'approved' => (
          label: _memberStatusText(context,
              zhCN: '已实名', zhTW: '已實名', en: 'Verified'),
          background: const Color(0xFFE8F7EF),
          foreground: const Color(0xFF32885D),
        ),
      'pending' => (
          label: _memberStatusText(context,
              zhCN: '审核中', zhTW: '審核中', en: 'Pending'),
          background: const Color(0xFFEAF1FF),
          foreground: const Color(0xFF4674C6),
        ),
      'rejected' => (
          label: _memberStatusText(context,
              zhCN: '未通过', zhTW: '未通過', en: 'Rejected'),
          background: const Color(0xFFFFE9E7),
          foreground: const Color(0xFFC8564F),
        ),
      _ => (
          label: _memberStatusText(context,
              zhCN: '未实名', zhTW: '未實名', en: 'Unverified'),
          background: const Color(0xFFFFF1E2),
          foreground: const Color(0xFFC8792D),
        ),
    };
    final date = _date(
        member.joinedAt.isNotEmpty ? member.joinedAt : member.registeredAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkSurface
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _Avatar(url: member.avatar, name: member.nickname, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.nickname.isEmpty ? '用户' : member.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
                if (member.yixinId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('暖邻ID: ${member.yixinId}',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondaryFor(context))),
                ],
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('加入时间 $date',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textTertiaryFor(context))),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: status.background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.label,
              style: TextStyle(
                color: status.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _memberStatusText(
  BuildContext context, {
  required String zhCN,
  required String zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _Avatar({required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '暖' : name.trim().characters.first;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primaryWithOpacity(context, 0.10),
      backgroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty
          ? Text(initial,
              style: TextStyle(
                color: AppColors.primaryFor(context),
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ))
          : null,
    );
  }
}

class _EmptyMembers extends StatelessWidget {
  final int level;

  const _EmptyMembers({required this.level});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.groups_2_outlined,
              size: 48, color: AppColors.textTertiaryFor(context)),
          const SizedBox(height: 12),
          Text('暂无$level级团队成员',
              style: TextStyle(color: AppColors.textSecondaryFor(context))),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message.isEmpty ? '团队数据加载失败' : message,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
