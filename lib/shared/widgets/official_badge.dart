// 文件用途：提供 OfficialBadge 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 OfficialBadge，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';

// 关键声明：official badge 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 官方认证文字标签。
class OfficialBadge extends StatelessWidget {
  final double size;

  const OfficialBadge({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return _OfficialLabelBadge(height: size);
  }
}

/// 静态版本，用于列表等性能敏感场景。
class OfficialBadgeStatic extends StatelessWidget {
  final double size;

  const OfficialBadgeStatic({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return _OfficialLabelBadge(height: size);
  }
}

class _OfficialLabelBadge extends StatelessWidget {
  final double height;

  const _OfficialLabelBadge({required this.height});

  @override
  Widget build(BuildContext context) {
    final labelHeight = height.clamp(16.0, 24.0);
    final fontSize = (labelHeight * 0.54).clamp(9.0, 12.0);
    return Container(
      height: labelHeight,
      padding: EdgeInsets.symmetric(horizontal: labelHeight * 0.34),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8F0),
        border: Border.all(color: const Color(0xFF25A55A), width: 1),
        borderRadius: BorderRadius.circular(labelHeight * 0.28),
      ),
      child: Text(
        '官方',
        style: TextStyle(
          color: const Color(0xFF198A4A),
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
