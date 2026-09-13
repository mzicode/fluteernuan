import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/services/android_pdf_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.customer/pdf_preview');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads page count from the native PdfRenderer bridge', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return <String, dynamic>{'available': true, 'page_count': 3};
    });

    final info = await AndroidPdfPreviewService.getInfo('/cache/report.pdf');

    expect(info.pageCount, 3);
    expect(received?.method, 'getInfo');
    expect(received?.arguments, <String, dynamic>{'path': '/cache/report.pdf'});
  });

  test('returns a rendered native page path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, dynamic>{
        'rendered': true,
        'image_path': '/cache/pdf_preview/page.png',
        'width': 1200,
        'height': 1600,
      };
    });

    final page = await AndroidPdfPreviewService.renderPage(
      path: '/cache/report.pdf',
      pageIndex: 1,
      targetWidth: 1200,
    );

    expect(page.imagePath, '/cache/pdf_preview/page.png');
    expect(page.width, 1200);
    expect(page.height, 1600);
  });

  test('preserves native PDF error reasons', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      return <String, dynamic>{
        'available': false,
        'reason': 'password_required',
      };
    });

    await expectLater(
      AndroidPdfPreviewService.getInfo('/cache/encrypted.pdf'),
      throwsA(
        isA<AndroidPdfPreviewException>().having(
          (error) => error.code,
          'code',
          'password_required',
        ),
      ),
    );
  });
}
