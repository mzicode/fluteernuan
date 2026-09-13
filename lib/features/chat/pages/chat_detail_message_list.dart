// 文件用途：实现 _ChatDetailMessageList 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMessageList 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail message list 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMessageList on _ChatDetailPageState {
  // 流程逻辑：`_buildMessageList` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildMessageList(List<MessageItem> messages, bool isDark) {
    // 性能优化：bubbleColors 在 ListView 外层一次性获取，避免每个 item 都 watch
    final bubbleColors = ref.watch(bubbleColorProvider);
    final messageSettings = ref.watch(messageSettingsProvider);
    final contactDisplayNames = this._buildContactDisplayNameMap(
      ref.watch(contactListProvider),
    );
    final chatDetail = ref.watch(chatDetailProvider(widget.chatId)).valueOrNull;
    final canOpenMemberProfile =
        widget.chatType != ChatType.group || (chatDetail?.myRole ?? 0) >= 2;
    final canSeeMembershipEvents =
        widget.chatType != ChatType.group || (chatDetail?.myRole ?? 0) >= 2;
    final visibleMessages = messages
        .where(
          (message) =>
              !message.isDeleted &&
              (widget.chatType != ChatType.group ||
                  message.type != MessageItemType.system ||
                  (canSeeMembershipEvents &&
                      isGroupMembershipSystemMessage(message.content))),
        )
        .toList(growable: false);
    final displayItems = _buildMessageDisplayItems(visibleMessages);
    final voicePlaylist = visibleMessages
        .where(
          (message) =>
              message.type == MessageItemType.voice && !message.isDeleted,
        )
        .toList(growable: false);

    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (_inputFocusNode.hasFocus) {
          _inputFocusNode.unfocus();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        itemCount: displayItems.length,
        cacheExtent: 400,
        // Voice bubbles request keep-alive only while they own playback. This
        // prevents viewport/cache recycling from tearing down the active
        // player without retaining every message row permanently.
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        addSemanticIndexes: false,
        physics: Theme.of(context).platform == TargetPlatform.iOS
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
        itemBuilder: (context, index) {
          final entry = displayItems[index];
          final message = this._applyContactDisplayName(
            entry.message,
            contactDisplayNames,
          );
          final albumMessages = entry.albumMessages
              .map(
                (item) =>
                    this._applyContactDisplayName(item, contactDisplayNames),
              )
              .toList(growable: false);
          final previousMessage = index < displayItems.length - 1
              ? this._applyContactDisplayName(
                  displayItems[index + 1].message,
                  contactDisplayNames,
                )
              : null;
          final nextMessage = index > 0
              ? this._applyContactDisplayName(
                  displayItems[index - 1].message,
                  contactDisplayNames,
                )
              : null;

          final showDateDivider = previousMessage == null ||
              !this._isSameDay(message.createdAt, previousMessage.createdAt);

          final isFirstInGroup = previousMessage == null ||
              previousMessage.senderId != message.senderId ||
              message.createdAt
                      .difference(previousMessage.createdAt)
                      .inMinutes >
                  5;

          final isLastInGroup = nextMessage == null ||
              nextMessage.senderId != message.senderId ||
              nextMessage.createdAt.difference(message.createdAt).inMinutes > 5;

          final visibilityId = entry.isAlbum
              ? 'album_${message.mediaGroupId}_${albumMessages.length}'
              : message.id;
          final row = Column(
            key: _messageKeys.putIfAbsent(visibilityId, GlobalKey.new),
            children: [
              if (showDateDivider) this._buildDateDivider(message.createdAt),
              if (message.type == MessageItemType.system)
                this._buildSystemMessage(message.content)
              else
                Container(
                  decoration: _highlightedMessageId == message.id
                      ? BoxDecoration(
                          color: AppColors.primaryWithOpacity(context, 0.2),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: RepaintBoundary(
                    child: _isSelectionMode
                        ? this._buildSelectableMessage(
                            message,
                            albumMessages,
                            isFirstInGroup,
                            isLastInGroup,
                            bubbleColors,
                            messageSettings.fontSize,
                            isDark,
                          )
                        : MessageBubble(
                            message: message,
                            voicePlaylist: voicePlaylist,
                            albumMessages: albumMessages,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup,
                            showSenderName: widget.chatType == ChatType.group ||
                                (widget.chatType == ChatType.channel &&
                                    !message.isOutgoing),
                            isGroupChat: widget.chatType == ChatType.group,
                            onTap: this._buildMessageTapHandler(message),
                            onLongPressStart: (details) =>
                                this._showMessageOptions(
                              message,
                              details.globalPosition,
                            ),
                            onSecondaryTapDown: (details) =>
                                this._showMessageOptions(
                              message,
                              details.globalPosition,
                            ),
                            onDoubleTap: () => this._reactToMessage(message),
                            onRetry: message.status == MessageStatus.failed
                                ? () => ref
                                    .read(
                                      messageListProvider(widget.chatId)
                                          .notifier,
                                    )
                                    .resendMessage(message.id)
                                : null,
                            customOutgoingColor: bubbleColors.outgoing,
                            customIncomingColor: bubbleColors.incoming,
                            canOpenMemberProfile: canOpenMemberProfile,
                            onMentionUser: widget.chatType != ChatType.private
                                ? (userId, userName) =>
                                    _mentionUser(userId, userName)
                                : null,
                            messageFontSize: messageSettings.fontSize,
                            translationText: _messageTranslations[message.id],
                            translationLoading:
                                _translatingMessageIds.contains(message.id),
                            onBotCallback: _handleBotCallback,
                            onReplyTap: message.replyTo != null
                                ? () => this._scrollToMessage(
                                      message.replyTo!.messageId,
                                    )
                                : null,
                          ),
                  ),
                ),
            ],
          );

          return VisibilityDetector(
            key: ValueKey('message_read_${widget.chatId}_$visibilityId'),
            onVisibilityChanged: (info) =>
                _handleMessageVisibility(entry, info),
            child: row,
          );
        },
      ),
    );
  }

  void _handleMessageVisibility(
    _MessageDisplayItem entry,
    VisibilityInfo info,
  ) {
    final messages = entry.isAlbum ? entry.albumMessages : [entry.message];
    var highestIncomingSeq = 0;
    for (final message in messages) {
      if (!message.isOutgoing && message.seq > highestIncomingSeq) {
        highestIncomingSeq = message.seq;
      }
    }

    final isResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!shouldMarkMessageAsExposed(
      isIncoming: highestIncomingSeq > 0,
      sequence: highestIncomingSeq,
      appIsResumed: isResumed,
      visibleFraction: info.visibleFraction,
      itemHeight: info.size.height,
    )) {
      return;
    }

    ref
        .read(messageListProvider(widget.chatId).notifier)
        .markVisibleMessagesAsReadUpToSeq(highestIncomingSeq);
  }

  /// 构建多选模式操作栏
  List<_MessageDisplayItem> _buildMessageDisplayItems(
    List<MessageItem> messages,
  ) {
    final out = <_MessageDisplayItem>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (!_canGroupAsAlbum(message)) {
        out.add(_MessageDisplayItem(message: message));
        index++;
        continue;
      }

      final group = <MessageItem>[message];
      var next = index + 1;
      while (next < messages.length &&
          _isSameAlbumMessage(message, messages[next])) {
        group.add(messages[next]);
        next++;
      }

      if (group.length > 1) {
        out.add(
          _MessageDisplayItem(message: group.first, albumMessages: group),
        );
        index = next;
      } else {
        out.add(_MessageDisplayItem(message: message));
        index++;
      }
    }
    return out;
  }

  bool _canGroupAsAlbum(MessageItem message) {
    final groupId = message.mediaGroupId?.trim();
    return groupId != null &&
        groupId.isNotEmpty &&
        message.type == MessageItemType.image &&
        !message.isDeleted &&
        !message.burnAfterRead;
  }

  bool _isSameAlbumMessage(MessageItem anchor, MessageItem candidate) {
    return _canGroupAsAlbum(candidate) &&
        candidate.mediaGroupId == anchor.mediaGroupId &&
        candidate.senderId == anchor.senderId &&
        candidate.chatId == anchor.chatId;
  }

  Widget _buildSelectionActionBar(bool isDark) {
    final count = _selectedMessageIds.length;
    final selectedMessages = ref
        .watch(messageListProvider(widget.chatId))
        .where((message) => _selectedMessageIds.contains(message.id))
        .toList(growable: false);
    final canForwardSelected =
        count > 0 && !selectedMessages.any((message) => message.burnAfterRead);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // 取消按钮
                  TextButton.icon(
                    onPressed: _exitSelectionMode,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    label: Text(
                      _localizedText(
                        zhCN: '取消',
                        zhTW: '取消',
                        en: 'Cancel',
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  // 选中数量
                  Expanded(
                    child: Center(
                      child: Text(
                        _translate(
                          context,
                          'selected_messages_count',
                          _localizedText(
                            zhCN: '已选择 {count} 条消息',
                            zhTW: '已選擇 {count} 條消息',
                            en: '{count} messages selected',
                          ),
                          {'count': '$count'},
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),

                  // 操作按钮
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 转发
                      IconButton(
                        onPressed: canForwardSelected
                            ? this._forwardSelectedMessages
                            : null,
                        icon: Icon(
                          Icons.shortcut_rounded,
                          color: canForwardSelected
                              ? AppColors.primaryFor(context)
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                        tooltip: AppLocalizations.of(context).forward,
                      ),

                      // 删除
                      IconButton(
                        onPressed:
                            count > 0 ? this._deleteSelectedMessages : null,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: count > 0
                              ? AppColors.error
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                        tooltip: AppLocalizations.of(context).delete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 构建输入区域（检查禁言状态）
}
