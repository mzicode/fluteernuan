// 文件用途：识别并解析聊天文件中的文档、表格、演示文稿与文本内容。
// 核心逻辑：文本按格式安全解码，OOXML 在隔离线程中解包并提取可读内容，避免阻塞聊天界面。
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:universal_io/io.dart';
import 'package:xml/xml.dart';

enum DocumentPreviewKind {
  pdf,
  text,
  markdown,
  csv,
  docx,
  xlsx,
  pptx,
  legacyOffice,
}

class DocumentPreviewSection {
  final String title;
  final String text;
  final List<List<String>> rows;

  const DocumentPreviewSection({
    required this.title,
    this.text = '',
    this.rows = const <List<String>>[],
  });
}

class DocumentPreviewData {
  final DocumentPreviewKind kind;
  final String text;
  final List<DocumentPreviewSection> sections;
  final bool truncated;

  const DocumentPreviewData({
    required this.kind,
    this.text = '',
    this.sections = const <DocumentPreviewSection>[],
    this.truncated = false,
  });
}

class DocumentPreviewException implements Exception {
  final String code;

  const DocumentPreviewException(this.code);

  @override
  String toString() => 'DocumentPreviewException($code)';
}

class DocumentPreviewService {
  static const Set<String> supportedExtensions = <String>{
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'csv',
    'md',
    'rtf',
    'json',
    'xml',
    'html',
    'htm',
  };

  static const Set<String> legacyOfficeExtensions = <String>{
    'doc',
    'xls',
    'ppt',
  };

  static const int _maxTextBytes = 8 * 1024 * 1024;
  static const int _maxOoxmlBytes = 64 * 1024 * 1024;
  static const int _maxOoxmlEntryBytes = 24 * 1024 * 1024;
  static const int _maxOutputCharacters = 2 * 1024 * 1024;
  static const int _maxTableRows = 1000;
  static const int _maxTableColumns = 64;
  static const int _maxSlides = 500;

  static String extensionOf(String fileName) {
    final normalized = fileName.trim();
    final dot = normalized.lastIndexOf('.');
    if (dot < 0 || dot == normalized.length - 1) return '';
    return normalized.substring(dot + 1).toLowerCase();
  }

  static bool supports(String fileName) =>
      supportedExtensions.contains(extensionOf(fileName));

  static bool isLegacyOffice(String fileName) =>
      legacyOfficeExtensions.contains(extensionOf(fileName));

