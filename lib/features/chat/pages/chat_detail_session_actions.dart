// 文件用途：实现 _ChatDetailSessionActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailSessionActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail session actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailSessionActions on _ChatDetailPageState {
  // 流程逻辑：`_leaveChat` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _leaveChat() async {
    final (success, errorMsg) = await ref
        .read(chatListProvider.notifier)
        .leaveChatFromServer(widget.chatId);

    if (!mounted) return;

    if (success) {
      // 退出成功，返回聊天列表
      context.go('/home');
    } else {
      // 显示错误
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                _localizedText(
                  zhCN: '操作失败，请重试',
                  zhTW: '操作失敗，請重試',
                  en: 'Action failed. Please try again.',
                ),
          ),
        ),
      );
    }
  }

  /// 发起通话
  Future<void> _startCall(CallType type) async {
    if (!_ensureChatWritable()) return;
    final callService = ref.read(callServiceProvider.notifier);

    // Never substitute chatId for a user UUID while chat detail is still
    // loading. The server correctly rejects that value as an unknown target.
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetUserId = _resolvedPrivateTargetUserId();
    if (targetUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('用户资料加载中，请稍后重试')),
        );
      }
      return;
    }
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar ?? widget.avatar;

    GlobalHaptics.medium();

    final success = callService.startCall(
      targetUserId: targetUserId,
      targetName: targetName,
      targetAvatar: targetAvatar,
      type: type,
    );

    // The app-level call navigator opens CallPage after the synchronous
    // preparing state is published. Do not await network, permissions or RTC
    // from this tap handler.
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: '当前已有通话正在进行',
              zhTW: '目前已有通話正在進行',
              en: 'Another call is already in progress',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _startMeeting(
    MeetingType meetingType, {
    List<String> inviteeUserIds = const [],
  }) async {
    if (!_ensureChatWritable()) return;
    final meetingService = ref.read(meetingServiceProvider);
    final response = await meetingService.createMeeting(
      chatId: widget.chatId,
      meetingType: meetingType,
      title: widget.chatName,
      inviteeUserIds: inviteeUserIds,
      maxParticipants: 32,
    );

    if (!mounted) return;
    if (!response.isSuccess || response.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _displayServerMessage(
              raw: response.message,
              zhCN: '发起会议失败',
              zhTW: '發起會議失敗',
              en: 'Failed to start the meeting',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final created = response.data!;
    final authUser = ref.read(authServiceProvider).user;
    _updateState(() {
      _activeMeetingInfo = MeetingActiveInfo(
        hasActive: true,
        meetingId: created.meetingId,
        chatId: widget.chatId,
        title: created.title,
        meetingType: created.meetingType,
        channelName: created.channelName,
        roomName: created.roomName,
        rtcProvider: created.rtcProvider,
        serverUrl: created.serverUrl,
        startTime: DateTime.now(),
        hostUserId: authUser?.uuid ?? '',
        hostName: authUser?.nickname ?? '',
        hostAvatar: authUser?.avatar,
      );
    });
    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => MeetingPage(
          meetingId: created.meetingId,
          chatId: widget.chatId,
          chatName: widget.chatName,
        ),
      ),
    );
  }
}
