import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:customer/features/settings/pages/profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final viewports = <Size>[
    const Size(320, 568),
    const Size(393, 852),
    const Size(800, 1280),
  ];

  for (final viewport in viewports) {
    testWidgets(
      'QR card stays square without overflow at '
      '${viewport.width.toInt()}x${viewport.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ProfileQRCodePage(
                userUuid: 'layout-test-user',
                displayName: '兼容性测试用户昵称很长很长',
                username: 'layout_test_user',
                isSelfEntry: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        final qrFinder = find.byType(QrImageView);
        expect(qrFinder, findsOneWidget);
        final qrSize = tester.getSize(qrFinder);
        expect(qrSize.width, closeTo(qrSize.height, 0.01));
        expect(qrSize.width, lessThan(viewport.width));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('QR card supports enlarged Android system text', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 720),
              textScaler: TextScaler.linear(2),
            ),
            child: ProfileQRCodePage(
              userUuid: 'layout-test-user',
              displayName: '兼容性测试用户昵称很长很长',
              username: 'layout_test_user',
              isSelfEntry: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final qrSize = tester.getSize(find.byType(QrImageView));
    expect(qrSize.width, closeTo(qrSize.height, 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('save QR action writes the rendered card to the gallery',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const galChannel = MethodChannel('gal');
    final galCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galChannel, (call) async {
      galCalls.add(call);
      if (call.method == 'requestAccess') return true;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(galChannel, null);
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ProfileQRCodePage(
            userUuid: 'save-test-user',
            displayName: '保存测试用户',
            username: 'save_test_user',
            isSelfEntry: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('保存二维码'), findsOneWidget);
    expect(find.text('分享二维码'), findsNothing);

    await tester.ensureVisible(find.text('保存二维码'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '保存二维码'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.runAsync(() async {
      for (var i = 0;
          i < 20 && !galCalls.any((call) => call.method == 'putImageBytes');
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(
      galCalls.any((call) => call.method == 'putImageBytes'),
      isTrue,
    );
    expect(find.text('二维码已保存到相册'), findsOneWidget);
  });

  testWidgets('scan QR action opens the scanner route', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ProfileQRCodePage(
            userUuid: 'scan-test-user',
            displayName: '扫码测试用户',
            username: 'scan_test_user',
            isSelfEntry: false,
          ),
        ),
        GoRoute(
          path: '/scan',
          builder: (context, state) =>
              const Scaffold(body: Text('scanner destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('扫描二维码'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '扫描二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.routeInformationProvider.value.uri.path, '/scan');
    expect(find.text('scanner destination'), findsOneWidget);
  });
}
