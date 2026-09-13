// 文件用途：提供 VipBadge 可复用界面组件，服务于会员权益。
// 核心逻辑：根据输入模型和状态渲染 VipBadge，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';

// 关键声明：VIP badge 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class VipBadge extends StatelessWidget {
  const VipBadge({
    super.key,
    required this.level,
    required this.text,
    this.iconUrl = '',
    this.height = 20,
    this.compact = false,
  });

  final int level;
  final String text;
  final String iconUrl;
  final double height;
  final bool compact;

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _VipBadgeIcon extends StatelessWidget {
  const _VipBadgeIcon({
    required this.iconUrl,
    required this.fallbackIcon,
    required this.color,
    required this.size,
  });

  final String iconUrl;
  final IconData fallbackIcon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Icon(
      fallbackIcon,
      size: size,
      color: color,
    );
  }
}

class _DefaultVipBadgeImage extends StatelessWidget {
  const _DefaultVipBadgeImage({
    required this.assetPath,
    required this.fallbackIcon,
    required this.color,
    required this.height,
  });

  final String assetPath;
  final IconData fallbackIcon;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageWidth = height * 2.95;
    return Image.asset(
      assetPath,
      width: imageWidth,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        fallbackIcon,
        size: height * 0.72,
        color: color,
      ),
    );
  }
}

class VipProfileBadge extends StatelessWidget {
  const VipProfileBadge({
    super.key,
    required this.level,
    this.height = 22,
  });

  final int level;
  final double height;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
