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

  test('refresh bypasses the fresh-list cache after adding a contact',
      () async {
    final api = _ContactApiClient(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[
        _contact(id: 1, uuid: 'user-1', username: 'first'),
      ],
      <Map<String, dynamic>>[
        _contact(id: 1, uuid: 'user-1', username: 'first'),
        _contact(id: 2, uuid: 'user-2', username: 'new-contact'),
      ],
    ]);
    final webSocket = WebSocketService();
    final notifier = ContactListNotifier(api, webSocket, 'account-a');

    await notifier.loadFromServer(force: true);
    expect(notifier.state.map((item) => item.uuid), <String?>['user-1']);
    expect(api.getCalls, 1);

    // This is the path used after add/already-contact. It must not be skipped
    // by the 30-second freshness window.
    await notifier.refresh();

    expect(
      notifier.state.map((item) => item.uuid),
      <String?>['user-1', 'user-2'],
    );
    expect(api.getCalls, 2);

    notifier.dispose();
    webSocket.dispose();
    api.dispose();
  });

  test('accepted friend event refreshes contacts and conversations', () async {
    final api = _ContactApiClient(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[
        _contact(id: 2, uuid: 'user-2', username: 'new-friend'),
      ],
    ]);
    final webSocket = _TestWebSocketService();
    var chatRefreshes = 0;
    final notifier = ContactListNotifier(
      api,
      webSocket,
      'account-a',
      onFriendAccepted: () async {
        chatRefreshes++;
      },
    );

    webSocket.emit('friend_request_changed', <String, dynamic>{
      'request': <String, dynamic>{'status': 'accepted'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(chatRefreshes, 1);
    expect(api.getCalls, 1);
    expect(notifier.state.single.username, 'new-friend');

    notifier.dispose();
    webSocket.dispose();
    api.dispose();
  });
}

Map<String, dynamic> _contact({
  required int id,
  required String uuid,
  required String username,
}) {
  return <String, dynamic>{
    'id': id,
    'uuid': uuid,
    'name': username,
    'nickname': username,
    'username': username,
    'is_online': false,
  };
}

class _ContactApiClient extends ApiClient {
  _ContactApiClient(this.pages);

  final List<List<Map<String, dynamic>>> pages;
  int getCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    dynamic cancelToken,
  }) async {
    expect(path, '/contact/list');
    final index = getCalls < pages.length ? getCalls : pages.length - 1;
    final list = pages[index];
    getCalls++;
    final payload = <String, dynamic>{
      'list': list,
      'total': list.length,
      'page': 1,
      'page_size': 500,
    };
    return ApiResponse<T>(
      code: 0,
      message: 'success',
      data: payload as T,
    );
  }
}

class _TestWebSocketService extends WebSocketService {
  final Map<String, List<Function(dynamic)>> _testHandlers =
      <String, List<Function(dynamic)>>{};
  int _nextId = 0;

  @override
  String registerHandler(String type, Function(dynamic) handler) {
    _testHandlers.putIfAbsent(type, () => <Function(dynamic)>[]).add(handler);
    return '${type}_${++_nextId}';
  }

  @override
  void unregisterHandler(String handlerId) {}

  void emit(String type, dynamic data) {
    for (final handler in List<Function(dynamic)>.from(
      _testHandlers[type] ?? const <Function(dynamic)>[],
    )) {
      handler(data);
    }
  }
}
