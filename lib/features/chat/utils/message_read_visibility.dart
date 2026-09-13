// 文件用途：定义消息真正曝光后才允许上报已读的可见性规则。
// 核心逻辑：普通消息至少显示一半；超长消息显示 48px 即视为用户已看到。

const double messageReadMinVisibleFraction = 0.5;
const double messageReadMinVisiblePixels = 48;

bool shouldMarkMessageAsExposed({
  required bool isIncoming,
  required int sequence,
  required bool appIsResumed,
  required double visibleFraction,
  required double itemHeight,
}) {
  if (!isIncoming || sequence <= 0 || !appIsResumed || itemHeight <= 0) {
    return false;
  }

  final normalizedFraction = visibleFraction.clamp(0.0, 1.0).toDouble();
  final halfHeight = itemHeight * messageReadMinVisibleFraction;
  final requiredVisibleHeight = halfHeight < messageReadMinVisiblePixels
      ? halfHeight
      : messageReadMinVisiblePixels;

  return normalizedFraction * itemHeight >= requiredVisibleHeight;
}
