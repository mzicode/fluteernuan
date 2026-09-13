// 文件用途：展示当前用户的邀请码、邀请链接和二维码。
// 核心逻辑：读取推荐资料和公开设置，保证二维码、复制及分享使用同一完整邀请地址。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../team/services/team_service.dart';

String _inviteText(
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

class InviteFriendsPage extends ConsumerStatefulWidget {
  const InviteFriendsPage({super.key});

  @override
  ConsumerState<InviteFriendsPage> createState() => _InviteFriendsPageState();
}

class _InviteFriendsPageState extends ConsumerState<InviteFriendsPage> {
  ReferralProfile _profile = const ReferralProfile();
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReferralProfile();
    });
  }

  Future<void> _loadReferralProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final response = await ref.read(teamServiceProvider).getReferralProfile();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = !response.isSuccess || response.data == null;
        if (response.isSuccess && response.data != null) {
          _profile = response.data!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  String _resolveInviteCode(String localShortId) {
    if (_profile.inviteCode.isNotEmpty) return _profile.inviteCode;
    if (_profile.inviteParameter.isNotEmpty) return _profile.inviteParameter;
    if (_profile.yixinId.isNotEmpty) return _profile.yixinId;
    return localShortId;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authServiceProvider).user;
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final inviteCode = _resolveInviteCode(user?.shortId?.trim() ?? '');
    final inviteLink = inviteCode.isNotEmpty && settings != null
        ? settings.buildInviteLink(inviteCode)
        : '';
    final displayName = user?.nickname.trim().isNotEmpty == true
        ? user!.nickname.trim()
        : _inviteText(
            context,
            zhCN: '暖邻用户',
            zhTW: '暖鄰用戶',
            en: 'Nuanlin User',
          );

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.primaryFor(context),
        title: Text(
          _inviteText(
            context,
            zhCN: '我的邀请',
            zhTW: '我的邀請',
            en: 'My Invitations',
          ),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReferralProfile,
        color: AppColors.controlActiveFor(context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            _buildInviteCard(
              context,
              displayName: displayName,
              avatar: user?.avatar,
              inviteCode: inviteCode,
              inviteLink: inviteLink,
            ),
            const SizedBox(height: 16),
            _buildActions(context, inviteCode, inviteLink),
            if (_loadFailed) ...[
              const SizedBox(height: 16),
              _buildLoadError(context),
            ],
            const SizedBox(height: 18),
            Text(
              _inviteText(
                context,
                zhCN: '好友扫码或打开邀请链接后，注册页面会自动填入您的邀请码。',
                zhTW: '好友掃碼或開啟邀請連結後，註冊頁面會自動填入您的邀請碼。',
                en: 'When friends scan the code or open the link, your invite code is filled in automatically on registration.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(
    BuildContext context, {
    required String displayName,
    required String? avatar,
    required String inviteCode,
    required String inviteLink,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.primaryFor(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryFor(context).withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                AvatarWidget(
                  name: displayName,
                  avatar: avatar,
                  size: 48,
                  isCircle: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF22252B),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '暖邻',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    color: Color(0xFFFF3B30),
                    size: 21,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              inviteCode.isEmpty ? '------' : inviteCode,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _inviteText(
                context,
                zhCN: '我的邀请码',
                zhTW: '我的邀請碼',
                en: 'My invite code',
              ),
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            _buildQrArea(context, inviteLink),
            const SizedBox(height: 12),
            Text(
              _inviteText(
                context,
                zhCN: '扫一扫二维码，注册时自动填写邀请码',
                zhTW: '掃描二維碼，註冊時自動填寫邀請碼',
                en: 'Scan the QR code to fill in the invite code automatically',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrArea(BuildContext context, String inviteLink) {
    if (inviteLink.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: inviteLink,
          size: 176,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF111827),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF111827),
          ),
        ),
      );
    }

    return Container(
      width: 194,
      height: 194,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            size: 68,
            color: Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 8),
          Text(
            _isLoading
                ? _inviteText(
                    context,
                    zhCN: '邀请信息加载中',
                    zhTW: '邀請資訊載入中',
                    en: 'Loading invitation',
                  )
                : _inviteText(
                    context,
                    zhCN: '邀请地址暂未配置',
                    zhTW: '邀請地址尚未配置',
                    en: 'Invite address not configured',
                  ),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    String inviteCode,
    String inviteLink,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _ActionTile(
            icon: Icons.copy_rounded,
            title: _inviteText(
              context,
              zhCN: '复制邀请码',
              zhTW: '複製邀請碼',
              en: 'Copy Invite Code',
            ),
            subtitle: inviteCode.isEmpty ? '------' : inviteCode,
            onTap: () => _copyText(
              context,
              inviteCode,
              _inviteText(
                context,
                zhCN: '邀请码已复制',
                zhTW: '邀請碼已複製',
                en: 'Invite code copied',
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: AppColors.dividerFor(context),
          ),
          _ActionTile(
            icon: Icons.link_rounded,
            title: _inviteText(
              context,
              zhCN: '复制邀请链接',
              zhTW: '複製邀請連結',
              en: 'Copy Invite Link',
            ),
            subtitle: inviteLink.isEmpty
                ? _inviteText(
                    context,
                    zhCN: '邀请地址暂未配置',
                    zhTW: '邀請地址尚未配置',
                    en: 'Invite address not configured',
                  )
                : inviteLink,
            onTap: () => _copyText(
              context,
              inviteLink,
              _inviteText(
                context,
                zhCN: '邀请链接已复制',
                zhTW: '邀請連結已複製',
                en: 'Invite link copied',
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: AppColors.dividerFor(context),
          ),
          _ActionTile(
            icon: Icons.share_outlined,
            title: _inviteText(
              context,
              zhCN: '分享给好友',
              zhTW: '分享給好友',
              en: 'Share with Friends',
            ),
            subtitle: _inviteText(
              context,
              zhCN: '通过系统分享发送完整邀请链接',
              zhTW: '透過系統分享傳送完整邀請連結',
              en: 'Share the complete invitation link',
            ),
            onTap: () => _shareInviteLink(context, inviteLink),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Material(
      color: AppColors.cardFor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _loadReferralProfile,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.refresh_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _inviteText(
                    context,
                    zhCN: '邀请资料加载失败，点击重试',
                    zhTW: '邀請資料載入失敗，點擊重試',
                    en: 'Failed to load invitation details. Tap to retry.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyText(
    BuildContext context,
    String value,
    String successMessage,
  ) async {
    HapticFeedback.lightImpact();
    if (value.isEmpty) {
      _showUnavailable(context);
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _shareInviteLink(
    BuildContext context,
    String inviteLink,
  ) async {
    HapticFeedback.lightImpact();
    if (inviteLink.isEmpty) {
      _showUnavailable(context);
      return;
    }
    await Share.share(inviteLink);
  }

  void _showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _inviteText(
            context,
            zhCN: '邀请地址暂未配置',
            zhTW: '邀請地址尚未配置',
            en: 'Invite address not configured',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.emphasisSoftFor(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: AppColors.linkFor(context)),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          color: AppColors.textPrimaryFor(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textTertiaryFor(context),
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: AppColors.textTertiaryFor(context),
      ),
    );
  }
}
