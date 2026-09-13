import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputPath = Platform.environment['CUSTOMER_IM_QA_DRIVER_SCREENSHOT_DIR'] ??
      'build/integration-screenshots';
  final outputDirectory = Directory(outputPath);
  await outputDirectory.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${outputDirectory.path}/$name.png').writeAsBytes(
        bytes,
        flush: true,
      );
      return true;
    },
  );
}
