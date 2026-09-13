import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:customer/core/services/api/api_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('online bot create, add and permission smoke test',
      (tester) async {
    const groupName = String.fromEnvironment(
      'CUSTOMER_IM_BOT_SMOKE_GROUP',
      defaultValue: 'BotTest0811',
    );
    const botUsername = String.fromEnvironment(
      'CUSTOMER_IM_BOT_SMOKE_USERNAME',
      defaultValue: 'codex_online_test_bot',
    );

    final token = await TokenStorage.getToken();
    expect(token, isNotNull, reason: 'The test device is not signed in.');
    expect(token, isNotEmpty,
        reason: 'The test device has an empty auth token.');

    final client = ApiClient()..setToken(token!);

    Future<dynamic> request(
      String method,
      String path, {
      Object? data,
      Map<String, dynamic>? queryParameters,
    }) async {
      late final ApiResponse<dynamic> response;
      switch (method) {
        case 'GET':
          response = await client.get<dynamic>(
            path,
            queryParameters: queryParameters,
          );
          break;
        case 'POST':
          response = await client.post<dynamic>(path, data: data);
          break;
        case 'PUT':
          response = await client.put<dynamic>(path, data: data);
          break;
        case 'DELETE':
          response = await client.delete<dynamic>(path, data: data);
          break;
        default:
          fail('Unsupported method: $method');
      }
      expect(
        response.code,
        0,
        reason: '$method $path failed: ${response.message}',
      );
      return response.data;
    }

    final chatListData = Map<String, dynamic>.from(
      await request(
        'GET',
        '/chat/list',
        queryParameters: <String, dynamic>{'page': 1, 'page_size': 100},
      ) as Map,
    );
    final chats = (chatListData['list'] as List? ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final group = chats.firstWhere(
      (item) => item['name']?.toString() == groupName,
      orElse: () => <String, dynamic>{},
    );
    expect(group, isNotEmpty, reason: 'Test group "$groupName" was not found.');
    final chatId = group['chat_id']?.toString() ?? '';
    expect(chatId, isNotEmpty, reason: 'The test group has no chat UUID.');

    final ownedData = Map<String, dynamic>.from(
      await request('GET', '/bots') as Map,
    );
    final owned = (ownedData['list'] as List? ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    var account = owned.firstWhere(
      (item) {
        final user = item['user'];
        return user is Map && user['username']?.toString() == botUsername;
      },
      orElse: () => <String, dynamic>{},
    );
    if (account.isEmpty) {
      account = Map<String, dynamic>.from(
        await request(
          'POST',
          '/bots',
          data: <String, dynamic>{
            'name': '在线测试机器人',
            'username': botUsername,
            'description': '由真机在线冒烟测试创建',
          },
        ) as Map,
      );
    }

    final bot = Map<String, dynamic>.from(account['bot'] as Map);
    final botId = bot['uuid']?.toString() ?? '';
    expect(botId, isNotEmpty, reason: 'Created bot has no UUID.');

    final groupBotsData = Map<String, dynamic>.from(
      await request('GET', '/chat/$chatId/bots') as Map,
    );
    final groupBots = (groupBotsData['list'] as List? ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final alreadyAdded = groupBots.any((item) {
      final itemBot = item['bot'];
      return itemBot is Map && itemBot['uuid']?.toString() == botId;
    });
    if (!alreadyAdded) {
      await request(
        'POST',
        '/chat/$chatId/bots',
        data: <String, dynamic>{'bot': botUsername},
      );
    }

    await request(
      'PUT',
      '/chat/$chatId/bots/$botId/permissions',
      data: <String, dynamic>{
        'can_receive_commands': true,
        'can_read_all_messages': false,
        'can_send_messages': true,
        'can_send_media': true,
        'can_delete_messages': false,
        'can_manage_join_requests': false,
        'can_pin_messages': true,
      },
    );

    final verifiedData = Map<String, dynamic>.from(
      await request('GET', '/chat/$chatId/bots') as Map,
    );
    final verifiedBots =
        (verifiedData['list'] as List? ?? const <dynamic>[]).cast<Map>();
    final verified = verifiedBots.firstWhere(
      (item) {
        final itemBot = item['bot'];
        return itemBot is Map && itemBot['uuid']?.toString() == botId;
      },
      orElse: () => <String, dynamic>{},
    );
    expect(verified, isNotEmpty, reason: 'The bot was not found in the group.');
    final permission = Map<String, dynamic>.from(verified['permission'] as Map);
    expect(permission['can_send_messages'], isTrue);
    expect(permission['can_send_media'], isTrue);
    expect(permission['can_pin_messages'], isTrue);

    // Keep this one bot and group in the QA account so the result can be
    // inspected manually in the device UI after the automated test.
    client.dispose();
  });
}
