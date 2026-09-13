// 文件用途：实现 _ChatDetailTranslationActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailTranslationActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail translation actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailTranslationActions on _ChatDetailPageState {
  // 流程逻辑：`_canTranslateMessage` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  bool _canTranslateMessage(MessageItem message) {
    if (message.burnAfterRead || message.isDeleted) {
      return false;
    }
    return _messageTextForTranslation(message).isNotEmpty ||
        message.type == MessageItemType.text;
  }

  String _messageTextForTranslation(MessageItem message) {
    switch (message.type) {
      case MessageItemType.text:
      case MessageItemType.call:
      case MessageItemType.system:
        return message.content.trim();
      case MessageItemType.voice:
        return message.content.trim();
      default:
        return '';
    }
  }

  String _translationTargetLanguage() {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return '英文';
      case AppLanguage.zhTW:
        return '繁体中文';
      case AppLanguage.zhCN:
        return '简体中文';
    }
  }

  Future<void> _handleTranslateMessage(MessageItem message) async {
    if (_messageTranslations.containsKey(message.id)) {
      _updateState(() => _messageTranslations.remove(message.id));
      return;
    }
    if (_translatingMessageIds.contains(message.id)) return;

    final sourceText = _messageTextForTranslation(message);
    if (sourceText.isEmpty && message.type != MessageItemType.text) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '这条消息没有可翻译的文字',
          zhTW: '這則訊息沒有可翻譯的文字',
          en: 'There is no text to translate.',
        ),
      );
      return;
    }

    final targetLang = _translationTargetLanguage();
    _updateState(() => _translatingMessageIds.add(message.id));

    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.translateMessage(
        chatId: widget.chatId,
        msgId: message.id,
        text: sourceText.isNotEmpty ? sourceText : null,
        targetLang: targetLang,
      );
      if (!mounted) return;
      if (!response.isSuccess || response.data == null) {
        _updateState(() => _translatingMessageIds.remove(message.id));
        AppSnackBar.error(
          context,
          _displayServerMessage(
            raw: response.message,
            zhCN: '翻译失败',
            zhTW: '翻譯失敗',
            en: 'Translation failed',
          ),
        );
        return;
      }
      final result = response.data!;
      if (result.translation.trim().isEmpty) {
        _updateState(() => _translatingMessageIds.remove(message.id));
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '没有返回译文',
            zhTW: '沒有返回譯文',
            en: 'No translation returned.',
          ),
        );
        return;
      }
      _updateState(() {
        _translatingMessageIds.remove(message.id);
        _messageTranslations[message.id] = result.translation.trim();
      });
    } catch (_) {
      if (!mounted) return;
      _updateState(() => _translatingMessageIds.remove(message.id));
      AppSnackBar.error(
        context,
        _localizedText(
          zhCN: '翻译失败，请稍后重试',
          zhTW: '翻譯失敗，請稍後重試',
          en: 'Translation failed. Please try again.',
        ),
      );
    }
  }
}
