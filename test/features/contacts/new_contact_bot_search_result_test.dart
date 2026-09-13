import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/contacts/pages/new_contact_page.dart';

void main() {
  test('search result preserves bot identity returned by search-all', () {
    final result = SearchResult.fromJson(<String, dynamic>{
      'id': 'bot-user-uuid',
      'name': 'DeepSeek AI助手',
      'username': 'deepseek_ai_bot',
      'type': 'user',
      'is_bot': true,
      'account_type': 'bot',
      'bot_kind': 'ai_persona',
    });

    expect(result.type, 'user');
    expect(result.isBot, isTrue);
    expect(result.accountType, 'bot');
    expect(result.botKind, 'ai_persona');
    expect(result.canStartPrivateChat, isTrue);
  });

  test('non-contact human search result cannot start private chat', () {
    final result = SearchResult.fromJson(<String, dynamic>{
      'id': 'human-user-uuid',
      'name': 'Alice',
      'type': 'user',
      'account_type': 'human',
      'is_contact': false,
    });

    expect(result.isBot, isFalse);
    expect(result.accountType, 'human');
    expect(result.botKind, isNull);
    expect(result.canStartPrivateChat, isFalse);
  });

  test('contact human search result can start private chat', () {
    final result = SearchResult.fromJson(<String, dynamic>{
      'id': 'contact-user-uuid',
      'name': 'Bob',
      'type': 'user',
      'account_type': 'human',
      'is_contact': true,
    });

    expect(result.isBot, isFalse);
    expect(result.isContact, isTrue);
    expect(result.canStartPrivateChat, isTrue);
  });
}
