// 文件用途：实现 SearchResult 页面及其交互流程，属于联系人。
// 核心逻辑：维护 SearchResult 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../providers/contact_provider.dart';
import '../../chat/providers/chat_provider.dart' show chatListProvider;
import '../../home/pages/home_desktop_page.dart';
import '../../vip/models/vip_profile_summary.dart';
import '../../vip/widgets/vip_badge.dart';

// 关键声明：new contact page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 统一搜索结果
class SearchResult {
  final String id;
  final String name;
  final String? shortId;
  final String? username;
  final String? avatar;
  final String? bio;
  final String? gender;
  final double? distanceKm;
  final String type; // user, group, channel
  final int memberCount;
  final bool isMember; // 是否已加入/订阅
  final bool isContact;
  final bool isBot;
  final String? botKind;
  final String? accountType;
  final String? nicknameColor;
  final String? emojiAvatar;
  final VipProfileSummary vip;

  bool get canStartPrivateChat => type == 'user' && (isBot || isContact);

  SearchResult({
    required this.id,
    required this.name,
    this.shortId,
    this.username,
    this.avatar,
    this.bio,
    this.gender,
    this.distanceKm,
    required this.type,
    this.memberCount = 0,
    this.isMember = false,
    this.isContact = false,
    this.isBot = false,
    this.botKind,
    this.accountType,
    this.nicknameColor,
    this.emojiAvatar,
    this.vip = VipProfileSummary.inactive,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    // 转换头像 URL
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return SearchResult(
      id: json['id'] ?? '',
      name: json['name'] ?? json['nickname'] ?? '',
      shortId: json['short_id']?.toString(),
      username: json['username'],
      avatar: avatarUrl,
      bio: json['bio'],
      gender: json['gender']?.toString(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      type: json['type'] ?? 'user',
      memberCount: json['member_count'] ?? 0,
      isMember: json['is_member'] ?? false,
      isContact: json['is_contact'] ?? false,
      isBot: json['is_bot'] == true || json['account_type'] == 'bot',
      botKind: json['bot_kind']?.toString(),
      accountType: json['account_type']?.toString(),
      nicknameColor: json['nickname_color'],
      emojiAvatar: json['emoji_avatar'],
      vip: VipProfileSummary.fromJson(json['vip']),
    );
  }
}

class NewContactPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示
  final String? initialQuery;

  const NewContactPage({
    super.key,
    this.isDesktopPanel = false,
    this.initialQuery,
  });

  @override
  ConsumerState<NewContactPage> createState() => _NewContactPageState();
}

class _NewContactPageState extends ConsumerState<NewContactPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSearching = false;
  List<SearchResult> _allResults = [];
  String? _errorMessage;

