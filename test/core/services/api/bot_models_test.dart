import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/chat_service.dart';

void main() {
  test('BotAccount parses developer and group response contract', () {
    final bot = BotAccount.fromJson({
      'bot': {'uuid': 'bot-1', 'kind': 'third_party', 'status': 'active'},
      'user': {'uuid': 'user-1', 'nickname': '助手', 'username': 'helper_bot'},
      'token': 'one-time-token',
      'token_hint': 'abc…xyz',
    });

    expect(bot.botId, 'bot-1');
    expect(bot.botUserId, 'user-1');
    expect(bot.username, 'helper_bot');
    expect(bot.token, 'one-time-token');
  });

  test('GroupBot parses permissions and keeps safe defaults', () {
    final bot = GroupBot.fromJson({
      'bot': {'uuid': 'bot-2', 'kind': 'third_party', 'status': 'active'},
      'user': {'uuid': 'user-2', 'nickname': '群助手', 'username': 'group_bot'},
      'permission': {
        'can_receive_commands': true,
        'can_read_all_messages': false,
        'can_send_messages': false,
      },
    });

    expect(bot.permission.canReceiveCommands, isTrue);
    expect(bot.permission.canReadAllMessages, isFalse);
    expect(bot.permission.canSendMessages, isFalse);
    expect(bot.permission.canSendMedia, isFalse);
  });

  test('BotWelcomePolicy parses template variables configuration', () {
    final policy = BotWelcomePolicy.fromJson({
      'enabled': true,
      'template': '欢迎 {members}',
      'merge_window_seconds': 8,
    });

    expect(policy.enabled, isTrue);
    expect(policy.template, contains('{members}'));
    expect(policy.mergeWindowSeconds, 8);
  });

  test('BotReplyMarkup parses url callback and copy buttons', () {
    final markup = BotReplyMarkup.fromJson({
      'inline_keyboard': [
        [
          {'text': '官网', 'url': 'https://example.com'},
          {'text': '选择', 'callback_data': 'pick:1'},
          {'text': '复制', 'copy_text': 'ABC'},
        ],
      ],
    });

    expect(markup.inlineKeyboard.single, hasLength(3));
    expect(markup.inlineKeyboard.single[1].callbackData, 'pick:1');
    expect(markup.toJson()['inline_keyboard'], isNotEmpty);
  });

  test('P1 keyword callback and expanded permissions parse safely', () {
    final permission = BotChatPermission.fromJson({
      'can_send_media': true,
      'can_delete_messages': true,
      'can_pin_messages': true,
    });
    final rule = BotKeywordRule.fromJson({
      'uuid': 'rule-1',
      'keyword': '帮助',
      'match_mode': 'contains',
      'reply_text': '请查看帮助',
      'cooldown_seconds': 20,
      'enabled': true,
    });
    final callback = BotCallbackResult.fromJson({
      'id': 'callback-1',
      'status': 'answered',
      'text': '完成',
      'show_alert': true,
    });

    expect(permission.canSendMedia, isTrue);
    expect(permission.canDeleteMessages, isTrue);
    expect(permission.canPinMessages, isTrue);
    expect(rule.id, 'rule-1');
    expect(callback.showAlert, isTrue);
  });
}
