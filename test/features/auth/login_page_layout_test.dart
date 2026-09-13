import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/api/system_settings_service.dart';
import 'package:customer/core/utils/platform_utils.dart';
import 'package:customer/features/auth/pages/login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('agreement is visible above login on a compact phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) async => const SystemSettings(),
          ),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final agreement = find.byKey(const Key('login_terms_checkbox'));
    final loginButton = find.byKey(const Key('login_submit_button'));

    expect(agreement.hitTestable(), findsOneWidget);
    expect(loginButton.hitTestable(), findsOneWidget);
    expect(
      tester.getCenter(agreement).dy,
      lessThan(tester.getCenter(loginButton).dy),
    );
    expect(tester.takeException(), isNull);
  }, skip: PlatformUtils.isPhysicalDesktop);

  testWidgets('quick registration remains visible when carrier auth is off',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) async => const SystemSettings(
              allowQuickRegister: true,
              carrierAuthEnabled: false,
            ),
          ),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('quick_register_button')), findsOneWidget);
    expect(find.byKey(const Key('carrier_login_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the terms checkbox keeps it selected', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) async => const SystemSettings(),
          ),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final checkboxFinder = find.byKey(const Key('login_terms_checkbox'));
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

    await tester.tap(checkboxFinder);
    await tester.pump();

    expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
