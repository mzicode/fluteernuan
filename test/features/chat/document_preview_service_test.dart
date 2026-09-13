import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/chat/services/document_preview_service.dart';

void main() {
  group('DocumentPreviewService format routing', () {
    test('recognizes the requested preview formats case-insensitively', () {
      const names = <String>[
        'report.PDF',
        'letter.doc',
        'letter.docx',
        'ledger.xls',
        'ledger.xlsx',
        'deck.ppt',
        'deck.pptx',
        'notes.txt',
        'data.csv',
        'readme.md',
        'rich.rtf',
        'payload.json',
        'layout.xml',
        'page.html',
      ];

      expect(names.every(DocumentPreviewService.supports), isTrue);
      expect(DocumentPreviewService.supports('archive.zip'), isFalse);
    });
  });

  group('text previews', () {
    test('loads a local text file off the caller isolate', () async {
      final directory =
          await Directory.systemTemp.createTemp('document-preview');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/notes.txt')
        ..writeAsStringSync('Preview content\nSecond line');

      final result = await DocumentPreviewService.load(
        path: file.path,
        fileName: 'notes.txt',
      );

      expect(result.text, contains('Preview content'));
    });

    test('decodes UTF-16LE text with a BOM', () {
      final bytes = Uint8List.fromList(<int>[
        0xff,
        0xfe,
        0x60,
        0x4f,
        0x7d,
        0x59,
      ]);

      final result = DocumentPreviewService.parseBytes(
        bytes,
        fileName: 'hello.txt',
      );

      expect(result.kind, DocumentPreviewKind.text);
      expect(result.text, '你好');
    });

    test('parses quoted CSV values and embedded newlines', () {
      final result = DocumentPreviewService.parseBytes(
        Uint8List.fromList(
          utf8.encode('name,note\r\nAlice,"line 1\nline 2"'),
        ),
        fileName: 'data.csv',
      );

      expect(result.kind, DocumentPreviewKind.csv);
      expect(
          result.sections.single.rows[1], <String>['Alice', 'line 1\nline 2']);
    });

    test('extracts readable text from RTF controls', () {
      final result = DocumentPreviewService.parseBytes(
        Uint8List.fromList(utf8.encode(r'{\rtf1\ansi Hello\par \u20320?}')),
        fileName: 'message.rtf',
      );

      expect(result.text, contains('Hello'));
      expect(result.text, contains('你'));
    });

    test('removes executable HTML content before extracting text', () {
      final result = DocumentPreviewService.parseBytes(
        Uint8List.fromList(
          utf8.encode(
            '<html><head><title>Notice</title><script>steal()</script></head>'
            '<body><h1>Hello</h1><p>World</p></body></html>',
          ),
        ),
        fileName: 'notice.html',
      );

      expect(result.text, contains('Notice'));
      expect(result.text, contains('Hello'));
      expect(result.text, isNot(contains('steal')));
    });
  });

  group('OOXML previews', () {
    test('extracts headings, paragraphs, and tables from DOCX', () {
      final bytes = _zip(<String, String>{
        'word/document.xml': '''
          <w:document xmlns:w="urn:w">
            <w:body>
              <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Plan</w:t></w:r></w:p>
              <w:p><w:r><w:t>First paragraph</w:t></w:r></w:p>
              <w:tbl><w:tr>
                <w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Status</w:t></w:r></w:p></w:tc>
              </w:tr></w:tbl>
            </w:body>
          </w:document>
        ''',
      });

      final result = DocumentPreviewService.parseBytes(
        bytes,
        fileName: 'plan.docx',
      );

      expect(result.kind, DocumentPreviewKind.docx);
      expect(result.text, contains('# Plan'));
      expect(result.text, contains('First paragraph'));
      expect(result.text, contains('| Name | Status |'));
    });

    test('extracts sheets, shared strings, and booleans from XLSX', () {
      final bytes = _zip(<String, String>{
        'xl/workbook.xml': '''
          <workbook xmlns:r="urn:r"><sheets><sheet name="Overview" r:id="rId1"/></sheets></workbook>
        ''',
        'xl/_rels/workbook.xml.rels': '''
          <Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>
        ''',
        'xl/sharedStrings.xml': '''
          <sst><si><t>Name</t></si><si><t>Alice</t></si></sst>
        ''',
        'xl/worksheets/sheet1.xml': '''
          <worksheet><sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="b"><v>1</v></c></row>
            <row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>42</v></c></row>
          </sheetData></worksheet>
        ''',
      });

      final result = DocumentPreviewService.parseBytes(
        bytes,
        fileName: 'overview.xlsx',
      );

      expect(result.kind, DocumentPreviewKind.xlsx);
      expect(result.sections.single.title, 'Overview');
      expect(result.sections.single.rows[0], <String>['Name', 'TRUE']);
      expect(result.sections.single.rows[1], <String>['Alice', '42']);
    });

    test('extracts ordered slide text from PPTX', () {
      final bytes = _zip(<String, String>{
        'ppt/slides/slide2.xml':
            '<p:sld xmlns:p="urn:p" xmlns:a="urn:a"><a:p><a:r><a:t>Second</a:t></a:r></a:p></p:sld>',
        'ppt/slides/slide1.xml':
            '<p:sld xmlns:p="urn:p" xmlns:a="urn:a"><a:p><a:r><a:t>First</a:t></a:r></a:p></p:sld>',
      });

      final result = DocumentPreviewService.parseBytes(
        bytes,
        fileName: 'slides.pptx',
      );

      expect(result.kind, DocumentPreviewKind.pptx);
      expect(result.sections.map((section) => section.text), <String>[
        'First',
        'Second',
      ]);
    });
  });
}

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}
