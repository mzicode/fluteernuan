import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/theme/app_colors.dart';
import 'package:customer/features/chat/providers/message_provider.dart';
import 'package:customer/features/chat/widgets/message_bubble.dart';

MessageItem _message(MessageStatus status) {
  return MessageItem(
    id: 'status-${status.name}',
    chatId: 'chat-1',
    senderId: 'sender-1',
    senderName: 'Sender',
    type: MessageItemType.text,
    content: 'status',
    isOutgoing: true,
    status: status,
    createdAt: DateTime(2026, 8, 16, 10),
    seq: 1,
  );
}

Widget _app(MessageStatus status) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: MessageBubble(
          message: _message(status),
          customOutgoingColor: const Color(0xFF20252D),
        ),
      ),
    ),
  );
}

Finder _statusFinder(MessageStatus status) {
  return find.byKey(
    ValueKey('message_status_${status.name}_status-${status.name}'),
  );
}

void main() {
  testWidgets('sending uses a progress indicator', (tester) async {
    await tester.pumpWidget(_app(MessageStatus.sending));

    expect(_statusFinder(MessageStatus.sending), findsOneWidget);
    expect(
      find.descendant(
        of: _statusFinder(MessageStatus.sending),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sent uses a single muted-green check', (tester) async {
    await tester.pumpWidget(_app(MessageStatus.sent));

    final icon = tester.widget<Icon>(_statusFinder(MessageStatus.sent));
    expect(icon.icon, Icons.check_rounded);
    expect(icon.color, AppColors.messageDelivered);
  });

  testWidgets('delivered uses a single muted-green check', (tester) async {
    await tester.pumpWidget(_app(MessageStatus.delivered));

    final icon = tester.widget<Icon>(_statusFinder(MessageStatus.delivered));
    expect(icon.icon, Icons.check_rounded);
    expect(icon.color, const Color(0xFF5D9B5D));
  });

  testWidgets('read uses bright-green double checks', (tester) async {
    await tester.pumpWidget(_app(MessageStatus.read));

    final icon = tester.widget<Icon>(_statusFinder(MessageStatus.read));
    expect(icon.icon, Icons.done_all_rounded);
    expect(icon.color, const Color(0xFF4FAE4E));
  });

  testWidgets('failed uses the semantic red error icon', (tester) async {
    await tester.pumpWidget(_app(MessageStatus.failed));

    final icon = tester.widget<Icon>(_statusFinder(MessageStatus.failed));
    expect(icon.icon, Icons.error_outline_rounded);
    expect(icon.color, AppColors.error);
  });
}
