import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:customer/features/chat/providers/message_provider.dart';
import 'package:customer/features/chat/widgets/message_bubble.dart';

MessageItem _textMessage() {
  return MessageItem(
    id: 'translation-message',
    chatId: 'chat-1',
    senderId: 'user-2',
    senderName: 'User 2',
    type: MessageItemType.text,
    content: '我改成微信这种',
    isOutgoing: false,
    createdAt: DateTime(2026, 8, 5, 14),
    seq: 1,
  );
}

Widget _app({String? translation, bool loading = false}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: _textMessage(),
          translationText: translation,
          translationLoading: loading,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('translation renders below the message with provider label',
      (tester) async {
    await tester.pumpWidget(_app(translation: 'Translate this'));

    expect(
        find.byKey(const ValueKey('message_translation_translation-message')),
        findsOneWidget);
    expect(find.text('Translate this'), findsOneWidget);
    expect(find.text('由 DeepSeek 提供翻译支持'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('translation loading state stays inline', (tester) async {
    await tester.pumpWidget(_app(loading: true));

    expect(find.text('正在翻译'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
