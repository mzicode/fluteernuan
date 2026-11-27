import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/i18n/app_localizations.dart';
import 'package:customer/features/chat/providers/message_provider.dart';
import 'package:customer/features/chat/utils/message_content_preview.dart';

void main() {
  tearDown(() {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
  });

  test('red packet reply preview shows 红包 not 消息', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
    const json = '{"id":"rp1","sender_id":"u1","chat_id":"c1","type":"normal",'
        '"total_amount":10,"total_count":1,"remaining_amount":10,'
        '"remaining_count":1,"message":"恭喜发财","status":"active"}';

    expect(sanitizeEncodedReplyPreview(json), '红包');
    expect(
      resolveReplyPreviewText(
        content: json,
        contentType: MessageItemType.redPacket,
      ),
      '红包',
    );
    expect(
      formatMessageContentPreview(
        MessageItem(
          id: 'm1',
          chatId: 'c1',
          senderId: 'u1',
          senderName: 'A',
          type: MessageItemType.redPacket,
          content: json,
          isOutgoing: false,
          status: MessageStatus.sent,
          createdAt: DateTime(2026, 1, 1),
        ),
      ),
      '红包',
    );
  });

  test('transfer and unknown json payloads are sanitized', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
    const transfer =
        '{"transfer_id":"t1","sender_id":"u1","receiver_id":"u2","amount":3.5,"remark":"午饭"}';
    const unknown = '{"foo":1,"bar":2}';

    expect(sanitizeEncodedReplyPreview(transfer), '转账');
    expect(sanitizeEncodedReplyPreview(unknown), '消息');
    expect(sanitizeEncodedReplyPreview('普通文本'), '普通文本');
  });

  test('msg_type 12 is resolved as red packet label', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
    expect(replyContentTypeFromRaw(12, ''), MessageItemType.redPacket);
    expect(
      resolveReplyPreviewText(
        content: '[消息]',
        contentType: replyContentTypeFromRaw(12, ''),
      ),
      '红包',
    );
  });
}
