import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/pages/document_preview_page.dart';

void main() {
  testWidgets('offers an external app for legacy Office files', (tester) async {
    var openedExternally = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentPreviewPage(
          path: 'legacy.doc',
          fileName: 'legacy.doc',
          onOpenExternally: () async => openedExternally = true,
        ),
      ),
    );
    await _pumpAsyncWork(tester);

    expect(find.text('旧版 Office 格式'), findsOneWidget);
    expect(find.textContaining('DOCX'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '使用其他应用打开'));
    await tester.pump();
    expect(openedExternally, isTrue);
  });
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
