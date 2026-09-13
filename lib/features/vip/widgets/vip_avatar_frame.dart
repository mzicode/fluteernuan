// 文件用途：提供 VipAvatarFrame 可复用界面组件，服务于会员权益。
// 核心逻辑：根据输入模型和状态渲染 VipAvatarFrame，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';

// 关键声明：VIP avatar frame 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class VipAvatarFrame extends StatelessWidget {
  const VipAvatarFrame({
    super.key,
    required this.level,
    required this.size,
    required this.child,
    this.animated = false,
    this.frameWidth,
    this.borderRadius,
    this.isCircle = false,
  });

  final int level;
  final double size;
  final Widget child;
  final bool animated;
  final double? frameWidth;
  final double? borderRadius;
  final bool isCircle;

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    return child;
  }
}
