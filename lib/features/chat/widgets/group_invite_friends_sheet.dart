// 文件用途：群成员邀请好友选择器（对接 GET invite-candidates + POST members）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../providers/chat_provider.dart';

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

String _inviteServerMessage(
  BuildContext context,
  String raw, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  final localized = localizeServerMessage(raw);
  if (localized.trim().isNotEmpty) return localized.trim();
  return _inviteText(context, zhCN: zhCN, zhTW: zhTW, en: en);
}

/// 展示群邀请好友选择器；成功后回调 [onMembersAdded] 并刷新详情/成员。
Future<void> showGroupInviteFriendsSheet({
  required BuildContext context,
  required String chatId,
  VoidCallback? onMembersAdded,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => GroupInviteFriendsSheet(
      chatId: chatId,
      onMembersAdded: onMembersAdded,
    ),
  );
}

class GroupInviteFriendsSheet extends ConsumerStatefulWidget {
  final String chatId;
  final VoidCallback? onMembersAdded;

  const GroupInviteFriendsSheet({
    super.key,
    required this.chatId,
    this.onMembersAdded,
  });

  @override
  ConsumerState<GroupInviteFriendsSheet> createState() =>
      _GroupInviteFriendsSheetState();
}

class _GroupInviteFriendsSheetState
    extends ConsumerState<GroupInviteFriendsSheet> {
  final Set<String> _selectedUserIds = {};
  final List<api.InviteCandidate> _candidates = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingCandidates = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  int _requestToken = 0;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadCandidates(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    if (!_isLoadingCandidates && !_isLoadingMore && _hasMore) {
      unawaited(_loadCandidates());
    }
  }

  Future<void> _loadCandidates({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasMore = true;
      if (mounted) setState(() => _isLoadingCandidates = true);
    } else {
      if (_isLoadingMore || !_hasMore) return;
      if (mounted) setState(() => _isLoadingMore = true);
    }

    final requestPage = reset ? 1 : _page + 1;
    final requestToken = ++_requestToken;
    final keyword = _searchQuery;
    try {
      final response =
          await ref.read(api.chatServiceProvider).getInviteCandidates(
                widget.chatId,
                page: requestPage,
                keyword: keyword,
              );
      if (!mounted || requestToken != _requestToken) return;
      if (!response.isSuccess || response.data == null) {
        setState(() {
          _isLoadingCandidates = false;
          _isLoadingMore = false;
          if (reset) {
            _candidates.clear();
            _total = 0;
            _hasMore = false;
          }
        });
        if (response.message.trim().isNotEmpty) {
          _showSnack(
            _inviteServerMessage(
              context,
              response.message,
              zhCN: '获取可邀请好友失败',
              zhTW: '取得可邀請好友失敗',
              en: 'Failed to load invite candidates',
            ),
            isError: true,
          );
        }
        // 开关关闭等 403：刷新群资料，入口由上层按 can_add_members 再判断。
        if (response.code == 403) {
          ref.invalidate(chatDetailProvider(widget.chatId));
        }
        return;
      }

      final page = response.data!;
      setState(() {
        if (reset) {
          _candidates
            ..clear()
            ..addAll(page.list);
        } else {
          final seen = _candidates.map((c) => c.userId).toSet();
          _candidates.addAll(
            page.list.where((c) => c.userId.isNotEmpty && seen.add(c.userId)),
          );
        }
        _page = page.page;
        _total = page.total;
        _hasMore = _candidates.length < _total;
        _isLoadingCandidates = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _isLoadingCandidates = false;
        _isLoadingMore = false;
        if (reset) {
          _candidates.clear();
          _total = 0;
          _hasMore = false;
        }
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final keyword = value.trim();
      if (keyword == _searchQuery) return;
      setState(() => _searchQuery = keyword);
      unawaited(_loadCandidates(reset: true));
    });
  }

  int _addedCount(ApiResponse response) {
    final data = response.data;
    if (data is Map) {
      final added = data['added'];
      if (added is int) return added;
      return int.tryParse(added?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  void _refreshGroupData() {
    ref.invalidate(chatDetailProvider(widget.chatId));
    ref.invalidate(chatMembersProvider(widget.chatId));
    unawaited(ref.read(chatListProvider.notifier).refresh());
    widget.onMembersAdded?.call();
  }

  Future<void> _submitInvite() async {
    if (_isLoading) return;
    final selected = _selectedUserIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (selected.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final response = await ref.read(api.chatServiceProvider).addMembers(
            widget.chatId,
            selected,
          );
      if (!mounted) return;

      if (response.isSuccess) {
        final added = _addedCount(response);
        _refreshGroupData();
        if (added >= selected.length && added > 0) {
          Navigator.pop(context);
          _showSnack(
            _inviteText(
              context,
              zhCN: '已成功邀请 $added 位好友',
              zhTW: '已成功邀請 $added 位好友',
              en: 'Successfully invited $added friends',
            ),
          );
        } else if (added > 0 && added < selected.length) {
          _selectedUserIds.clear();
          unawaited(_loadCandidates(reset: true));
          _showSnack(
            _inviteText(
              context,
              zhCN: '已新增 $added 人（共选择 ${selected.length} 人），请核对成员列表',
              zhTW: '已新增 $added 人（共選擇 ${selected.length} 人），請核對成員列表',
              en:
                  'Added $added of ${selected.length} selected. Please check the member list.',
            ),
          );
        } else {
          // added=0：不能一律说「全部已在群里」
          _selectedUserIds.clear();
          unawaited(_loadCandidates(reset: true));
          _showSnack(
            _inviteText(
              context,
              zhCN: '未新增成员，请重新确认',
              zhTW: '未新增成員，請重新確認',
              en: 'No members were added. Please review and try again.',
            ),
          );
        }
      } else {
        if (response.code == 403) {
          ref.invalidate(chatDetailProvider(widget.chatId));
          unawaited(_loadCandidates(reset: true));
        }
        _showSnack(
          _inviteServerMessage(
            context,
            response.message,
            zhCN: '邀请失败',
            zhTW: '邀請失敗',
            en: 'Invite failed',
          ),
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack(
        _inviteText(
          context,
          zhCN: '邀请失败，请重试',
          zhTW: '邀請失敗，請重試',
          en: 'Invite failed. Please try again.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.surfaceFor(context);
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.cardFor(context)
        : AppColors.lightBackground;
    final ink = AppColors.primaryFor(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _inviteText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                    style: const TextStyle(color: Colors.grey, fontSize: 17),
                  ),
                ),
                Text(
                  _inviteText(
                    context,
                    zhCN: '邀请好友',
                    zhTW: '邀請好友',
                    en: 'Invite Friends',
                  ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                TextButton(
                  onPressed: _selectedUserIds.isEmpty || _isLoading
                      ? null
                      : _submitInvite,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _inviteText(
                            context,
                            zhCN:
                                '邀请${_selectedUserIds.isNotEmpty ? "(${_selectedUserIds.length})" : ""}',
                            zhTW:
                                '邀請${_selectedUserIds.isNotEmpty ? "(${_selectedUserIds.length})" : ""}',
                            en: _selectedUserIds.isNotEmpty
                                ? 'Invite (${_selectedUserIds.length})'
                                : 'Invite',
                          ),
                          style: TextStyle(
                            color: _selectedUserIds.isEmpty ? Colors.grey : ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                onChanged: _onSearchChanged,
                style: TextStyle(color: AppColors.textPrimaryFor(context)),
                decoration: InputDecoration(
                  hintText: _inviteText(
                    context,
                    zhCN: '搜索好友备注/昵称',
                    zhTW: '搜尋好友備註/暱稱',
                    en: 'Search friend remark / nickname',
                  ),
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoadingCandidates
                ? const Center(child: CircularProgressIndicator())
                : _candidates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.person_off_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? _inviteText(
                                      context,
                                      zhCN: '未找到可邀请的好友',
                                      zhTW: '找不到可邀請的好友',
                                      en: 'No inviteable friends found',
                                    )
                                  : _inviteText(
                                      context,
                                      zhCN: '暂无可邀请的好友',
                                      zhTW: '暫無可邀請的好友',
                                      en: 'No friends available to invite',
                                    ),
                              style: const TextStyle(
                                fontSize: 17,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount:
                            _candidates.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _candidates.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final contact = _candidates[index];
                          final userId = contact.userId;
                          final shortId = contact.visibleShortId;
                          final isSelected = _selectedUserIds.contains(userId);
                          final displayName = contact.displayName.isNotEmpty
                              ? contact.displayName
                              : _inviteText(
                                  context,
                                  zhCN: '用户',
                                  zhTW: '用戶',
                                  en: 'User',
                                );

                          return ListTile(
                            leading: Stack(
                              children: [
                                AvatarWidget(
                                  name: displayName,
                                  avatar: contact.avatar,
                                  userId: contact.uuid,
                                  size: 44,
                                ),
                                if (isSelected)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: ink,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: bgColor,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: ColoredNameWidget(
                                    name: displayName,
                                    nicknameColor: contact.nicknameColor,
                                    fontSize: 17,
                                  ),
                                ),
                                if (contact.emojiAvatar != null &&
                                    contact.emojiAvatar!.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  EmojiStatusWidget(
                                    emoji: contact.emojiAvatar!,
                                    size: 18,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: shortId != null
                                ? Text(
                                    '暖邻ID：$shortId',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  )
                                : null,
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: ink)
                                : Icon(
                                    Icons.radio_button_unchecked,
                                    color: Colors.grey.shade400,
                                  ),
                            onTap: () {
                              if (userId.isEmpty) return;
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(userId);
                                } else {
                                  _selectedUserIds.add(userId);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
