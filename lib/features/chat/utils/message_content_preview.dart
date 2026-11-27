// 文件用途：把消息内容转成引用/预览可读文案，避免红包/转账等 JSON 原文泄漏到 UI。
import 'dart:convert';

import '../../../core/i18n/app_localizations.dart';
import '../providers/message_provider.dart';
import 'system_message_text.dart';

String _previewLabel({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String redPacketReplyLabel() => _previewLabel(
      zhCN: '红包',
      zhTW: '紅包',
      en: 'Red packet',
    );

String transferReplyLabel() => _previewLabel(
      zhCN: '转账',
      zhTW: '轉帳',
      en: 'Transfer',
    );

bool _looksLikeRedPacketJson(Map<dynamic, dynamic> map) {
  if (map.containsKey('red_packet_id')) return true;
  if (map.containsKey('remaining_count') ||
      map.containsKey('remaining_amount')) {
    return true;
  }
  if (map.containsKey('is_claimed') || map.containsKey('claimed_amount')) {
    return true;
  }
  final type = map['type']?.toString().trim().toLowerCase() ?? '';
  if (type == 'normal' ||
      type == 'lucky' ||
      type == 'red_packet' ||
      type == 'exclusive') {
    return true;
  }
  if (map.containsKey('total_amount') && map.containsKey('total_count')) {
    return true;
  }
  final status = map['status']?.toString().trim().toLowerCase() ?? '';
  if (map.containsKey('total_amount') &&
      (status == 'active' ||
          status == 'finished' ||
          status == 'expired' ||
          status == 'claimed')) {
    return true;
  }
  return map.containsKey('total_amount') &&
      map.containsKey('sender_id') &&
      (map.containsKey('chat_id') || map.containsKey('message'));
}

bool _looksLikeTransferJson(Map<dynamic, dynamic> map) {
  if (map.containsKey('transfer_id')) return true;
  final type = map['type']?.toString().trim().toLowerCase() ?? '';
  if (type == 'transfer') return true;
  return map.containsKey('amount') &&
      (map.containsKey('receiver_id') || map.containsKey('sender_id')) &&
      !map.containsKey('total_count') &&
      !map.containsKey('remaining_count');
}

String _unwrapJsonCandidate(String content) {
  var candidate = content.trim();
  if (candidate.startsWith('"') && candidate.endsWith('"')) {
    try {
      final inner = jsonDecode(candidate);
      if (inner is String && inner.trim().isNotEmpty) {
        candidate = inner.trim();
      }
    } catch (_) {}
  }
  return candidate;
}

MessageItemType? _replyContentTypeFromJsonMap(Map<dynamic, dynamic> map) {
  if (_looksLikeRedPacketJson(map)) return MessageItemType.redPacket;
  if (_looksLikeTransferJson(map)) return MessageItemType.transfer;
  return null;
}

/// 将服务端 msg_type / 正文推断为本地消息类型。
MessageItemType? replyContentTypeFromRaw(int? msgType, String content) {
  switch (msgType) {
    case 2:
      return MessageItemType.image;
    case 3:
      return MessageItemType.video;
    case 4:
      return MessageItemType.voice;
    case 5:
      return MessageItemType.file;
    case 6:
      return MessageItemType.location;
    case 8:
      return MessageItemType.sticker;
    case 10:
      return MessageItemType.contact;
    case 11:
      return MessageItemType.call;
    case 12:
      return MessageItemType.redPacket;
    case 13:
      return MessageItemType.transfer;
    case 14:
      return MessageItemType.forwardBundle;
    case 99:
      return MessageItemType.system;
  }

  final candidate = _unwrapJsonCandidate(content);
  if (candidate.startsWith('{')) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return _replyContentTypeFromJsonMap(
          Map<dynamic, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
  }

  final lower = content.toLowerCase();
  if (lower.contains('total_amount') ||
      lower.contains('red_packet') ||
      lower.contains('remaining_count') ||
      lower.contains('is_claimed')) {
    return MessageItemType.redPacket;
  }
  if (lower.contains('transfer_id')) {
    return MessageItemType.transfer;
  }
  return null;
}

String labelForReplyContentType(MessageItemType? type) {
  switch (type) {
    case MessageItemType.redPacket:
      return redPacketReplyLabel();
    case MessageItemType.transfer:
      return transferReplyLabel();
    case MessageItemType.image:
      return _previewLabel(zhCN: '图片', zhTW: '圖片', en: 'Photo');
    case MessageItemType.video:
      return _previewLabel(zhCN: '视频', zhTW: '影片', en: 'Video');
    case MessageItemType.voice:
    case MessageItemType.audio:
      return _previewLabel(zhCN: '语音', zhTW: '語音', en: 'Voice');
    case MessageItemType.file:
      return _previewLabel(zhCN: '文件', zhTW: '檔案', en: 'File');
    case MessageItemType.sticker:
    case MessageItemType.gif:
      return _previewLabel(zhCN: '表情', zhTW: '表情', en: 'Sticker');
    case MessageItemType.location:
      return _previewLabel(zhCN: '位置', zhTW: '位置', en: 'Location');
    case MessageItemType.contact:
      return _previewLabel(zhCN: '名片', zhTW: '名片', en: 'Contact');
    case MessageItemType.call:
      return _previewLabel(zhCN: '通话', zhTW: '通話', en: 'Call');
    case MessageItemType.forwardBundle:
      return _previewLabel(zhCN: '聊天记录', zhTW: '聊天記錄', en: 'Chat history');
    case MessageItemType.system:
      return _previewLabel(zhCN: '系统消息', zhTW: '系統訊息', en: 'System');
    case MessageItemType.poll:
      return _previewLabel(zhCN: '投票', zhTW: '投票', en: 'Poll');
    case MessageItemType.text:
    case null:
      return '';
  }
}

/// 引用条最终展示文案：优先类型，其次清洗正文。红包固定为「红包」。
String resolveReplyPreviewText({
  required String content,
  MessageItemType? contentType,
}) {
  final typeLabel = labelForReplyContentType(contentType);
  if (typeLabel.isNotEmpty) return typeLabel;

  final inferred = replyContentTypeFromRaw(null, content);
  final inferredLabel = labelForReplyContentType(inferred);
  if (inferredLabel.isNotEmpty) return inferredLabel;

  return sanitizeEncodedReplyPreview(content);
}

/// 将可能是 JSON 的引用正文清洗成可读预览。
String sanitizeEncodedReplyPreview(String content) {
  final value = content.trim();
  if (value.isEmpty) return value;

  // 已是可读标签
  if (value == '红包' || value == '[红包]' || value == '紅包' || value == '[紅包]') {
    return redPacketReplyLabel();
  }
  if (value == '转账' || value == '[转账]' || value == '轉帳' || value == '[轉帳]') {
    return transferReplyLabel();
  }

  final candidate = _unwrapJsonCandidate(value);

  if (candidate.startsWith('{')) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        final map = Map<dynamic, dynamic>.from(decoded);
        final inferred = _replyContentTypeFromJsonMap(map);
        if (inferred != null) {
          return labelForReplyContentType(inferred);
        }
        if (encodedSystemEventType(candidate) != null) {
          return resolveSystemMessageText(candidate);
        }
        if (map.containsKey('messages') ||
            (map.containsKey('title') && map.containsKey('items'))) {
          return _previewLabel(
            zhCN: '聊天记录',
            zhTW: '聊天記錄',
            en: 'Chat history',
          );
        }
      }
    } catch (_) {}
  }

  final lower = value.toLowerCase();
  if (lower.contains('total_amount') ||
      lower.contains('red_packet') ||
      lower.contains('remaining_count') ||
      lower.contains('remaining_amount') ||
      lower.contains('is_claimed')) {
    return redPacketReplyLabel();
  }
  if (lower.contains('transfer_id') ||
      (value.contains('{') &&
          lower.contains('amount') &&
          (lower.contains('receiver_id') || lower.contains('sender_id')))) {
    return transferReplyLabel();
  }

  if (candidate.startsWith('{') || candidate.startsWith('[')) {
    // 未知 JSON 不再显示「消息」，避免红包误伤；仍不展示源码
    return _previewLabel(zhCN: '消息', zhTW: '訊息', en: 'Message');
  }

  return value;
}

