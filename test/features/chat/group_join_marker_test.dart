import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/providers/chat_provider.dart';
import 'package:customer/features/chat/services/group_join_marker_store.dart';
import 'package:customer/features/chat/widgets/chat_list_item.dart';

void main() {
  test('empty preview should keep local join marker text', () {
    expect(shouldApplyGroupJoinPreview(null), isTrue);
    expect(shouldApplyGroupJoinPreview(''), isTrue);
    expect(shouldApplyGroupJoinPreview('  '), isTrue);
    expect(shouldApplyGroupJoinPreview('hello'), isFalse);
  });

  test('join preview text recognition covers locales', () {
    expect(isGroupJoinPreviewText(groupJoinPreviewText()), isTrue);
    expect(isGroupJoinPreviewText('Joined the group'), isTrue);
    expect(isGroupJoinPreviewText('已加入群組'), isTrue);
    expect(isGroupJoinPreviewText('普通消息'), isFalse);
  });

  test('apply join markers only when server preview is empty', () {
    final joinedAt = DateTime(2026, 9, 29, 10);
    final chats = applyGroupJoinMarkersToChats(
      chats: [
        ChatItem(
          id: 'g1',
          name: 'Group A',
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
        ChatItem(
          id: 'g2',
          name: 'Group B',
          lastMessage: 'already has message',
          lastMessageTime: joinedAt,
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
      ],
      markers: {
        'g1': joinedAt,
        'g2': joinedAt,
      },
      previewText: '已加入群组',
    );

    expect(chats[0].lastMessage, '已加入群组');
    expect(chats[0].lastMessageTime, joinedAt);
    expect(chats[1].lastMessage, 'already has message');
  });

  test('real server preview clears join marker', () {
    final joinedAt = DateTime(2026, 9, 29, 10);
    final ready = groupJoinMarkersReadyToClear(
      chats: [
        ChatItem(
          id: 'g1',
          name: 'Group A',
          lastMessage: 'hello',
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
        ChatItem(
          id: 'g2',
          name: 'Group B',
          lastMessage: '已加入群组',
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
        ChatItem(
          id: 'g3',
          name: 'Group C',
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
      ],
      markers: {
        'g1': joinedAt,
        'g2': joinedAt,
        'g3': joinedAt,
      },
    );

    expect(ready, ['g1']);
  });

  test('server refresh then join-marker apply keeps empty-group preview', () {
    final joinedAt = DateTime(2026, 9, 29, 12);
    final merged = mergeServerChatsWithLocalDrafts(
      [
        ChatItem(
          id: 'g1',
          name: 'New Group',
          type: ChatItemType.group,
          createdAt: joinedAt,
        ),
      ],
      const [],
    );
    final applied = applyGroupJoinMarkersToChats(
      chats: merged,
      markers: {'g1': joinedAt},
      previewText: '已加入群组',
    );

    expect(applied.single.lastMessage, '已加入群组');
    expect(applied.single.lastMessageTime, joinedAt);
  });
}
