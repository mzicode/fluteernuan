// 文件用途：描述桌面端拖入聊天窗口后进入待发送区的附件。
// 核心逻辑：统一识别图片、视频和普通文件，并保存发送与预览所需元数据。

enum DesktopDropAttachmentType { image, video, file }

class DesktopDropAttachment {
  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
  };
  static const Set<String> videoExtensions = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'm4v',
    'webm',
  };

  final String path;
  final String name;
  final String extension;
  final int size;
  final DesktopDropAttachmentType type;
  final int? width;
  final int? height;

  const DesktopDropAttachment({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.type,
    this.width,
    this.height,
  });

  static String extensionFromName(String name) {
    final normalized = name.trim();
    final separator = normalized.lastIndexOf('.');
    if (separator <= 0 || separator == normalized.length - 1) return '';
    return normalized.substring(separator + 1).toLowerCase();
  }

  static DesktopDropAttachmentType typeFromExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    if (imageExtensions.contains(normalized)) {
      return DesktopDropAttachmentType.image;
    }
    if (videoExtensions.contains(normalized)) {
      return DesktopDropAttachmentType.video;
    }
    return DesktopDropAttachmentType.file;
  }
}

String formatDesktopDropAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
