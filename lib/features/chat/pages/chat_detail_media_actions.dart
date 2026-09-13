// 文件用途：实现 _ChatDetailMediaActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMediaActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaActions on _ChatDetailPageState {
  // 流程逻辑：`_handleDroppedFiles` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (!_ensureCanSendMedia() || files.isEmpty) return;
    final settings =
        await ref.read(systemSettingsServiceProvider).getSettings();
    if (!mounted) return;
    final pending = <DesktopDropAttachment>[];
    var unreadableCount = 0;
    var disabledFileCount = 0;

    for (final xfile in files) {
      final path = xfile.path.trim();
      final fileName = xfile.name.trim();
      final extension = DesktopDropAttachment.extensionFromName(fileName);
      final type = DesktopDropAttachment.typeFromExtension(extension);
      if (path.isEmpty || fileName.isEmpty) {
        unreadableCount++;
        continue;
      }

      final file = File(path);
      if (!await file.exists()) {
        unreadableCount++;
        continue;
      }

      if (type == DesktopDropAttachmentType.file &&
          !settings.fileUploadEnabled) {
        disabledFileCount++;
        continue;
      }

      final size = await file.length();
      final maxSize = switch (type) {
        DesktopDropAttachmentType.image => settings.maxImageSize * 1024 * 1024,
        DesktopDropAttachmentType.video => settings.maxVideoSize * 1024 * 1024,
        DesktopDropAttachmentType.file => settings.maxFileSize * 1024 * 1024,
      };
      if (size > maxSize) {
        if (mounted) {
          this._showFileSizeExceededDialog(
            size,
            maxSize,
            switch (type) {
              DesktopDropAttachmentType.image =>
                _localizedText(zhCN: '图片', zhTW: '圖片', en: 'Image'),
              DesktopDropAttachmentType.video =>
                _localizedText(zhCN: '视频', zhTW: '影片', en: 'Video'),
              DesktopDropAttachmentType.file =>
                _localizedText(zhCN: '文件', zhTW: '檔案', en: 'File'),
            },
          );
        }
        continue;
      }

      int? width;
      int? height;
      if (type == DesktopDropAttachmentType.image) {
        try {
          final decodedImage =
              await decodeImageFromList(await file.readAsBytes());
          width = decodedImage.width;
          height = decodedImage.height;
          decodedImage.dispose();
        } catch (error) {
          debugPrint('[DesktopDrop] Image decode failed for $path: $error');
          unreadableCount++;
          continue;
        }
      }

      pending.add(
        DesktopDropAttachment(
          path: path,
          name: fileName,
          extension: extension,
          size: size,
          type: type,
          width: width,
          height: height,
        ),
      );
    }

    if (pending.isNotEmpty && mounted) {
      _updateState(() {
        _showAttachmentPickerState = false;
        _pendingDesktopAttachments.addAll(pending);
      });
      _inputFocusNode.requestFocus();
    }
    if (unreadableCount > 0 && mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '有 $unreadableCount 个文件无法读取，已跳过',
          zhTW: '有 $unreadableCount 個檔案無法讀取，已略過',
          en: '$unreadableCount files could not be read and were skipped.',
        ),
      );
    }
    if (disabledFileCount > 0 && mounted) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '管理员已关闭普通文件上传，已跳过 $disabledFileCount 个文件',
          zhTW: '管理員已關閉一般檔案上傳，已略過 $disabledFileCount 個檔案',
          en: 'File uploads are disabled. $disabledFileCount files were skipped.',
        ),
      );
    }
  }

  Future<void> _sendPendingDesktopAttachments({
    String? text,
    bool refocusInput = true,
  }) async {
    if (_pendingDesktopAttachments.isEmpty || !_ensureCanSendMedia()) return;
    final attachments =
        List<DesktopDropAttachment>.from(_pendingDesktopAttachments);
    final caption = text?.trim();
    final captionImageIndex = caption == null || caption.isEmpty
        ? -1
        : attachments.indexWhere(
            (item) => item.type == DesktopDropAttachmentType.image,
          );

    _updateState(() => _pendingDesktopAttachments.clear());
    _stopTyping();

    List<String>? captionMentions;
    if (captionImageIndex >= 0) {
      captionMentions = _pendingMentionIds.isNotEmpty
          ? List<String>.from(_pendingMentionIds)
          : null;
      _pendingMentionIds.clear();
      _updateState(() {
        _mentionQuery = null;
        _atSignIndex = -1;
      });
      _inputController.clear();
      ref.read(chatListProvider.notifier).updateDraft(widget.chatId, '');
    } else if (caption != null && caption.isNotEmpty) {
      this._sendMessage(caption, refocusInput: false);
    } else {
      _inputController.clear();
      ref.read(chatListProvider.notifier).updateDraft(widget.chatId, '');
    }

    final notifier = ref.read(messageListProvider(widget.chatId).notifier);
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      switch (attachment.type) {
        case DesktopDropAttachmentType.image:
          final sent = await notifier.sendImageMessage(
            attachment.path,
            width: attachment.width,
            height: attachment.height,
            caption: index == captionImageIndex ? caption : null,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
            mentions: index == captionImageIndex ? captionMentions : null,
          );
          if (sent) {
            this._updateChatListPreview(
              _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]'),
              type: MessageContentType.photo,
              mediaUrl: attachment.path,
            );
          }
        case DesktopDropAttachmentType.video:
          await notifier.sendVideoMessage(
            attachment.path,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          );
          this._updateChatListPreview(
            _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
            type: MessageContentType.video,
          );
        case DesktopDropAttachmentType.file:
          await notifier.sendFileMessage(
            attachment.path,
            attachment.name,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
            onError: (message) {
              if (mounted) AppSnackBar.warning(context, message);
            },
          );
          this._updateChatListPreview(
            '${_localizedText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]')} ${attachment.name}',
            type: MessageContentType.file,
          );
      }
    }

    this._scrollToBottom();
    GlobalHaptics.light();
    if (refocusInput && mounted) {
      _inputFocusNode.requestFocus();
    }
  }

  void _showAttachmentOptions() {
    FocusManager.instance.primaryFocus?.unfocus();
    _updateState(() {
      if (_showEmojiPickerState) {
        _showEmojiPickerState = false;
      }
      _showAttachmentPickerState = !_showAttachmentPickerState;
    });
  }

  void _hideAttachmentPicker() {
    if (!_showAttachmentPickerState) return;
    _updateState(() => _showAttachmentPickerState = false);
  }

  Widget _buildInlineAttachmentOptions() {
    final isPrivateChat = widget.chatType == ChatType.private;
    final isGroupChat = widget.chatType == ChatType.group;
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final configuredMenu =
        settings?.chatAttachmentMenu ?? const ChatAttachmentMenuSettings();
    final walletEnabled = settings?.walletEnabled ?? true;
    final menuSettings = walletEnabled
        ? configuredMenu
        : ChatAttachmentMenuSettings(
            enabled: configuredMenu.enabled,
            album: configuredMenu.album,
            camera: configuredMenu.camera,
            call: configuredMenu.call,
            location: configuredMenu.location,
            redPacket: false,
            transfer: false,
            favorite: configuredMenu.favorite,
            file: configuredMenu.file,
          );

    return _AttachmentSheet(
      onPickFromGallery: this._pickFromGallery,
      onTakePhoto: this._takePhotoOrVideo,
      onStartCall: isPrivateChat ? this._showCallTypeOptions : null,
      onStartMeeting: isGroupChat ? this._showMeetingStartOptionsCompact : null,
      onSendLocation: this._sendCurrentLocation,
      onOpenFavorites: this._openFavoriteMessages,
      onPickFile: this._pickFile,
      onSendRedPacket:
          (isPrivateChat || isGroupChat) ? this._sendRedPacket : null,
      onTransfer: isPrivateChat ? this._transfer : null,
      onBurnAfterReadToggle: this._toggleBurnAfterRead,
      onDismiss: this._hideAttachmentPicker,
      menuSettings: menuSettings,
      burnAfterReadEnabled: _burnAfterReadEnabled,
      allowBurnAfterRead: _isBurnAfterReadAllowed,
    );
  }

  void _showCallTypeOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final l10n = AppLocalizations.of(sheetContext);
        final actionColor =
            isDark ? AppColors.callMeetingIconDark : AppColors.callMeetingIcon;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.videocam_rounded, color: actionColor),
                  title: Text(l10n.videoCall),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    this._startCall(CallType.video);
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFEDEDED),
                ),
                ListTile(
                  leading: Icon(Icons.call_rounded, color: actionColor),
                  title: Text(l10n.voiceCall),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    this._startCall(CallType.voice);
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFEDEDED),
                ),
                ListTile(
                  title: Center(child: Text(l10n.cancel)),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleBurnAfterRead() {
    if (!_isBurnAfterReadAllowed) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '后台已关闭阅后即焚',
          zhTW: '後台已關閉閱後即焚',
          en: 'Burn-after-read has been disabled in admin settings',
        ),
      );
      return;
    }
    _updateState(() => _burnAfterReadEnabled = !_burnAfterReadEnabled);
    AppSnackBar.info(
      context,
      _burnAfterReadEnabled
          ? _localizedText(
              zhCN: '已开启阅后即焚',
              zhTW: '已開啟閱後即焚',
              en: 'Burn-after-read enabled',
            )
          : _localizedText(
              zhCN: '已关闭阅后即焚',
              zhTW: '已關閉閱後即焚',
              en: 'Burn-after-read disabled',
            ),
    );
  }

  void _toggleAnonymousSend() {
    if (!_anonymousSendAllowed) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '本群未开放匿名发言',
          zhTW: '本群未開放匿名發言',
          en: 'Anonymous messages are disabled in this group',
        ),
      );
      return;
    }
    _updateState(() => _anonymousSendEnabled = !_anonymousSendEnabled);
    AppSnackBar.info(
      context,
      _anonymousSendEnabled
          ? _localizedText(
              zhCN: '匿名发言已开启',
              zhTW: '匿名發言已開啟',
              en: 'Anonymous messages enabled',
            )
          : _localizedText(
              zhCN: '匿名发言已关闭',
              zhTW: '匿名發言已關閉',
              en: 'Anonymous messages disabled',
            ),
    );
  }

  void _toggleEmojiPicker() {
    _updateState(() {
      if (!_showEmojiPickerState) {
        _showAttachmentPickerState = false;
      }
      _showEmojiPickerState = !_showEmojiPickerState;
    });
  }
}
