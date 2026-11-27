// 文件用途：实现 _ChatDetailPageFlow 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailPageFlow 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail page flow 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailPageFlow on _ChatDetailPageState {
  // 流程逻辑：`_cleanupOnExit` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _cleanupOnExit() {
    // 防止重复执行（back button 和 PopScope 会双重触发）
    if (_hasCleanedUp || !mounted) return;
    _hasCleanedUp = true;
    // 标记不再活跃，停止发送已读回执
    ref.read(messageListProvider(widget.chatId).notifier).setActive(false);
    // 清除活跃聊天 ID
    ref.read(chatListProvider.notifier).setActiveChatId(null);
  }

  /// 处理返回按钮点击
  void _handleBackButton() {
    _cleanupOnExit();
    Navigator.of(context).pop();
  }

  void _onScroll() {
    if (!mounted) return;

    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToBottom) {
      _updateState(() => _showScrollToBottom = showButton);
    }

    // 键盘收起防抖：滚动 300ms 后才收起，避免频繁触发
    if (_inputFocusNode.hasFocus) {
      _keyboardDismissTimer?.cancel();
      _keyboardDismissTimer = Timer(const Duration(milliseconds: 300), () {
        if (_inputFocusNode.hasFocus && mounted) {
          _inputFocusNode.unfocus();
        }
      });
    }

    // 分页加载：接近顶部时加载更多（列表是 reverse 的，所以是 maxScrollExtent）
    if (_scrollController.hasClients && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // 领取记录已从列表去掉。剩下的内容撑不满一屏时 maxScroll 为 0，
      // 仍要继续拉更早的消息，否则红包气泡和上面的历史都出不来。
      if (maxScroll - currentScroll < 500) {
        _loadMoreMessages();
      }
    }
  }

  /// 加载更多历史消息
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    try {
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .loadMoreMessages();
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 收起键盘和表情选择器
  void _dismissKeyboardAndEmoji() {
    // 收起键盘
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    }
    // 收起表情选择器
    if (_showEmojiPickerState) {
      _updateState(() => _showEmojiPickerState = false);
    }
    if (_showAttachmentPickerState) {
      _updateState(() => _showAttachmentPickerState = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 滚动到指定消息（用于点击回复预览时跳转）
  Future<void> _scrollToMessage(String messageId, {int? targetSeq}) async {
    if (messageId.isEmpty) {
      _showMessageLocateFailed();
      return;
    }

    final found = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .ensureMessageLoaded(messageId, targetSeq: targetSeq);
    if (!mounted) return;

    final messages = ref.read(messageListProvider(widget.chatId));
    final index = messages.indexWhere((m) => m.id == messageId);

    if (!found || index == -1) {
      _showMessageNotInView();
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _scrollMessageIntoView(messageId);
  }

  void _scrollMessageIntoView(String messageId, {int retries = 16}) {
    if (!mounted) return;

    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      _highlightMessage(messageId);
      return;
    }

    if (retries <= 0 || !_scrollController.hasClients) {
      _showMessageLocateFailed();
      return;
    }

    final messages = ref.read(messageListProvider(widget.chatId));
    final displayItems =
        _buildMessageDisplayItems(_visibleChatMessages(messages));
    final displayIndex = _messageDisplayIndex(displayItems, messageId);
    if (displayIndex < 0) {
      _showMessageNotInView();
      return;
    }

    final position = _scrollController.position;
    var firstBuilt = -1;
    var lastBuilt = -1;
    for (var i = 0; i < displayItems.length; i++) {
      final ids = displayItems[i].albumMessages.isNotEmpty
          ? displayItems[i].albumMessages.map((item) => item.id)
          : [displayItems[i].message.id];
      if (ids.any((id) => _messageKeys[id]?.currentContext != null)) {
        if (firstBuilt < 0) firstBuilt = i;
        lastBuilt = i;
      }
    }

    final current = position.pixels;
    final maxOffset = position.maxScrollExtent;
    double nextOffset;
    if (firstBuilt < 0 || lastBuilt < 0) {
      nextOffset = (displayIndex * 84.0).clamp(0.0, maxOffset);
    } else if (displayIndex < firstBuilt) {
      nextOffset =
          (current - position.viewportDimension * 0.85).clamp(0.0, maxOffset);
    } else if (displayIndex > lastBuilt) {
      nextOffset =
          (current + position.viewportDimension * 0.85).clamp(0.0, maxOffset);
    } else {
      nextOffset = (displayIndex * 84.0).clamp(0.0, maxOffset);
    }

    if ((nextOffset - current).abs() >= 1) {
      _scrollController.jumpTo(nextOffset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 32), () {
        if (mounted) {
          _scrollMessageIntoView(messageId, retries: retries - 1);
        }
      });
    });
  }

  void _showMessageNotInView() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _translate(
            context,
            'message_not_in_current_view',
            _localizedText(
              zhCN: '消息不在当前视图中',
              zhTW: '消息不在目前視圖中',
              en: 'The message is not in the current view',
            ),
          ),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showMessageLocateFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            zhCN: '暂时无法定位到这条消息',
            zhTW: '暫時無法定位到這則訊息',
            en: 'Unable to locate this message for now',
          ),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 高亮显示目标消息

  void _highlightMessage(String messageId) {
    _updateState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _updateState(() => _highlightedMessageId = null);
      }
    });
  }
}
