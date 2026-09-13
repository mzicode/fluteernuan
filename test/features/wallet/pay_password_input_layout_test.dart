import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/wallet/widgets/pay_password_input.dart';

Widget _host({required Size size, double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: PayPasswordInput(onCompleted: (_) {}),
      ),
    ),
  );
}

void main() {
  testWidgets('six password cells fit a narrow phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(size: const Size(320, 720)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('six password cells fit with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(size: const Size(360, 720), textScale: 2),
    );
    expect(tester.takeException(), isNull);
  });
}
