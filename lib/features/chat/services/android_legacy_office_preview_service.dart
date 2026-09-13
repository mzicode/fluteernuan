// 文件用途：封装 Android 旧版 Office 文件的原生解析结果。
// 核心逻辑：把平台通道返回的受限文本、表格和幻灯片转换为统一预览模型。
import 'package:flutter/services.dart';

import 'document_preview_service.dart';

class AndroidLegacyOfficePreviewException implements Exception {
  final String code;

  const AndroidLegacyOfficePreviewException(this.code);

  @override
  String toString() => 'AndroidLegacyOfficePreviewException($code)';
}

class AndroidLegacyOfficePreviewService {
  static const MethodChannel _channel =
      MethodChannel('com.customer/legacy_office_preview');

  static Future<DocumentPreviewData> load({
    required String path,
    required String fileName,
  }) async {
    final extension = DocumentPreviewService.extensionOf(fileName);
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'extract',
        <String, dynamic>{'path': path, 'extension': extension},
      );
      if (response?['available'] != true) {
        throw AndroidLegacyOfficePreviewException(
          response?['reason']?.toString() ?? 'preview_unavailable',
        );
      }
      final truncated = response?['truncated'] == true;
      switch (response?['kind']?.toString()) {
        case 'doc':
          return DocumentPreviewData(
            kind: DocumentPreviewKind.docx,
            text: response?['text']?.toString() ?? '',
            truncated: truncated,
          );
        case 'xls':
          return DocumentPreviewData(
            kind: DocumentPreviewKind.xlsx,
            sections: _sections(response?['sections']),
            truncated: truncated,
          );
        case 'ppt':
          return DocumentPreviewData(
            kind: DocumentPreviewKind.pptx,
            sections: _sections(response?['sections']),
            truncated: truncated,
          );
        default:
          throw const AndroidLegacyOfficePreviewException('invalid_response');
      }
    } on PlatformException catch (error) {
      throw AndroidLegacyOfficePreviewException(
        error.code.isEmpty ? 'platform_error' : error.code,
      );
    } on MissingPluginException {
      throw const AndroidLegacyOfficePreviewException('not_supported');
    }
  }

  static List<DocumentPreviewSection> _sections(Object? raw) {
    if (raw is! List) return const <DocumentPreviewSection>[];
    return raw.whereType<Map>().map((section) {
      final rows = section['rows'];
      return DocumentPreviewSection(
        title: section['title']?.toString() ?? '',
        text: section['text']?.toString() ?? '',
        rows: rows is List
            ? rows
                .whereType<List>()
                .map((row) => row.map((cell) => cell.toString()).toList())
                .toList()
            : const <List<String>>[],
      );
    }).toList();
  }
}
