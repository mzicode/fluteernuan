import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/utils/desktop_drop_attachment.dart';

void main() {
  group('DesktopDropAttachment', () {
    test('classifies supported image and video extensions', () {
      expect(
        DesktopDropAttachment.typeFromExtension('PNG'),
        DesktopDropAttachmentType.image,
      );
      expect(
        DesktopDropAttachment.typeFromExtension('m4v'),
        DesktopDropAttachmentType.video,
      );
      expect(
        DesktopDropAttachment.typeFromExtension('docx'),
        DesktopDropAttachmentType.file,
      );
    });

    test('extracts extensions without treating hidden files as extensions', () {
      expect(
          DesktopDropAttachment.extensionFromName('report.final.pdf'), 'pdf');
      expect(DesktopDropAttachment.extensionFromName('.env'), isEmpty);
      expect(DesktopDropAttachment.extensionFromName('README'), isEmpty);
    });

    test('formats file sizes for the pending panel', () {
      expect(formatDesktopDropAttachmentSize(512), '512 B');
      expect(formatDesktopDropAttachmentSize(1536), '1.5 KB');
      expect(formatDesktopDropAttachmentSize(2 * 1024 * 1024), '2.0 MB');
    });
  });
}
