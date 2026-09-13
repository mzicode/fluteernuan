// 文件用途：封装 Android 系统 PdfRenderer 的页面信息与逐页渲染能力。
// 核心逻辑：通过平台通道请求原生侧渲染应用私有目录中的 PDF，并把失败转换为稳定错误码。
import 'package:flutter/services.dart';

class AndroidPdfInfo {
  final int pageCount;

  const AndroidPdfInfo({required this.pageCount});
}

class AndroidPdfPage {
  final String imagePath;
  final int width;
  final int height;

  const AndroidPdfPage({
    required this.imagePath,
    required this.width,
    required this.height,
  });
}

class AndroidPdfPreviewException implements Exception {
  final String code;

  const AndroidPdfPreviewException(this.code);

  @override
  String toString() => 'AndroidPdfPreviewException($code)';
}

class AndroidPdfPreviewService {
  static const MethodChannel _channel = MethodChannel('com.customer/pdf_preview');

  static Future<AndroidPdfInfo> getInfo(String path) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'getInfo',
        <String, dynamic>{'path': path},
      );
      if (response?['available'] != true) {
        throw AndroidPdfPreviewException(
          response?['reason']?.toString() ?? 'preview_unavailable',
        );
      }
      final pageCount = (response?['page_count'] as num?)?.toInt() ?? 0;
      if (pageCount <= 0) {
        throw const AndroidPdfPreviewException('empty_document');
      }
      return AndroidPdfInfo(pageCount: pageCount);
    } on PlatformException catch (error) {
      throw AndroidPdfPreviewException(
        error.code.isEmpty ? 'platform_error' : error.code,
      );
    } on MissingPluginException {
      throw const AndroidPdfPreviewException('not_supported');
    }
  }

  static Future<AndroidPdfPage> renderPage({
    required String path,
    required int pageIndex,
    required int targetWidth,
  }) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'renderPage',
        <String, dynamic>{
          'path': path,
          'page_index': pageIndex,
          'target_width': targetWidth,
        },
      );
      if (response?['rendered'] != true) {
        throw AndroidPdfPreviewException(
          response?['reason']?.toString() ?? 'render_failed',
        );
      }
      final imagePath = response?['image_path']?.toString() ?? '';
      final width = (response?['width'] as num?)?.toInt() ?? 0;
      final height = (response?['height'] as num?)?.toInt() ?? 0;
      if (imagePath.isEmpty || width <= 0 || height <= 0) {
        throw const AndroidPdfPreviewException('invalid_response');
      }
      return AndroidPdfPage(
        imagePath: imagePath,
        width: width,
        height: height,
      );
    } on PlatformException catch (error) {
      throw AndroidPdfPreviewException(
        error.code.isEmpty ? 'platform_error' : error.code,
      );
    } on MissingPluginException {
      throw const AndroidPdfPreviewException('not_supported');
    }
  }
}
