// 文件用途：实现 _ChatDetailForwardActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailForwardActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail forward actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailForwardActions on _ChatDetailPageState {
  // 流程逻辑：`_canForwardMessage` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  bool _canForwardMessage(MessageItem message) {
    return _canForwardFromCurrentChat && !message.burnAfterRead;
  }

  void _showForwardBlockedHint() {
    AppSnackBar.warning(
      context,
      _localizedText(
        zhCN: '阅后即焚消息不支持转发',
        zhTW: '閱後即焚訊息不支援轉發',
        en: 'This message cannot be forwarded',
      ),
    );
  }

  /// 处理转发消息
  void _handleForward(MessageItem message) {
    if (!_canForwardMessage(message)) {
      _showForwardBlockedHint();
      return;
    }
    GlobalHaptics.selection();
    _showForwardDialog(message);
  }

  /// 显示好友群发对话框
  void _showForwardDialog(MessageItem message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedContactKeys = <String>{};
    var isSubmitting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final contacts = ref
              .read(contactListProvider)
              .where((contact) =>
                  (contact.uuid?.trim().isNotEmpty ?? false) ||
                  contact.id.trim().isNotEmpty)
              .toList(growable: false);
          final allSelected = contacts.isNotEmpty &&
              contacts.every((contact) =>
                  selectedContactKeys.contains(_forwardContactKey(contact)));

          Future<void> submit() async {
            if (isSubmitting || selectedContactKeys.isEmpty) return;
            setSheetState(() => isSubmitting = true);

            final selectedContacts = contacts
                .where((contact) =>
                    selectedContactKeys.contains(_forwardContactKey(contact)))
                .toList(growable: false);
            final chatNotifier = ref.read(chatListProvider.notifier);
            final targetChatIds = <String>[];
            var failedCount = 0;

            for (final contact in selectedContacts) {
              final targetUserId = (contact.uuid?.trim().isNotEmpty ?? false)
                  ? contact.uuid!.trim()
                  : contact.id.trim();
              final targetChat = await chatNotifier.createPrivateChatFromServer(
                targetUserId: targetUserId,
                targetUserName: contact.name,
                avatar: contact.avatar,
              );
              if (targetChat == null) {
                failedCount++;
              } else {
                targetChatIds.add(targetChat.id);
              }
            }

            if (sheetContext.mounted) Navigator.pop(sheetContext);
            if (mounted)
              _showTopToast(_localizedText(
                zhCN: '正在发送给 ${targetChatIds.length} 位好友',
                zhTW: '正在傳送給 ${targetChatIds.length} 位好友',
                en: 'Sending to ${targetChatIds.length} friends',
              ));

            final notifier = ref.read(
              messageListProvider(widget.chatId).notifier,
            );
            final results = await forwardMessagesToTargetsReliably(
              [message],
              targetChatIds,
              (targetId, sourceMessage, clientMsgId) => notifier.forwardMessage(
                sourceMessage.id,
                targetId,
                clientMsgId: clientMsgId,
                sourceMessage: sourceMessage,
              ),
            );
            final successCount =
                results.where((result) => result.isComplete).length;
            failedCount += results.where((result) => !result.isComplete).length;

            if (mounted) {
              _showTopToast(_localizedText(
                zhCN: '群发完成：成功 $successCount 人，失败 $failedCount 人',
                zhTW: '群發完成：成功 $successCount 人，失敗 $failedCount 人',
                en: 'Broadcast complete: $successCount succeeded, $failedCount failed',
              ));
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _localizedText(
                              zhCN: '群发给好友',
                              zhTW: '群發給好友',
                              en: 'Send to friends',
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  _showLegacyForwardDialog(message);
                                },
                          child: const Text('单个转发'),
                        ),
                        TextButton(
                          onPressed: isSubmitting || contacts.isEmpty
                              ? null
                              : () => setSheetState(() {
                                    if (allSelected) {
                                      selectedContactKeys.clear();
                                    } else {
                                      selectedContactKeys
                                        ..clear()
                                        ..addAll(contacts
                                            .take(100)
                                            .map(_forwardContactKey));
                                    }
                                  }),
                          child: Text(allSelected ? '取消全选' : '全选'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: contacts.isEmpty
                        ? Center(
                            child: Text(
                              _localizedText(
                                zhCN: '暂无好友',
                                zhTW: '暫無好友',
                                en: 'No friends yet',
                              ),
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              final key = _forwardContactKey(contact);
                              final selected =
                                  selectedContactKeys.contains(key);
                              return ListTile(
                                leading: AvatarWidget(
                                  avatar: contact.avatar,
                                  name: contact.name,
                                  size: 44,
                                ),
                                title: Text(contact.name),
                                trailing: Checkbox(
                                  value: selected,
                                  onChanged: isSubmitting
                                      ? null
                                      : (_) => setSheetState(() {
                                            if (selected) {
                                              selectedContactKeys.remove(key);
                                            } else if (selectedContactKeys
                                                    .length <
                                                100) {
                                              selectedContactKeys.add(key);
                                            } else {
                                              _showTopToast('单次最多选择100位好友');
                                            }
                                          }),
                                ),
                                onTap: isSubmitting
                                    ? null
                                    : () => setSheetState(() {
                                          if (selected) {
                                            selectedContactKeys.remove(key);
                                          } else if (selectedContactKeys
                                                  .length <
                                              100) {
                                            selectedContactKeys.add(key);
                                          } else {
                                            _showTopToast('单次最多选择100位好友');
                                          }
                                        }),
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isSubmitting || selectedContactKeys.isEmpty
                            ? null
                            : submit,
                        child: Text(
                          isSubmitting
                              ? '发送中...'
                              : '发送给 ${selectedContactKeys.length} 位好友',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _forwardContactKey(ContactItem contact) {
    final uuid = contact.uuid?.trim() ?? '';
    return uuid.isNotEmpty ? uuid : contact.id.trim();
  }

  /// 旧的会话转发对话框（保留代码，避免影响多选消息转发流程）
  void _showLegacyForwardDialog(MessageItem message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _translate(context, 'forward_to', 'Forward to...'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final chatState = ref.watch(chatListProvider);
                    final chats = [
                      ...chatState.pinnedChats,
                      ...chatState.regularChats,
                    ];
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        if (chat.id == widget.chatId)
                          return const SizedBox.shrink();

                        return ListTile(
                          leading: AvatarWidget(
                            avatar: chat.avatar,
                            name: chat.name,
                            size: 48,
                          ),
                          title: Text(
                            chat.name,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          onTap: () async {
                            if (chat.type == ChatItemType.group ||
                                chat.type == ChatItemType.channel) {
                              final chatDetail = await ref.read(
                                chatDetailProvider(chat.id).future,
                              );
                              if (chatDetail != null) {
                                if (chat.type == ChatItemType.channel &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast(
                                      _translate(
                                        context,
                                        'only_admin_can_post_forward',
                                        _localizedText(
                                          zhCN: '仅管理员可发布内容，无法转发',
                                          zhTW: '僅管理員可發布內容，無法轉發',
                                          en: 'Only admins can post here, so this message cannot be forwarded',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (chat.type == ChatItemType.group &&
                                    !chatDetail.canSendMessage &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast(
                                      _translate(
                                        context,
                                        'group_muted_cannot_forward',
                                        _localizedText(
                                          zhCN: '该群组已禁言，无法转发',
                                          zhTW: '該群組已禁言，無法轉發',
                                          en: 'This group is muted, so the message cannot be forwarded',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              _forwardMessageTo(message, chat.id, chat.name);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 转发消息到指定聊天
  void _forwardMessageTo(
    MessageItem message,
    String targetChatId,
    String chatTitle,
  ) async {
    if (!_canForwardMessage(message)) {
      _showForwardBlockedHint();
      return;
    }
    if (_isForwardingMessages) return;
    _isForwardingMessages = true;
    GlobalHaptics.medium();

    bool success;
    try {
      success = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .forwardMessage(message.id, targetChatId);
    } finally {
      _isForwardingMessages = false;
    }

    if (!mounted) return;

    if (success) {
      _showTopToast(
        _translate(
          context,
          'forwarded_to',
          _localizedText(
            zhCN: '已转发到 {name}',
            zhTW: '已轉發到 {name}',
            en: 'Forwarded to {name}',
          ),
          {'name': chatTitle},
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'forward_failed',
              _localizedText(
                zhCN: '转发失败',
                zhTW: '轉發失敗',
                en: 'Forward failed',
              ),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// 显示顶部浮动提示 (Telegram 风格)
  void _showTopToast(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        message: message,
        isDark: isDark,
        onDismiss: () {
          entry.remove();
          _activeOverlays.remove(entry);
        },
      ),
    );

    _activeOverlays.add(entry);
    overlay.insert(entry);
  }
}