/// 按消息类型生成引用/输入栏预览文案。
String formatMessageContentPreview(MessageItem message) {
  final typeLabel = labelForReplyContentType(message.type);
  if (message.type == MessageItemType.redPacket ||
      message.type == MessageItemType.transfer ||
      message.type == MessageItemType.image ||
      message.type == MessageItemType.video ||
      message.type == MessageItemType.voice ||
      message.type == MessageItemType.audio ||
      message.type == MessageItemType.sticker ||
      message.type == MessageItemType.gif ||
      message.type == MessageItemType.call ||
      message.type == MessageItemType.forwardBundle ||
      message.type == MessageItemType.poll) {
    return typeLabel;
  }

  switch (message.type) {
    case MessageItemType.text:
      return sanitizeEncodedReplyPreview(message.content);
    case MessageItemType.file:
      final name = message.fileName?.trim() ?? '';
      final label = typeLabel;
      return name.isEmpty ? label : '$label $name';
    case MessageItemType.location:
      final title = message.locationTitle?.trim() ?? '';
      if (title.isNotEmpty) return title;
      final address = message.locationAddress?.trim() ?? '';
      if (address.isNotEmpty) return address;
      return typeLabel;
    case MessageItemType.contact:
      final name = message.contactName?.trim() ?? '';
      return name.isEmpty ? typeLabel : '$typeLabel $name';
    case MessageItemType.system:
      return resolveSystemMessageText(message.content);
    default:
      return typeLabel.isNotEmpty
          ? typeLabel
          : sanitizeEncodedReplyPreview(message.content);
  }
}

int? rawMsgTypeForMessageItemType(MessageItemType type) {
  switch (type) {
    case MessageItemType.text:
      return 1;
    case MessageItemType.image:
      return 2;
    case MessageItemType.video:
      return 3;
    case MessageItemType.voice:
      return 4;
    case MessageItemType.file:
      return 5;
    case MessageItemType.location:
      return 6;
    case MessageItemType.sticker:
    case MessageItemType.gif:
      return 8;
    case MessageItemType.contact:
      return 10;
    case MessageItemType.call:
      return 11;
    case MessageItemType.redPacket:
      return 12;
    case MessageItemType.transfer:
      return 13;
    case MessageItemType.forwardBundle:
      return 14;
    case MessageItemType.system:
      return 99;
    case MessageItemType.audio:
      return 4;
    case MessageItemType.poll:
      return 1;
  }
}
