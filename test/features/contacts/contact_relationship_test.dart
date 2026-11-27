import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer/core/services/api/api_client.dart';
import 'package:customer/core/services/api/websocket_service.dart';
import 'package:customer/features/contacts/providers/contact_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ContactRelationship.fromJson maps friends and pending states', () {
    final friends = ContactRelationship.fromJson(<String, dynamic>{
      'user_uuid': 'user-b',
      'is_friend': true,
      'relationship_status': 'friends',
    });
    expect(friends.canStartConversation, isTrue);
    expect(friends.isSelf, isFalse);

    final pending = ContactRelationship.fromJson(<String, dynamic>{
      'user_uuid': 'user-b',
      'is_friend': false,
      'relationship_status': 'pending_outgoing',
    });
    expect(pending.canStartConversation, isFalse);
    expect(pending.relationshipStatus, ContactRelationship.statusPendingOutgoing);

    final self = ContactRelationship.fromJson(<String, dynamic>{
      'user_uuid': 'user-a',
      'is_friend': false,
      'relationship_status': 'self',
    });
    expect(self.isSelf, isTrue);
    expect(self.canStartConversation, isFalse);
  });

  test('ContactRelationship.fromJson accepts truthy is_friend and nested data', () {
    final numericFriend = ContactRelationship.fromJson(<String, dynamic>{
      'user_uuid': 'user-b',
      'is_friend': 1,
      'relationship_status': 'none',
    });
    expect(numericFriend.canStartConversation, isTrue);

    final stringFriend = ContactRelationship.fromJson(<String, dynamic>{
      'userUuid': 'user-b',
      'isFriend': 'true',
      'relationshipStatus': 'Friend',
    });
    expect(stringFriend.canStartConversation, isTrue);

    final nested = ContactRelationship.fromJson(<String, dynamic>{
      'code': 0,
      'data': <String, dynamic>{
        'user_uuid': 'user-b',
        'is_friend': true,
        'relationship_status': 'friends',
      },
    });
    expect(nested.canStartConversation, isTrue);
    expect(nested.userUuid, 'user-b');

    final stranger = ContactRelationship.fromJson(<String, dynamic>{
      'user_uuid': 'user-b',
      'is_friend': 0,
      'relationship_status': 'none',
    });
    expect(stranger.canStartConversation, isFalse);
  });

  test('fetchRelationship calls GET /contact/relationship/{uuid}', () async {
    final api = _RelationshipApiClient();
    final webSocket = WebSocketService();
    final notifier = ContactListNotifier(api, webSocket, 'account-a');

    final relationship = await notifier.fetchRelationship('target-uuid');

    expect(api.lastPath, '/contact/relationship/target-uuid');
    expect(relationship, isNotNull);
    expect(relationship!.isFriend, isTrue);
    expect(relationship.relationshipStatus, ContactRelationship.statusFriends);

    notifier.dispose();
    webSocket.dispose();
    api.dispose();
  });
}

class _RelationshipApiClient extends ApiClient {
  String? lastPath;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    lastPath = path;
    final payload = <String, dynamic>{
      'user_uuid': 'target-uuid',
      'is_friend': true,
      'relationship_status': 'friends',
    };
    return ApiResponse<T>(
      code: 0,
      message: 'success',
      data: payload as T,
    );
  }
}
