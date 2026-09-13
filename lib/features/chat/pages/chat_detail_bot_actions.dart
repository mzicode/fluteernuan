part of 'chat_detail_page.dart';

extension _ChatDetailBotActions on _ChatDetailPageState {
  Future<void> _handleBotCallback(String messageId, String data) async {
    final service = ref.read(api.chatServiceProvider);
    var response = await service.submitBotCallback(widget.chatId,
        messageId: messageId, data: data);
    if (!mounted) return;
    if (!response.isSuccess || response.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              response.message.isEmpty ? '按钮操作失败，请重试' : response.message)));
      return;
    }
    var result = response.data!;
    for (var attempt = 0;
        attempt < 8 && result.status == 'pending';
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      final polled = await service.getBotCallbackStatus(result.id);
      if (polled.isSuccess && polled.data != null) result = polled.data!;
    }
    if (!mounted) return;
    final text = result.text.trim().isEmpty
        ? (result.status == 'answered' ? '操作成功' : '请求已发送给机器人')
        : result.text.trim();
    if (result.showAlert) {
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('机器人提示'),
                  content: Text(text),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('确定'))
                  ]));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}
