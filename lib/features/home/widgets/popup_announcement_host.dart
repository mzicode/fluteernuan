import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../services/popup_announcement_service.dart';

String _popupText(BuildContext context) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return 'OK';
    case AppLanguage.zhTW:
      return '我知道了';
    case AppLanguage.zhCN:
      return '我知道了';
  }
}

final popupAnnouncementServiceProvider = Provider<PopupAnnouncementService>((ref) {
  return PopupAnnouncementService(ref.watch(apiClientProvider));
});

/// 登录后首页可用时拉取启动公告。图片解码且弹窗可见后才 ACK。
class PopupAnnouncementHost extends ConsumerStatefulWidget {
  final Widget child;

  const PopupAnnouncementHost({super.key, required this.child});

  @override
  ConsumerState<PopupAnnouncementHost> createState() =>
      _PopupAnnouncementHostState();
}

class _PopupAnnouncementHostState extends ConsumerState<PopupAnnouncementHost> {
  bool _running = false;
  bool _retryAfterConflict = false;
  int _conflictRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _presentIfNeeded());
  }

  Future<void> _presentIfNeeded() async {
    if (!mounted || _running) return;
    final auth = ref.read(authServiceProvider);
    final userId = auth.user?.id.trim() ?? '';
    if (auth.status != AuthStatus.authenticated || userId.isEmpty) return;
    if (PopupAnnouncementSession.completedUserIds.contains(userId)) return;

    _running = true;
    try {
      final service = ref.read(popupAnnouncementServiceProvider);
      final fetch = await service.fetch();
      if (!mounted || fetch == null) return;
      PopupAnnouncementSession.completedUserIds.add(userId);
      final announcement = fetch.announcement;
      if (!fetch.eligible || announcement == null) return;

      PopupAnnouncementImage? image;
      var imageReady = !announcement.hasImage;
      if (announcement.hasImage) {
        image = await service.loadImage(announcement.imageUrl);
        imageReady = image != null;
      }
      if (!mounted) return;
      if (!announcement.hasContent && !imageReady) return;

      final allowAck = imageReady;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _PopupAnnouncementDialog(
            image: image,
            onVisible: allowAck
                ? () => _acknowledge(service, announcement.displayToken)
                : null,
          );
        },
      );
    } finally {
      _running = false;
    }
    if (mounted && _retryAfterConflict && _conflictRetries < 1) {
      _retryAfterConflict = false;
      _conflictRetries++;
      await _presentIfNeeded();
    }
  }

  Future<void> _acknowledge(
    PopupAnnouncementService service,
    String displayToken,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await service.acknowledge(displayToken);
      if (result.acknowledged) return;
      if (result.httpStatus == 409) {
        final userId = ref.read(authServiceProvider).user?.id.trim() ?? '';
        if (userId.isNotEmpty) {
          PopupAnnouncementSession.completedUserIds.remove(userId);
        }
        _retryAfterConflict = true;
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        return;
      }
      if (!result.retryLater) return;
      await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authServiceProvider, (previous, next) {
      final previousId = previous?.user?.id;
      final nextId = next.user?.id;
      if (next.status == AuthStatus.authenticated &&
          nextId != null &&
          nextId.isNotEmpty &&
          nextId != previousId) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _presentIfNeeded());
      }
    });
    return widget.child;
  }
}

class _PopupAnnouncementDialog extends StatefulWidget {
  final PopupAnnouncementImage? image;
  final VoidCallback? onVisible;

  const _PopupAnnouncementDialog({
    required this.image,
    required this.onVisible,
  });

  @override
  State<_PopupAnnouncementDialog> createState() =>
      _PopupAnnouncementDialogState();
}

class _PopupAnnouncementDialogState extends State<_PopupAnnouncementDialog> {
  static const _countdownSeconds = 5;

  var _reported = false;
  var _secondsLeft = _countdownSeconds;
  Timer? _timer;

  bool get _canClose => _secondsLeft <= 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reported) return;
      _reported = true;
      widget.onVisible?.call();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final screen = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    const sideInset = 12.0;
    final dialogWidth = screen.width - sideInset * 2;
    final topInset = math.max(12.0, viewPadding.top);
    final bottomInset = math.max(12.0, viewPadding.bottom + 8);
    final maxCardHeight = screen.height - topInset - bottomInset;
    const buttonBlock = 88.0;
    final imageHeight = image == null
        ? null
        : math.min(
            dialogWidth / _AnnouncementImage.aspectRatio,
            math.max(120.0, maxCardHeight - buttonBlock),
          );

    return PopScope(
      canPop: _canClose,
      child: Dialog(
        insetPadding: EdgeInsets.fromLTRB(sideInset, topInset, sideInset, bottomInset),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: maxCardHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: dialogWidth,
                height: imageHeight ?? 168,
                child: Stack(
                  children: [
                    if (image != null)
                      _AnnouncementImage(
                        image: image,
                        height: imageHeight!,
                      ),
                    if (!_canClose)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _CountdownBadge(seconds: _secondsLeft),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    disabledBackgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.38),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
                  ),
                  onPressed: _canClose ? () => Navigator.of(context).pop() : null,
                  child: Text(
                    _popupText(context),
                    style: const TextStyle(fontSize: 16, height: 1.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;

  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '${seconds}s',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AnnouncementImage extends StatelessWidget {
  /// 公告图固定比例：高:宽 = 4:3。宽度铺满弹窗。
  static const double aspectRatio = 3 / 4;

  final PopupAnnouncementImage image;
  final double height;

  const _AnnouncementImage({
    required this.image,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4F4F5),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Image.memory(
          image.bytes,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}
