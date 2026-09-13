// 文件用途：为页面空状态提供随机的小恐龙 Lottie 动画。
// 核心逻辑：组件创建时从内置恐龙贴纸中随机选择一个，并在本次生命周期内保持不变。
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class RandomDinosaurLottie extends StatefulWidget {
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? variant;

  const RandomDinosaurLottie({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.variant,
  }) : assert(
          variant == null || (variant >= 1 && variant <= 30),
          'variant must be between 1 and 30',
        );

  static String assetPathForVariant(int variant) {
    if (variant < 1 || variant > 30) {
      throw RangeError.range(variant, 1, 30, 'variant');
    }
    return 'assets/stickers/cubigator/'
        'cubigator_${variant.toString().padLeft(2, '0')}.json';
  }

  @override
  State<RandomDinosaurLottie> createState() => _RandomDinosaurLottieState();
}

class _RandomDinosaurLottieState extends State<RandomDinosaurLottie> {
  static const int _dinosaurCount = 30;
  late final int _dinosaurNumber;
  late final String _assetPath;

  @override
  void initState() {
    super.initState();
    _dinosaurNumber = widget.variant ?? Random().nextInt(_dinosaurCount) + 1;
    _assetPath = RandomDinosaurLottie.assetPathForVariant(_dinosaurNumber);
  }

  @override
  Widget build(BuildContext context) {
    // Cubigator 必须在 Android、iOS、Windows、macOS 和 H5 使用同一份
    // Lottie 资源。这里不能经过 WebSafeLottie，否则 H5 会降级成文本符号。
    return Semantics(
      label: 'Dinosaur animation',
      image: true,
      child: Lottie.asset(
        _assetPath,
        key: ValueKey(
          'dinosaur_lottie_${_dinosaurNumber.toString().padLeft(2, '0')}',
        ),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        repeat: true,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(child: Icon(Icons.pets_rounded, size: 48)),
        ),
      ),
    );
  }
}
