// 文件用途：提供 _MessageBubbleMedia 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleMedia，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

String? _privateMediaCacheKey(MessageItem item) {
  final thumbnailMediaId = item.thumbnailMediaId?.trim() ?? '';
  if (thumbnailMediaId.isNotEmpty) return 'media:$thumbnailMediaId';
  final mediaId = item.mediaId?.trim() ?? '';
  return mediaId.isEmpty ? null : 'media:$mediaId';
}

String? _privateMediaId(MessageItem item) {
  final thumbnailMediaId = item.thumbnailMediaId?.trim() ?? '';
  if (thumbnailMediaId.isNotEmpty) return thumbnailMediaId;
  final mediaId = item.mediaId?.trim() ?? '';
  return mediaId.isEmpty ? null : mediaId;
}

class _RetryableChatNetworkImage extends ConsumerStatefulWidget {
  const _RetryableChatNetworkImage({
    required this.chatId,
    required this.fit,
    this.imageUrl,
    this.cacheKey,
    this.mediaId,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache = 800,
    this.maxHeightDiskCache = 800,
    this.enableTapRetry = true,
  });

  final String chatId;
  final String? imageUrl;
  final String? cacheKey;
  final String? mediaId;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int maxWidthDiskCache;
  final int maxHeightDiskCache;
  final bool enableTapRetry;

  @override
  ConsumerState<_RetryableChatNetworkImage> createState() =>
      _RetryableChatNetworkImageState();
}

class _RetryableChatNetworkImageState
    extends ConsumerState<_RetryableChatNetworkImage> {
  static const _maxAutoRetries = 2;
  int _autoRetries = 0;
  bool _retrying = false;
  int _loadGeneration = 0;

  bool get _hasImageUrl {
    final url = widget.imageUrl?.trim() ?? '';
    return url.isNotEmpty;
  }

  bool get _hasMediaId {
    final mediaId = widget.mediaId?.trim() ?? '';
    return mediaId.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (!_hasImageUrl && _hasMediaId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_retry(auto: true));
      });
    }
  }

  @override
  void didUpdateWidget(_RetryableChatNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged = oldWidget.imageUrl != widget.imageUrl;
    if (urlChanged) {
      _retrying = false;
    }
    if (!_hasImageUrl && _hasMediaId && !_retrying && urlChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_retry(auto: true));
      });
    }
  }

  Future<void> _retry({required bool auto}) async {
    if (_retrying) return;
    if (auto && _autoRetries >= _maxAutoRetries) return;
    _retrying = true;
    if (auto) _autoRetries += 1;
    if (mounted) setState(() {});
    try {
      await ChatMediaCacheManager.evictImage(
        cacheKey: widget.cacheKey,
        url: widget.imageUrl,
      );
      if (!mounted) return;
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .refreshPrivateMediaAccess(forceRefresh: true);
    } catch (error) {
      debugPrint('[MessageImage] retry refresh failed: $error');
    } finally {
      _retrying = false;
      if (mounted) {
        setState(() {
          _loadGeneration += 1;
        });
        if (!_hasImageUrl &&
            _hasMediaId &&
            _autoRetries < _maxAutoRetries) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_retry(auto: true));
          });
        }
      }
    }
  }

  Widget _placeholder({bool showSpinner = true}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: showSpinner
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.image, size: 40, color: Colors.grey[400]),
      ),
    );
  }

  Widget _retryPlaceholder() {
    final label = _localizedUiText(
      context,
      zhCN: '点击重试',
      zhTW: '點擊重試',
      en: 'Tap to retry',
    );
    final content = Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: _retrying
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 28, color: Colors.grey[500]),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
      ),
    );
    if (!widget.enableTapRetry) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _retrying ? null : () => unawaited(_retry(auto: false)),
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasImageUrl) {
      if (_hasMediaId && (_retrying || _autoRetries < _maxAutoRetries)) {
        return _placeholder();
      }
      if (_hasMediaId) return _retryPlaceholder();
      return _placeholder(showSpinner: false);
    }

    final imageUrl = ChatMediaCacheManager.normalizeUrl(widget.imageUrl);
    final maxWidth = widget.memCacheWidth ?? 280;
    final maxHeight = widget.memCacheHeight ?? 280;

    return CachedNetworkImage(
      key: ValueKey<String>('chat-img:$_loadGeneration:$imageUrl'),
      imageUrl: imageUrl,
      cacheKey: widget.cacheKey,
      cacheManager: ChatMediaCacheManager.instance,
      fit: widget.fit,
      memCacheWidth: maxWidth,
      memCacheHeight: maxHeight,
      maxWidthDiskCache: widget.maxWidthDiskCache,
      maxHeightDiskCache: widget.maxHeightDiskCache,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => _placeholder(),
      errorWidget: (context, url, error) {
        debugPrint('[MessageImage] cached image failed: $url error=$error');
        if (!_retrying && _autoRetries < _maxAutoRetries) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_retry(auto: true));
          });
          return _placeholder();
        }
        return _retryPlaceholder();
      },
    );
  }
}

