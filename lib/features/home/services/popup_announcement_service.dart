import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/services/api/api_client.dart';

class PopupAnnouncement {
  final String announcementId;
  final int revision;
  final String title;
  final String content;
  final String imageUrl;
  final String displayToken;
  final String frequency;

  const PopupAnnouncement({
    required this.announcementId,
    required this.revision,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.displayToken,
    required this.frequency,
  });

  bool get hasImage => imageUrl.trim().isNotEmpty;
  bool get hasContent => content.trim().isNotEmpty || title.trim().isNotEmpty;
}

class PopupAnnouncementImage {
  final Uint8List bytes;
  final double width;
  final double height;

  const PopupAnnouncementImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// 宽 / 高。异常尺寸时按 16:9 横幅处理。
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 16 / 9;
    return width / height;
  }
}

class PopupAnnouncementFetch {
  final bool eligible;
  final PopupAnnouncement? announcement;

  const PopupAnnouncementFetch({
    required this.eligible,
    this.announcement,
  });
}

class PopupAnnouncementAck {
  final bool acknowledged;
  final bool duplicate;
  final int? httpStatus;
  final String? errorCode;

  const PopupAnnouncementAck({
    required this.acknowledged,
    this.duplicate = false,
    this.httpStatus,
    this.errorCode,
  });

  bool get retryLater => httpStatus == 503;
}

/// 同一次进程启动共用一个 open_event_id；重试不得换号。
class PopupAnnouncementSession {
  static final String openEventId = _createOpenEventId();
  static final Set<String> completedUserIds = <String>{};

  static String _createOpenEventId() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final random = Random.secure();
    final suffix =
        List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)])
            .join();
    return 'app_open_$suffix';
  }
}

class PopupAnnouncementService {
  final ApiClient _api;

  const PopupAnnouncementService(this._api);

  Future<PopupAnnouncementFetch?> fetch() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/app/popup-announcement',
      queryParameters: {
        'open_event_id': PopupAnnouncementSession.openEventId,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!response.isSuccess || response.data == null) return null;
    final data = response.data!;
    if (data['eligible'] != true) {
      return const PopupAnnouncementFetch(eligible: false);
    }
    final raw = data['announcement'];
    if (raw is! Map) {
      return const PopupAnnouncementFetch(eligible: false);
    }
    final announcement = Map<String, dynamic>.from(raw);
    final token = data['display_token']?.toString().trim() ?? '';
    final id = announcement['announcement_id']?.toString().trim() ?? '';
    if (token.isEmpty || id.isEmpty) {
      return const PopupAnnouncementFetch(eligible: false);
    }
    return PopupAnnouncementFetch(
      eligible: true,
      announcement: PopupAnnouncement(
        announcementId: id,
        revision: (announcement['revision'] as num?)?.toInt() ?? 0,
        title: announcement['title']?.toString() ?? '',
        content: announcement['content']?.toString() ?? '',
        imageUrl: announcement['image_url']?.toString() ?? '',
        displayToken: token,
        frequency: announcement['frequency']?.toString() ?? '',
      ),
    );
  }

  Future<PopupAnnouncementImage?> loadImage(String imageUrl) async {
    final path = _imageRequestPath(imageUrl);
    if (path == null) return null;
    final bytes = await _api.getBytes(path);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final frame = await decodeImageFromList(bytes);
      final image = PopupAnnouncementImage(
        bytes: bytes,
        width: frame.width.toDouble(),
        height: frame.height.toDouble(),
      );
      frame.dispose();
      return image;
    } catch (e) {
      debugPrint('[PopupAnnouncement] image decode failed: $e');
      return null;
    }
  }

  Future<PopupAnnouncementAck> acknowledge(String displayToken) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/app/popup-announcement/ack',
      data: {
        'display_token': displayToken,
        'open_event_id': PopupAnnouncementSession.openEventId,
      },
      fromJson: (data) =>
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
    if (response.isSuccess) {
      final data = response.data ?? response.rawData ?? const {};
      return PopupAnnouncementAck(
        acknowledged: data['acknowledged'] == true || data['duplicate'] == true,
        duplicate: data['duplicate'] == true,
        httpStatus: 200,
      );
    }
    return PopupAnnouncementAck(
      acknowledged: false,
      httpStatus: response.httpStatus ?? response.code,
      errorCode: response.errorCode,
    );
  }

  String? _imageRequestPath(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
      return trimmed;
    }
    final base = Uri.tryParse(ApiConfig.baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    final origin = base.hasPort
        ? '${base.scheme}://${base.host}:${base.port}'
        : '${base.scheme}://${base.host}';
    if (trimmed.startsWith('/')) return '$origin$trimmed';
    return '$origin/$trimmed';
  }
}
