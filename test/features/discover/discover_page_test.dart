import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/system_settings_service.dart';
import 'package:customer/features/discover/pages/discover_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDiscoverPage(
    WidgetTester tester, {
    required bool botMarketplaceEnabled,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) async => SystemSettings(
              botMarketplaceEnabled: botMarketplaceEnabled,
            ),
          ),
          discoverEntriesProvider.overrideWith((ref) async => const []),
          discoverBannersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: DiscoverPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('bot marketplace is hidden by default', (tester) async {
    await pumpDiscoverPage(tester, botMarketplaceEnabled: false);

    expect(find.text('机器人应用市场'), findsNothing);
    expect(find.text('广场'), findsOneWidget);
  });

  testWidgets('bot marketplace is shown only when enabled', (tester) async {
    await pumpDiscoverPage(tester, botMarketplaceEnabled: true);

    expect(find.text('机器人应用市场'), findsOneWidget);
  });
}
