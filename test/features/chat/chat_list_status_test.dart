import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/i18n/app_localizations.dart';
import 'package:customer/features/chat/providers/chat_provider.dart';
import 'package:customer/features/chat/widgets/chat_list_item.dart';

void main() {
  test('dissolved chats are excluded from client chat search', () {
    final active = ChatItem(
      id: 'active',
      name: 'Active channel',
      type: ChatItemType.channel,
      createdAt: DateTime(2026, 8, 9),
    );
    final dissolved = active.copyWith(id: 'dissolved', status: 2);

    expect(isChatVisibleInSearch(active), isTrue);
    expect(isChatVisibleInSearch(dissolved), isFalse);
  });

  test('unread badge caps display without losing the authoritative count', () {
    expect(formatUnreadBadgeCount(0), '');
    expect(formatUnreadBadgeCount(1), '1');
    expect(formatUnreadBadgeCount(99), '99');
    expect(formatUnreadBadgeCount(100), '99+');
    expect(formatUnreadBadgeCount(1000), '99+');
  });

  testWidgets('failed last message is visible even when a draft was restored',
      (tester) async {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
    final chat = ChatItem(
      id: 'chat-1',
      name: 'Peer',
      lastMessage: 'failed message',
      lastMessageTime: DateTime.now(),
      lastMessageFailed: true,
      isSentByMe: true,
      draft: 'failed message',
      type: ChatItemType.private,
      createdAt: DateTime(2026, 7, 18),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ChatListItem(chat: chat),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      find.textContaining('发送失败', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('草稿', findRichText: true), findsNothing);
  });
}
