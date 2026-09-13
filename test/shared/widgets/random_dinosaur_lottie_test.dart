import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:customer/shared/widgets/random_dinosaur_lottie.dart';

void main() {
  test('all dinosaur variants map to packaged Cubigator assets', () async {
    for (var variant = 1; variant <= 30; variant++) {
      final path = RandomDinosaurLottie.assetPathForVariant(variant);
      expect(path,
          endsWith('cubigator_${variant.toString().padLeft(2, '0')}.json'));
      final animation = await rootBundle.loadString(path);
      expect(animation, contains('"layers"'), reason: 'invalid $path');
    }
  });

  test('invalid dinosaur variants are rejected', () {
    expect(
      () => RandomDinosaurLottie.assetPathForVariant(0),
      throwsRangeError,
    );
    expect(
      () => RandomDinosaurLottie.assetPathForVariant(31),
      throwsRangeError,
    );
  });

  testWidgets('renders the actual Lottie animation instead of a text fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RandomDinosaurLottie(
            variant: 1,
            width: 100,
            height: 100,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.byKey(const ValueKey('dinosaur_lottie_01')), findsOneWidget);
    expect(find.text('*'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