// 关键声明：message bubble media 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleMedia on MessageBubble {
  // 流程逻辑：`_buildSizedMedia` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  /// 根据已知的 mediaWidth/mediaHeight 预计算显示尺寸，避免图片加载后闪烁
  Widget _buildSizedMedia(double maxW, double maxH) {
    final mw = message.mediaWidth;
    final mh = message.mediaHeight;

    if (mw != null && mh != null && mw > 0 && mh > 0) {
      double w = mw.toDouble();
      double h = mh.toDouble();

      // 始终使用统一缩放因子，保证外层缩略图容器与图片真实比例一致。
      final shrinkScale = math.min(maxW / w, maxH / h);
      if (shrinkScale < 1) {
        w *= shrinkScale;
        h *= shrinkScale;
      }

      // 仅在图片整体都太小时才按比例整体放大，避免比例失真。
      if (w < 100 && h < 80) {
        final growScale = math.min(maxW / w, maxH / h);
        final desiredScale = math.max(100 / w, 80 / h);
        final finalScale = math.min(growScale, desiredScale);
        if (finalScale > 1) {
          w *= finalScale;
          h *= finalScale;
        }
      }

      return SizedBox(width: w, height: h, child: _buildMediaImage());
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: maxH,
        minWidth: 100,
        minHeight: 80,
      ),
      child: _buildMediaImage(),
    );
  }

  /// 构建媒体图片（处理本地文件和网络URL）
  Widget _buildMediaImage() {
    final localPath = message.localPath;
    final remoteMediaUrl = message.mediaUrl?.trim();
    final isRemoteGif = remoteMediaUrl != null &&
        remoteMediaUrl.isNotEmpty &&
        AnimatedGifImage.isGifSource(
          ChatMediaCacheManager.normalizeUrl(remoteMediaUrl),
        );
    final thumbnailUrl = message.thumbnail?.trim();
    final remoteDisplayUrl =
        !isRemoteGif && thumbnailUrl != null && thumbnailUrl.isNotEmpty
            ? thumbnailUrl
            : remoteMediaUrl;
    final rawUrl = ChatMediaCacheManager.isLocalPath(localPath) &&
            File(localPath!).existsSync()
        ? localPath
        : remoteDisplayUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      return _RetryableChatNetworkImage(
        chatId: message.chatId,
        imageUrl: null,
        cacheKey: _privateMediaCacheKey(message),
        mediaId: _privateMediaId(message),
        fit: BoxFit.fill,
      );
    }

    final isSticker = message.type == MessageItemType.sticker;
    final url = isSticker
        ? EmojiStoreService.resolveStickerDisplayPath(rawUrl)
        : ChatMediaCacheManager.normalizeUrl(rawUrl);
    final isGif = AnimatedGifImage.isGifSource(url);
    final imageFit = isSticker || isGif ? BoxFit.contain : BoxFit.fill;

    if (isSticker) {
      return StickerImage(
        source: url,
        fit: imageFit,
        errorBuilder: (context, nativeError) {
          debugPrint(
            '[MessageImage] sticker image failed: $url error=$nativeError',
          );
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image,
              size: 40,
              color: Colors.grey[400],
            ),
          );
        },
      );
    }

    if (ChatMediaCacheManager.isLocalPath(url)) {
      if (isGif) {
        return AnimatedGifImage(source: url, fit: imageFit);
      }

      final file = File(url);
      return Image.file(
        file,
        fit: imageFit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
          );
        },
      );
    }

    final imageUrl = url;

    if (isGif) {
      return AnimatedGifImage(
        source: imageUrl,
        fit: imageFit,
        errorBuilder: (context, nativeError) {
          debugPrint(
            '[MessageImage] gif image failed: $imageUrl error=$nativeError',
          );
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image,
              size: 40,
              color: Colors.grey[400],
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? (constraints.maxWidth * 2).round().clamp(200, 560)
                : 280;
        final maxHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? (constraints.maxHeight * 2).round().clamp(200, 560)
                : 280;

        return _RetryableChatNetworkImage(
          chatId: message.chatId,
          imageUrl: imageUrl,
          cacheKey: _privateMediaCacheKey(message),
          mediaId: _privateMediaId(message),
          fit: imageFit,
          memCacheWidth: maxWidth,
          memCacheHeight: maxHeight,
        );
      },
    );
  }
}
