// 文件用途：展示桌面端拖入聊天窗口、尚未确认发送的附件列表。
// 核心逻辑：按附件类型显示缩略图或文件图标，并提供逐项移除和全部清空操作。

import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../utils/desktop_drop_attachment.dart';

class DesktopPendingAttachmentsPanel extends StatelessWidget {
  final List<DesktopDropAttachment> attachments;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear;

  const DesktopPendingAttachmentsPanel({
    super.key,
    required this.attachments,
    required this.onRemove,
    required this.onClear,
  });

  String _text(
    BuildContext context, {
    required String zhCN,
    required String zhTW,
    required String en,
  }) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = AppColors.textSecondaryFor(context);

    return Container(
      key: const Key('desktop_pending_attachments_panel'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primaryWithOpacity(context, 0.13)
            : AppColors.primaryWithOpacity(context, 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.primaryWithOpacity(context, isDark ? 0.24 : 0.14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_rounded, size: 17, color: secondaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _text(
                    context,
                    zhCN: '${attachments.length} 个文件待发送，点击发送按钮确认',
                    zhTW: '${attachments.length} 個檔案待傳送，點擊傳送按鈕確認',
                    en: '${attachments.length} files ready. Select Send to confirm.',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: secondaryColor),
                ),
              ),
              Tooltip(
                message: _text(
                  context,
                  zhCN: '清空待发送文件',
                  zhTW: '清空待傳送檔案',
                  en: 'Clear files',
                ),
                child: IconButton(
                  key: const Key('clear_desktop_pending_attachments'),
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  color: secondaryColor,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints.tightFor(width: 30, height: 30),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _PendingAttachmentTile(
                key: ValueKey('desktop_pending_attachment_$index'),
                attachment: attachments[index],
                onRemove: () => onRemove(index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentTile extends StatelessWidget {
  final DesktopDropAttachment attachment;
  final VoidCallback onRemove;

  const _PendingAttachmentTile({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24262B) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E5EA),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Row(
            children: [
              _AttachmentThumbnail(attachment: attachment),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 9, 26, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        attachment.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatDesktopDropAttachmentSize(attachment.size),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 3,
            right: 3,
            child: Tooltip(
              message: AppLocalizations.of(context).language == AppLanguage.en
                  ? 'Remove'
                  : '移除',
              child: InkResponse(
                key:
                    Key('remove_desktop_pending_attachment_${attachment.path}'),
                onTap: onRemove,
                radius: 14,
                child: Container(
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black54 : const Color(0xFFF1F3F5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  final DesktopDropAttachment attachment;

  const _AttachmentThumbnail({required this.attachment});

  @override
  Widget build(BuildContext context) {
    if (attachment.type == DesktopDropAttachmentType.image) {
      return Image.file(
        File(attachment.path),
        width: 68,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context, Icons.image_outlined),
      );
    }
    return _fallback(
      context,
      attachment.type == DesktopDropAttachmentType.video
          ? Icons.play_circle_outline_rounded
          : Icons.insert_drive_file_outlined,
    );
  }

  Widget _fallback(BuildContext context, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 68,
      height: 80,
      color: isDark ? const Color(0xFF30343B) : const Color(0xFFF1F4F8),
      alignment: Alignment.center,
      child: Icon(icon, size: 29, color: AppColors.primaryFor(context)),
    );
  }
}