  String _text({
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

  String _displayServerMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    return localizeServerMessage(
      raw,
      fallbackZhCN: zhCN,
      fallbackZhTW: zhTW,
      fallbackEn: en,
    );
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      if (initialQuery.isNotEmpty) {
        _search(initialQuery);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    // 去掉开头的 @ 符号（支持 @username 格式搜索）
    String searchKeyword = keyword.trim();
    if (searchKeyword.startsWith('@')) {
      searchKeyword = searchKeyword.substring(1);
    }

    if (searchKeyword.isEmpty) {
      setState(() {
        _allResults = [];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(
        '/user/search-all',
        queryParameters: {'keyword': searchKeyword, 'type': 'all'},
      );

      if (response.code == 0 && response.data != null) {
        final list = response.data['list'] as List? ?? [];
        setState(() {
          _allResults =
              list.map((json) => SearchResult.fromJson(json)).toList();
          _isSearching = false;
        });
      } else {
        setState(() {
          _errorMessage = _displayServerMessage(
            raw: response.message,
            zhCN: '搜索失败，请重试',
            zhTW: '搜尋失敗，請重試',
            en: 'Search failed. Please try again.',
          );
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = _text(
          zhCN: '搜索失败，请重试',
          zhTW: '搜尋失敗，請重試',
          en: 'Search failed. Please try again.',
        );
        _isSearching = false;
      });
    }
  }

  String _formatDistance(SearchResult result) {
    final distance = result.distanceKm;
    if (distance == null) return '';
    if (distance < 1) {
      return '${(distance * 1000).round().clamp(1, 999)}m';
    }
    return '${distance.toStringAsFixed(1)}km';
  }

  void _openResult(SearchResult result) {
    // 桌面端不触发震动
    if (Platform.isIOS || Platform.isAndroid) {
      HapticFeedback.selectionClick();
    }

    debugPrint(
      '[NewContact] Opening result: ${result.name}, type: ${result.type}',
    );

    if (result.type == 'user') {
      if (!result.canStartPrivateChat) return;
      _startChat(result);
    } else {
      // 群组/频道 - 直接进入聊天页，传递类型参数
      final chatType = result.type == 'group' ? 'group' : 'channel';
      context.push(
        '/chat/${result.id}?name=${Uri.encodeComponent(result.name)}&type=$chatType${result.avatar != null ? '&avatar=${Uri.encodeComponent(result.avatar!)}' : ''}',
      );
    }
  }

  Future<void> _startChat(SearchResult user) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = user.isBot
          ? await apiClient.post(
              '/bots/${Uri.encodeComponent(user.id)}/start',
              data: <String, dynamic>{},
            )
          : await apiClient.post(
              '/chat/create',
              data: {
                'type': 1, // 私聊
                'member_ids': [user.id],
              },
            );

      if (!mounted) return;

      if (response.code == 0 && response.data != null) {
        final responseData = response.data;
        final chatData = user.isBot && responseData is Map
            ? responseData['chat']
            : responseData;
        final chatId = chatData is Map ? chatData['uuid']?.toString() : null;
        if (chatId != null) {
          ref.read(chatListProvider.notifier).refresh();
          context.push(
            '/chat/$chatId?name=${Uri.encodeComponent(user.name)}&type=private${user.avatar != null ? '&avatar=${Uri.encodeComponent(user.avatar!)}' : ''}',
          );
          return;
        }
      }

      // 创建失败时显示错误
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _displayServerMessage(
              raw: response.message,
              zhCN: '打开聊天失败，请重试',
              zhTW: '打開聊天失敗，請重試',
              en: 'Failed to open chat. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              zhCN: '打开聊天失败，请重试',
              zhTW: '打開聊天失敗，請重試',
              en: 'Failed to open chat. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _addContact(SearchResult user) async {
    // 桌面端不触发震动
    if (Platform.isIOS || Platform.isAndroid) {
      HapticFeedback.mediumImpact();
    }

    // 系统配置决定客户端展示哪条流程，但添加结果仍由服务端权限和关系校验裁决。
    final friendAddMode =
        ref.read(systemSettingsProvider).valueOrNull?.friendAddMode ??
            FriendAddMode.approval;
    if (friendAddMode == FriendAddMode.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              zhCN: '管理员已关闭添加好友功能',
              zhTW: '管理員已關閉新增好友功能',
              en: 'Adding friends has been disabled by the administrator.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (friendAddMode == FriendAddMode.direct) {
      final success =
          await ref.read(contactListProvider.notifier).addContact(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? _text(
                    zhCN: '已添加为好友',
                    zhTW: '已新增為好友',
                    en: 'Friend added',
                  )
                : _text(
                    zhCN: '添加失败，请重试',
                    zhTW: '新增失敗，請重試',
                    en: 'Failed to add friend. Please try again.',
                  ),
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) {
        await _search(_searchController.text);
      }
      return;
    }

    var verificationMessage = _text(
      zhCN: '你好，我是${_text(zhCN: '新朋友', zhTW: '新朋友', en: 'a new friend')}',
      zhTW: '你好，我是新朋友',
      en: 'Hi, I would like to add you as a friend.',
    );
    final verification = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _text(
            zhCN: '发送好友申请',
            zhTW: '傳送好友申請',
            en: 'Send Friend Request',
          ),
        ),
        content: TextFormField(
          initialValue: verificationMessage,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          onChanged: (value) => verificationMessage = value,
          decoration: InputDecoration(
            labelText: _text(
              zhCN: '验证消息',
              zhTW: '驗證訊息',
              en: 'Verification message',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              verificationMessage.trim(),
            ),
            child: Text(
              _text(zhCN: '发送', zhTW: '傳送', en: 'Send'),
            ),
          ),
        ],
      ),
    );
    if (verification == null || !mounted) return;

    try {
      final result = await ref
          .read(contactListProvider.notifier)
          .sendFriendRequest(user.id, message: verification);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                zhCN: '好友申请发送失败，请重试',
                zhTW: '好友申請傳送失敗，請重試',
                en: 'Failed to send friend request. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      final accepted =
          result.autoAccepted || result.request.status == 'accepted';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? _text(
                    zhCN: '双方已互相申请，已成为好友',
                    zhTW: '雙方已互相申請，已成為好友',
                    en: 'You both sent requests and are now contacts.',
                  )
                : result.created
                    ? _text(
                        zhCN: '好友申请已发送',
                        zhTW: '好友申請已傳送',
                        en: 'Friend request sent',
                      )
                    : _text(
                        zhCN: '好友申请正在等待对方处理',
                        zhTW: '好友申請正在等待對方處理',
                        en: 'The friend request is already pending.',
                      ),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              zhCN: '添加失败，请重试',
              zhTW: '添加失敗，請重試',
              en: 'Failed to add contact. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final friendAddMode =
        ref.watch(systemSettingsProvider).valueOrNull?.friendAddMode ??
            FriendAddMode.approval;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: widget.isDesktopPanel
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 20,
                  color: AppColors.primaryFor(context),
                ),
                onPressed: () {
                  ref.read(desktopProfileProvider.notifier).state =
                      DesktopProfileInfo.none;
                },
              )
            : null,
        title: Text(l10n.search),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: _text(
                  zhCN: '输入ID或手机号搜索用户',
                  zhTW: '輸入 ID 或手機號搜尋使用者',
                  en: 'Enter an ID or phone number to search users',
                ),
                hintStyle: TextStyle(
                  color: AppColors.textTertiaryFor(context),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.textTertiaryFor(context),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? AppColors.inputBackgroundFor(context)
                    : Colors.black.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimaryFor(context),
              ),
              onChanged: (value) {
                setState(() {});
                // 防抖搜索
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchController.text == value) {
                    _search(value);
                  }
                });
              },
              onSubmitted: _search,
            ),
          ),

          // 提示文字
          if (_searchController.text.isEmpty && _allResults.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_search_rounded,
                      size: 80,
                      color: AppColors.textTertiaryFor(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.get('search_user_to_chat') ??
                          _text(
                            zhCN: '搜索用户开始聊天',
                            zhTW: '搜尋使用者開始聊天',
                            en: 'Search for a user to start chatting',
                          ),
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.get('no_need_add_friend') ??
                          _text(
                            zhCN: '无需添加好友，直接发起私聊',
                            zhTW: '無需加好友，直接發起私聊',
                            en: 'No need to add friends. Start a private chat directly',
                          ),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.get('also_search_public_groups') ??
                          _text(
                            zhCN: '也可搜索公开群组和频道',
                            zhTW: '也可搜尋公開群組和頻道',
                            en: 'You can also search public groups and channels',
                          ),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 加载中
          if (_isSearching)
            const Expanded(child: Center(child: CircularProgressIndicator())),

          // 错误信息
          if (_errorMessage != null && !_isSearching)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 搜索结果 - 直接显示所有结果，不分 Tab
          if (!_isSearching &&
              _errorMessage == null &&
              _searchController.text.isNotEmpty)
            Expanded(
              child: _allResults.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _allResults.length,
                      itemBuilder: (context, index) {
                        final result = _allResults[index];
                        final canOpenResult =
                            result.type != 'user' || result.canStartPrivateChat;
                        return _SearchResultTile(
                          result: result,
                          friendAddMode: friendAddMode,
                          distanceLabel: _formatDistance(result),
                          onTap:
                              canOpenResult ? () => _openResult(result) : null,
                          onAddContact: result.type == 'user' &&
                                  !result.isBot &&
                                  !result.isContact
                              ? () => _addContact(result)
                              : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 60,
            color: AppColors.textTertiaryFor(context),
          ),
          const SizedBox(height: 16),
          Text(
            _text(
              zhCN: '未找到用户',
              zhTW: '未找到使用者',
              en: 'No user found',
            ),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _text(
              zhCN: '尝试其他关键词',
              zhTW: '嘗試其他關鍵字',
              en: 'Try another keyword',
            ),
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final FriendAddMode friendAddMode;
  final String distanceLabel;
  final VoidCallback? onTap;
  final VoidCallback? onAddContact;

  const _SearchResultTile({
    required this.result,
    required this.friendAddMode,
    this.distanceLabel = '',
    this.onTap,
    this.onAddContact,
  });

  String _text(
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 头像
            Stack(
              children: [
                AvatarWidget(
                  avatar: result.avatar,
                  name: result.name,
                  size: 52,
                  borderRadius: 12,
                ),
                if (result.type != 'user')
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBackground : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        result.type == 'group' ? Icons.group : Icons.campaign,
                        size: 14,
                        color: AppColors.primaryFor(context),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // 信息
            Expanded(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: result.type == 'user'
                              ? ColoredNameWidget(
                                  name: result.name,
                                  nicknameColor: result.nicknameColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  defaultColor:
                                      AppColors.textPrimaryFor(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Text(
                                  result.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryFor(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        if (result.type == 'user' &&
                            result.emojiAvatar != null &&
                            result.emojiAvatar!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          EmojiStatusWidget(
                            emoji: result.emojiAvatar!,
                            size: 18,
                          ),
                        ],
                        if (result.type == 'user' && result.vip.visible) ...[
                          const SizedBox(width: 5),
                          VipBadge(
                            level: result.vip.level,
                            text: result.vip.badge,
                            iconUrl: result.vip.badgeIcon,
                            height: 18,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if ((result.shortId ?? result.username)?.isNotEmpty == true)
                      Text(
                        'ID号：${result.shortId ?? result.username}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.linkFor(context),
                        ),
                      ),
                    if (distanceLabel.isNotEmpty)
                      Text(
                        distanceLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    if (result.type != 'user' && result.memberCount > 0)
                      Text(
                        result.type == 'group'
                            ? _text(
                                context,
                                zhCN: '${result.memberCount} 位成员',
                                zhTW: '${result.memberCount} 位成員',
                                en: '${result.memberCount} members',
                              )
                            : _text(
                                context,
                                zhCN: '${result.memberCount} 订阅者',
                                zhTW: '${result.memberCount} 訂閱者',
                                en: '${result.memberCount} subscribers',
                              ),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    if (result.bio != null && result.bio!.isNotEmpty)
                      Text(
                        result.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 操作按钮
            if (result.type == 'user')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result.canStartPrivateChat)
                    FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(
                        _text(
                          context,
                          zhCN: '聊天',
                          zhTW: '聊天',
                          en: 'Chat',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryFor(context),
                        foregroundColor: AppColors.onPrimaryFor(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (onAddContact != null) ...[
                    if (result.canStartPrivateChat) const SizedBox(width: 8),
                    IconButton(
                      onPressed: onAddContact,
                      icon: Icon(
                        friendAddMode == FriendAddMode.disabled
                            ? Icons.person_add_disabled_outlined
                            : Icons.person_add_outlined,
                      ),
                      tooltip: _text(
                        context,
                        zhCN: friendAddMode == FriendAddMode.disabled
                            ? '管理员已禁止添加好友'
                            : friendAddMode == FriendAddMode.direct
                                ? '直接添加好友'
                                : '发送好友申请',
                        zhTW: friendAddMode == FriendAddMode.disabled
                            ? '管理員已禁止新增好友'
                            : friendAddMode == FriendAddMode.direct
                                ? '直接新增好友'
                                : '傳送好友申請',
                        en: friendAddMode == FriendAddMode.disabled
                            ? 'Adding friends is disabled'
                            : friendAddMode == FriendAddMode.direct
                                ? 'Add friend'
                                : 'Send friend request',
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        foregroundColor: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ] else if (result.isContact) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_circle_outline,
                      color: AppColors.success,
                    ),
                  ],
                ],
              )
            else if (result.isMember)
              // 已加入/订阅，显示箭头（进入聊天）
              Icon(
                Icons.chevron_right,
                color: AppColors.textTertiaryFor(context),
              )
            else
              // 未加入/订阅，显示加入/订阅按钮
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryFor(context),
                  foregroundColor: AppColors.onPrimaryFor(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  result.type == 'group'
                      ? _text(
                          context,
                          zhCN: '加入',
                          zhTW: '加入',
                          en: 'Join',
                        )
                      : _text(
                          context,
                          zhCN: '订阅',
                          zhTW: '訂閱',
                          en: 'Subscribe',
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
