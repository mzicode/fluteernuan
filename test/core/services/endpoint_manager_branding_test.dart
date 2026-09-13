import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/endpoint_manager.dart';

void main() {
  test('default endpoints use the current production service', () {
    expect(EndpointManager.fallbackServerUrl, 'https://web.cybndo.com');
    expect(
      EndpointManager.fallbackWsUrl,
      'wss://web.cybndo.com/api/v1/ws',
    );
    expect(EndpointManager.fallbackServerUrls, [
      'https://web.cybndo.com',
      'https://web.ojyvn.com',
      'https://web.iexici.cn',
    ]);
  });
}
