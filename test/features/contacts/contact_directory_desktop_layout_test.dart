import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/providers/chat_provider.dart';
import 'package:customer/features/contacts/pages/contacts_page.dart';
import 'package:customer/features/home/pages/home_desktop_page.dart';

void main() {
  final group = ChatItem(
    id: 'group-1',
    name: '测试群聊',
    username: 'project_team',
    type: ChatItemType.group,
    createdAt: DateTime(2026),
  );

  test('PC group directory search matches name, username and pinyin', () {
    expect(contactChatDirectoryMatchesSearch(group, '测试'), isTrue);
    expect(contactChatDirectoryMatchesSearch(group, '@project_team'), isTrue);
    expect(contactChatDirectoryMatchesSearch(group, 'ceshi'), isTrue);
    expect(contactChatDirectoryMatchesSearch(group, 'csql'), isTrue);
    expect(contactChatDirectoryMatchesSearch(group, 'not-found'), isFalse);
  });

  test('desktop profile switches to compact layout at narrow widths', () {
    expect(desktopProfileUsesCompactLayout(759), isTrue);
    expect(desktopProfileUsesCompactLayout(760), isFalse);
    expect(desktopProfileUsesCompactLayout(1200), isFalse);
  });
}
