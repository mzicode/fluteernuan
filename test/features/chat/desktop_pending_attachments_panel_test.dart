import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/utils/desktop_drop_attachment.dart';
import 'package:customer/features/chat/widgets/desktop_pending_attachments_panel.dart';

void main() {
  testWidgets('shows pending files and exposes remove and clear actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const attachments = [
      DesktopDropAttachment(
        path: r'C:\files\contract.pdf',
        name: 'customer-contract-with-a-very-long-name.pdf',
        extension: 'pdf',
        size: 2048,
        type: DesktopDropAttachmentType.file,
      ),
      DesktopDropAttachment(
        path: r'C:\files\demo.mp4',
        name: 'demo.mp4',
        extension: 'mp4',
        size: 3 * 1024 * 1024,
        type: DesktopDropAttachmentType.video,
      ),
    ];
    final removed = <int>[];
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPendingAttachmentsPanel(
            attachments: attachments,
            onRemove: removed.add,
            onClear: () => cleared = true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('desktop_pending_attachments_panel')),
      findsOneWidget,
    );
    expect(
      find.text('customer-contract-with-a-very-long-name.pdf'),
      findsOneWidget,
    );
    expect(find.text('demo.mp4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop_pending_attachment_0')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const Key(r'remove_desktop_pending_attachment_C:\files\contract.pdf'),
      ),
    );
    expect(removed, [0]);

    await tester.tap(
      find.byKey(const Key('clear_desktop_pending_attachments')),
    );
    expect(cleared, isTrue);
  });
}