  static Future<DocumentPreviewData> load({
    required String path,
    required String fileName,
  }) async {
    final extension = extensionOf(fileName);
    if (!supportedExtensions.contains(extension)) {
      throw const DocumentPreviewException('unsupported_format');
    }
    if (extension == 'pdf') {
      return const DocumentPreviewData(kind: DocumentPreviewKind.pdf);
    }
    if (legacyOfficeExtensions.contains(extension)) {
      return const DocumentPreviewData(
        kind: DocumentPreviewKind.legacyOffice,
      );
    }

    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) {
        throw const DocumentPreviewException('file_unavailable');
      }
      final length = file.lengthSync();
      final isOoxml =
          extension == 'docx' || extension == 'xlsx' || extension == 'pptx';
      final limit = isOoxml ? _maxOoxmlBytes : _maxTextBytes;
      if (length > limit) {
        throw const DocumentPreviewException('file_too_large');
      }
      return parseBytes(file.readAsBytesSync(), fileName: fileName);
    });
  }

  static DocumentPreviewData parseBytes(
    Uint8List bytes, {
    required String fileName,
  }) {
    final extension = extensionOf(fileName);
    switch (extension) {
      case 'docx':
        return _parseDocx(bytes);
      case 'xlsx':
        return _parseXlsx(bytes);
      case 'pptx':
        return _parsePptx(bytes);
      case 'csv':
        return _parseCsv(bytes);
      case 'md':
        return _textResult(bytes, DocumentPreviewKind.markdown);
      case 'rtf':
        return _rtfResult(bytes);
      case 'json':
        return _jsonResult(bytes);
      case 'xml':
        return _xmlResult(bytes);
      case 'html':
      case 'htm':
        return _htmlResult(bytes);
      case 'txt':
        return _textResult(bytes, DocumentPreviewKind.text);
      case 'doc':
      case 'xls':
      case 'ppt':
        return const DocumentPreviewData(
          kind: DocumentPreviewKind.legacyOffice,
        );
      case 'pdf':
        return const DocumentPreviewData(kind: DocumentPreviewKind.pdf);
      default:
        throw const DocumentPreviewException('unsupported_format');
    }
  }

  static DocumentPreviewData _textResult(
    Uint8List bytes,
    DocumentPreviewKind kind,
  ) {
    final limited = _limitText(_decodeText(bytes));
    return DocumentPreviewData(
      kind: kind,
      text: limited.text,
      truncated: limited.truncated,
    );
  }

  static DocumentPreviewData _jsonResult(Uint8List bytes) {
    final raw = _decodeText(bytes);
    var output = raw;
    try {
      output = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } on FormatException {
      // Keep malformed JSON readable as source instead of failing the preview.
    }
    final limited = _limitText(output);
    return DocumentPreviewData(
      kind: DocumentPreviewKind.text,
      text: limited.text,
      truncated: limited.truncated,
    );
  }

  static DocumentPreviewData _xmlResult(Uint8List bytes) {
    final raw = _decodeText(bytes);
    var output = raw;
    try {
      output = XmlDocument.parse(raw).toXmlString(pretty: true, indent: '  ');
    } on XmlParserException {
      // Keep malformed XML readable as source instead of failing the preview.
    }
    final limited = _limitText(output);
    return DocumentPreviewData(
      kind: DocumentPreviewKind.text,
      text: limited.text,
      truncated: limited.truncated,
    );
  }

  static DocumentPreviewData _htmlResult(Uint8List bytes) {
    final document = html_parser.parse(_decodeText(bytes));
    for (final element in document.querySelectorAll(
      'script,style,noscript,template,svg',
    )) {
      element.remove();
    }
    final title = document.querySelector('title')?.text.trim();
    final body = document.body?.text ?? document.documentElement?.text ?? '';
    final normalized = body
        .replaceAll(RegExp(r'[\t\x0B\f\r ]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    final output =
        title == null || title.isEmpty ? normalized : '$title\n\n$normalized';
    final limited = _limitText(output);
    return DocumentPreviewData(
      kind: DocumentPreviewKind.text,
      text: limited.text,
      truncated: limited.truncated,
    );
  }

  static DocumentPreviewData _rtfResult(Uint8List bytes) {
    final raw = _decodeText(bytes);
    final output = _stripRtf(raw);
    final limited = _limitText(output);
    return DocumentPreviewData(
      kind: DocumentPreviewKind.text,
      text: limited.text,
      truncated: limited.truncated,
    );
  }

  static DocumentPreviewData _parseCsv(Uint8List bytes) {
    final raw = _decodeText(bytes);
    final rows = Csv().decode(raw).take(_maxTableRows).map((row) {
      return row
          .take(_maxTableColumns)
          .map((value) => value?.toString() ?? '')
          .toList(growable: false);
    }).toList(growable: false);
    final totalLines = '\n'.allMatches(raw).length + 1;
    return DocumentPreviewData(
      kind: DocumentPreviewKind.csv,
      sections: <DocumentPreviewSection>[
        DocumentPreviewSection(title: '', rows: rows),
      ],
      truncated: totalLines > _maxTableRows ||
          rows.any((row) => row.length >= _maxTableColumns),
    );
  }

  static DocumentPreviewData _parseDocx(Uint8List bytes) {
    final archive = _decodeOoxml(bytes);
    final document = _readXml(archive, 'word/document.xml');
    final body = _firstElement(document, 'body');
    if (body == null) {
      throw const DocumentPreviewException('invalid_document');
    }

    final output = StringBuffer();
    var truncated = false;
    for (final child in body.children.whereType<XmlElement>()) {
      if (child.name.local == 'p') {
        final text = _paragraphText(child);
        if (text.isEmpty) continue;
        final style = _paragraphStyle(child).toLowerCase();
        final headingMatch = RegExp(r'heading\s*([1-6])').firstMatch(style);
        if (headingMatch != null) {
          final level = int.parse(headingMatch.group(1)!);
          output.writeln('${'#' * level} $text');
        } else {
          output.writeln(text);
        }
        output.writeln();
      } else if (child.name.local == 'tbl') {
        final rows = _wordTableRows(child);
        if (rows.isNotEmpty) {
          output.writeln(_rowsToMarkdown(rows));
          output.writeln();
        }
      }
      if (output.length > _maxOutputCharacters) {
        truncated = true;
        break;
      }
    }
    final limited = _limitText(output.toString().trim());
    return DocumentPreviewData(
      kind: DocumentPreviewKind.docx,
      text: limited.text,
      truncated: truncated || limited.truncated,
    );
  }

  static DocumentPreviewData _parseXlsx(Uint8List bytes) {
    final archive = _decodeOoxml(bytes);
    final workbook = _readXml(archive, 'xl/workbook.xml');
    final relationships = _readXml(
      archive,
      'xl/_rels/workbook.xml.rels',
    );
    final relationshipTargets = <String, String>{};
    for (final relationship in _elements(relationships, 'Relationship')) {
      final id = _attributeByLocalName(relationship, 'Id');
      final target = _attributeByLocalName(relationship, 'Target');
      if (id != null && target != null) relationshipTargets[id] = target;
    }

    final sharedStrings = <String>[];
    final sharedFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedFile != null) {
      final sharedDocument = XmlDocument.parse(
        utf8.decode(_archiveContent(sharedFile), allowMalformed: true),
      );
      for (final item in _elements(sharedDocument, 'si')) {
        sharedStrings.add(
          _elements(item, 't').map((element) => element.innerText).join(),
        );
      }
    }

    final sections = <DocumentPreviewSection>[];
    var truncated = false;
    final sheets = _elements(workbook, 'sheet').take(100);
    for (final sheet in sheets) {
      final name = _attributeByLocalName(sheet, 'name') ??
          'Sheet ${sections.length + 1}';
      final relationshipId = _attributeByLocalName(sheet, 'id');
      final target =
          relationshipId == null ? null : relationshipTargets[relationshipId];
      if (target == null) continue;
      final path = _resolveOoxmlPath('xl', target);
      final sheetFile = archive.findFile(path);
      if (sheetFile == null) continue;
      final sheetDocument = XmlDocument.parse(
        utf8.decode(_archiveContent(sheetFile), allowMalformed: true),
      );
      final rows = <List<String>>[];
      for (final row in _elements(sheetDocument, 'row')) {
        if (rows.length >= _maxTableRows) {
          truncated = true;
          break;
        }
        final values = <String>[];
        for (final cell in row.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'c')) {
          final reference = _attributeByLocalName(cell, 'r') ?? '';
          final columnIndex = _spreadsheetColumnIndex(reference);
          if (columnIndex >= _maxTableColumns) {
            truncated = true;
            continue;
          }
          while (values.length <= columnIndex) {
            values.add('');
          }
          values[columnIndex] = _spreadsheetCellValue(cell, sharedStrings);
        }
        rows.add(values);
      }
      sections.add(DocumentPreviewSection(title: name, rows: rows));
    }
    if (sections.isEmpty) {
      throw const DocumentPreviewException('invalid_document');
    }
    return DocumentPreviewData(
      kind: DocumentPreviewKind.xlsx,
      sections: sections,
      truncated: truncated,
    );
  }

  static DocumentPreviewData _parsePptx(Uint8List bytes) {
    final archive = _decodeOoxml(bytes);
    final slideFiles = archive.files
        .where(
          (file) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name),
        )
        .toList()
      ..sort((a, b) => _numberInName(a.name).compareTo(_numberInName(b.name)));
    if (slideFiles.isEmpty) {
      throw const DocumentPreviewException('invalid_document');
    }

    final sections = <DocumentPreviewSection>[];
    var truncated = slideFiles.length > _maxSlides;
    for (final file in slideFiles.take(_maxSlides)) {
      final document = XmlDocument.parse(
        utf8.decode(_archiveContent(file), allowMalformed: true),
      );
      final paragraphs = <String>[];
      for (final paragraph in _elements(document, 'p')) {
        final text = _elements(paragraph, 't')
            .map((element) => element.innerText)
            .join()
            .trim();
        if (text.isNotEmpty) paragraphs.add(text);
      }
      final slideNumber = _numberInName(file.name);
      sections.add(
        DocumentPreviewSection(
          title: 'Slide $slideNumber',
          text: paragraphs.join('\n\n'),
        ),
      );
    }
    return DocumentPreviewData(
      kind: DocumentPreviewKind.pptx,
      sections: sections,
      truncated: truncated,
    );
  }

  static Archive _decodeOoxml(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes, verify: true);
    } on ArchiveException {
      throw const DocumentPreviewException('invalid_document');
    } on FormatException {
      throw const DocumentPreviewException('invalid_document');
    }
  }

  static XmlDocument _readXml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) {
      throw const DocumentPreviewException('invalid_document');
    }
    try {
      return XmlDocument.parse(
        utf8.decode(_archiveContent(file), allowMalformed: true),
      );
    } on XmlParserException {
      throw const DocumentPreviewException('invalid_document');
    }
  }

  static Uint8List _archiveContent(ArchiveFile file) {
    if (file.size > _maxOoxmlEntryBytes) {
      throw const DocumentPreviewException('file_too_large');
    }
    return file.content;
  }

  static Iterable<XmlElement> _elements(XmlNode node, String localName) {
    return node.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName);
  }

  static XmlElement? _firstElement(XmlNode node, String localName) {
    for (final element in _elements(node, localName)) {
      return element;
    }
    return null;
  }

  static String? _attributeByLocalName(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _paragraphText(XmlElement paragraph) {
    final output = StringBuffer();
    for (final node in paragraph.descendants.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 't':
        case 'delText':
          output.write(node.innerText);
          break;
        case 'tab':
          output.write('\t');
          break;
        case 'br':
        case 'cr':
          output.write('\n');
          break;
      }
    }
    return output.toString().trim();
  }

  static String _paragraphStyle(XmlElement paragraph) {
    final style = _elements(paragraph, 'pStyle').firstOrNull;
    return style == null ? '' : (_attributeByLocalName(style, 'val') ?? '');
  }

  static List<List<String>> _wordTableRows(XmlElement table) {
    final rows = <List<String>>[];
    for (final row in table.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tr')) {
      final cells = row.children
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'tc')
          .map((cell) => _elements(cell, 'p')
              .map(_paragraphText)
              .where((text) => text.isNotEmpty)
              .join('\n'))
          .take(_maxTableColumns)
          .toList(growable: false);
      rows.add(cells);
      if (rows.length >= _maxTableRows) break;
    }
    return rows;
  }

  static String _rowsToMarkdown(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final width = rows.fold<int>(
      0,
      (current, row) => row.length > current ? row.length : current,
    );
    if (width == 0) return '';
    String renderRow(List<String> row) {
      final cells = List<String>.generate(
        width,
        (index) => index < row.length
            ? row[index].replaceAll('|', r'\|').replaceAll('\n', '<br>')
            : '',
      );
      return '| ${cells.join(' | ')} |';
    }

    final output = StringBuffer()
      ..writeln(renderRow(rows.first))
      ..writeln('| ${List<String>.filled(width, '---').join(' | ')} |');
    for (final row in rows.skip(1)) {
      output.writeln(renderRow(row));
    }
    return output.toString().trimRight();
  }

  static String _spreadsheetCellValue(
    XmlElement cell,
    List<String> sharedStrings,
  ) {
    final type = _attributeByLocalName(cell, 't');
    if (type == 'inlineStr') {
      return _elements(cell, 't').map((item) => item.innerText).join();
    }
    final value = _firstElement(cell, 'v')?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(value);
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
    }
    if (type == 'b') return value == '1' ? 'TRUE' : 'FALSE';
    return value;
  }

  static int _spreadsheetColumnIndex(String reference) {
    var result = 0;
    var found = false;
    for (final codeUnit in reference.codeUnits) {
      final upper =
          codeUnit >= 97 && codeUnit <= 122 ? codeUnit - 32 : codeUnit;
      if (upper < 65 || upper > 90) break;
      found = true;
      result = result * 26 + upper - 64;
    }
    return found ? result - 1 : 0;
  }

  static String _resolveOoxmlPath(String base, String target) {
    final parts = <String>[];
    final combined =
        target.startsWith('/') ? target.substring(1) : '$base/$target';
    for (final part in combined.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static int _numberInName(String value) {
    return int.tryParse(
            RegExp(r'(\d+)').allMatches(value).lastOrNull?.group(1) ?? '') ??
        0;
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    final start = bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? 3
        : 0;
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  static String _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
  }) {
    final codeUnits = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      final first = bytes[index];
      final second = bytes[index + 1];
      codeUnits
          .add(littleEndian ? first | (second << 8) : (first << 8) | second);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _stripRtf(String input) {
    var output = input;
    output = output.replaceAll(
      RegExp(
          r'{\\\*\\(?:fonttbl|colortbl|stylesheet|info|pict)[^{}]*(?:{[^{}]*}[^{}]*)*}'),
      '',
    );
    output = output.replaceAllMapped(
      RegExp(r"\\'([0-9a-fA-F]{2})"),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    );
    output = output.replaceAllMapped(
      RegExp(r'\\u(-?\d+)\??'),
      (match) {
        var value = int.parse(match.group(1)!);
        if (value < 0) value += 65536;
        return String.fromCharCode(value);
      },
    );
    output = output
        .replaceAll(RegExp(r'\\(?:par|line)\b ?'), '\n')
        .replaceAll(RegExp(r'\\tab\b ?'), '\t')
        .replaceAll(r'\{', '{')
        .replaceAll(r'\}', '}')
        .replaceAll(r'\\', '\\')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return output;
  }

  static ({String text, bool truncated}) _limitText(String value) {
    if (value.length <= _maxOutputCharacters) {
      return (text: value, truncated: false);
    }
    return (
      text: value.substring(0, _maxOutputCharacters),
      truncated: true,
    );
  }
}
