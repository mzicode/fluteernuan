import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/services/android_legacy_office_preview_service.dart';
import 'package:customer/features/chat/services/document_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.customer/legacy_office_preview');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps native DOC text to the unified document preview', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'extract');
      expect(call.arguments, <String, dynamic>{
        'path': '/app/report.doc',
        'extension': 'doc',
      });
      return <String, dynamic>{
        'available': true,
        'kind': 'doc',
        'text': 'Legacy Word content',
        'truncated': false,
      };
    });

    final result = await AndroidLegacyOfficePreviewService.load(
      path: '/app/report.doc',
      fileName: 'report.doc',
    );

    expect(result.kind, DocumentPreviewKind.docx);
    expect(result.text, 'Legacy Word content');
  });

  test('maps native XLS rows to worksheet sections', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => <String, dynamic>{
                  'available': true,
                  'kind': 'xls',
                  'sections': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'title': 'Overview',
                      'rows': <List<String>>[
                        <String>['Name', 'Value'],
                        <String>['Alice', '42'],
                      ],
                    },
                  ],
                  'truncated': true,
                });

    final result = await AndroidLegacyOfficePreviewService.load(
      path: '/app/report.xls',
      fileName: 'report.xls',
    );

    expect(result.kind, DocumentPreviewKind.xlsx);
    expect(result.sections.single.title, 'Overview');
    expect(result.sections.single.rows.last, <String>['Alice', '42']);
    expect(result.truncated, isTrue);
  });

  test('maps native PPT text and reports parser failures', () async {
    var fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (fail) {
        return <String, dynamic>{
          'available': false,
          'reason': 'invalid_document',
        };
      }
      return <String, dynamic>{
        'available': true,
        'kind': 'ppt',
        'sections': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Slide 1', 'text': 'Opening'},
        ],
      };
    });

    final result = await AndroidLegacyOfficePreviewService.load(
      path: '/app/deck.ppt',
      fileName: 'deck.ppt',
    );
    expect(result.kind, DocumentPreviewKind.pptx);
    expect(result.sections.single.text, 'Opening');

    fail = true;
    await expectLater(
      AndroidLegacyOfficePreviewService.load(
        path: '/app/deck.ppt',
        fileName: 'deck.ppt',
      ),
      throwsA(
        isA<AndroidLegacyOfficePreviewException>().having(
          (error) => error.code,
          'code',
          'invalid_document',
        ),
      ),
    );
  });
}
