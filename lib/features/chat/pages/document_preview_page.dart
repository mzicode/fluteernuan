// 文件用途：提供聊天文档的统一应用内预览页面。
// 核心逻辑：PDF 使用本地渲染器，文本与 OOXML 使用解析后的安全内容视图，旧版 Office 保留系统打开入口。
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/android_pdf_preview_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import '../services/android_legacy_office_preview_service.dart';
import '../services/document_preview_service.dart';

class DocumentPreviewPage extends StatefulWidget {
  final String path;
  final String fileName;
  final Future<void> Function()? onOpenExternally;

  const DocumentPreviewPage({
    super.key,
    required this.path,
    required this.fileName,
    this.onOpenExternally,
  });

  @override
  State<DocumentPreviewPage> createState() => _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends State<DocumentPreviewPage> {
  late final String _extension =
      DocumentPreviewService.extensionOf(widget.fileName);
  Future<DocumentPreviewData>? _previewFuture;

  @override
  void initState() {
    super.initState();
    if (_extension != 'pdf') {
      _previewFuture = PlatformUtils.isAndroid &&
              DocumentPreviewService.legacyOfficeExtensions.contains(_extension)
          ? AndroidLegacyOfficePreviewService.load(
              path: widget.path,
              fileName: widget.fileName,
            )
          : DocumentPreviewService.load(
              path: widget.path,
              fileName: widget.fileName,
            );
    }
  }

  String _text({
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    final code = AppLocalizations.of(context).language.code;
    return switch (code) {
      'en' => en,
      'zh_TW' => zhTW ?? zhCN,
      _ => zhCN,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111214) : Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              _extension.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _text(zhCN: '分享', zhTW: '分享', en: 'Share'),
            onPressed: () => Share.shareXFiles(
              <XFile>[XFile(widget.path, name: widget.fileName)],
            ),
            icon: const Icon(Icons.share_outlined),
          ),
          if (widget.onOpenExternally != null)
            IconButton(
              tooltip: _text(
                zhCN: '使用其他应用打开',
                zhTW: '使用其他應用程式開啟',
                en: 'Open with another app',
              ),
              onPressed: widget.onOpenExternally,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: _extension == 'pdf' ? _buildPdf(isDark) : _buildParsed(isDark),
    );
  }

  Widget _buildPdf(bool isDark) {
    if (!PlatformUtils.isAndroid) {
      return _PreviewStatus(
        icon: Icons.picture_as_pdf_outlined,
        title: _text(
          zhCN: '当前平台使用系统 PDF 阅读器',
          zhTW: '目前平台使用系統 PDF 閱讀器',
          en: 'Use the system PDF reader on this platform',
        ),
        description: _text(
          zhCN: 'Android 支持应用内 PDF 预览；当前平台请使用已安装的 PDF 阅读器打开。',
          zhTW: 'Android 支援應用程式內 PDF 預覽；目前平台請使用已安裝的 PDF 閱讀器開啟。',
          en: 'In-app PDF preview is available on Android. Open this file with an installed PDF reader on the current platform.',
        ),
        actionLabel: widget.onOpenExternally == null
            ? null
            : _text(zhCN: '打开 PDF', zhTW: '開啟 PDF', en: 'Open PDF'),
        onAction: widget.onOpenExternally,
      );
    }
    return _AndroidPdfPreview(
      path: widget.path,
      backgroundColor:
          isDark ? const Color(0xFF18191C) : const Color(0xFFE9EAED),
    );
  }

  Widget _buildParsed(bool isDark) {
    return FutureBuilder<DocumentPreviewData>(
      future: _previewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _PreviewStatus(
            icon: Icons.error_outline_rounded,
            title: _text(
              zhCN: '无法预览此文档',
              zhTW: '無法預覽此文件',
              en: 'Unable to preview this document',
            ),
            description: _errorDescription(snapshot.error),
            actionLabel: widget.onOpenExternally == null
                ? null
                : _text(
                    zhCN: '使用其他应用打开',
                    zhTW: '使用其他應用程式開啟',
                    en: 'Open with another app',
                  ),
            onAction: widget.onOpenExternally,
          );
        }

        final data = snapshot.data!;
        if (data.kind == DocumentPreviewKind.legacyOffice) {
          return _PreviewStatus(
            icon: _legacyIcon,
            title: _text(
              zhCN: '旧版 Office 格式',
              zhTW: '舊版 Office 格式',
              en: 'Legacy Office format',
            ),
            description: _text(
              zhCN:
                  '此二进制格式无法在应用内可靠解析。请使用系统应用打开，或另存为 ${_modernOfficeExtension()} 后预览。',
              zhTW:
                  '此二進位格式無法在應用程式內可靠解析。請使用系統應用程式開啟，或另存為 ${_modernOfficeExtension()} 後預覽。',
              en: 'This binary format cannot be parsed reliably in the app. Open it with another app or save it as ${_modernOfficeExtension()} first.',
            ),
            actionLabel: widget.onOpenExternally == null
                ? null
                : _text(
                    zhCN: '使用其他应用打开',
                    zhTW: '使用其他應用程式開啟',
                    en: 'Open with another app',
                  ),
            onAction: widget.onOpenExternally,
          );
        }

        return Column(
          children: [
            if (data.truncated)
              _TruncatedBanner(
                text: _text(
                  zhCN: '文档内容较多，当前显示部分内容',
                  zhTW: '文件內容較多，目前顯示部分內容',
                  en: 'This document is large. A partial preview is shown.',
                ),
              ),
            Expanded(child: _buildContent(data, isDark)),
          ],
        );
      },
    );
  }

  Widget _buildContent(DocumentPreviewData data, bool isDark) {
    switch (data.kind) {
      case DocumentPreviewKind.markdown:
      case DocumentPreviewKind.docx:
        return Markdown(
          data: data.text,
          selectable: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: AppColors.textPrimaryFor(context),
            ),
          ),
        );
      case DocumentPreviewKind.csv:
      case DocumentPreviewKind.xlsx:
        return _SectionedTablePreview(
          sections: data.sections,
          emptyLabel: _text(
            zhCN: '此表格没有可显示的内容',
            zhTW: '此表格沒有可顯示的內容',
            en: 'This spreadsheet has no displayable content.',
          ),
        );
      case DocumentPreviewKind.pptx:
        return _SlidePreview(
          sections: data.sections,
          slideLabel: (index) => _text(
            zhCN: '第 ${index + 1} 页',
            zhTW: '第 ${index + 1} 頁',
            en: 'Slide ${index + 1}',
          ),
        );
      case DocumentPreviewKind.text:
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            child: SelectableText(
              data.text.isEmpty
                  ? _text(
                      zhCN: '此文件没有可显示的文本内容',
                      zhTW: '此檔案沒有可顯示的文字內容',
                      en: 'This file has no displayable text.',
                    )
                  : data.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.65,
                fontFamily: _extension == 'txt' || _extension == 'rtf'
                    ? null
                    : 'monospace',
                color: AppColors.textPrimaryFor(context),
              ),
            ),
          ),
        );
      case DocumentPreviewKind.pdf:
      case DocumentPreviewKind.legacyOffice:
        return const SizedBox.shrink();
    }
  }

  String _errorDescription(Object? error) {
    final code = error is DocumentPreviewException ? error.code : '';
    return switch (code) {
      'file_too_large' => _text(
          zhCN: '文件过大，已停止解析以保护应用性能。',
          zhTW: '檔案過大，已停止解析以保護應用程式效能。',
          en: 'The file is too large to parse safely.',
        ),
      'invalid_document' => _text(
          zhCN: '文件内容损坏、已加密或格式与扩展名不一致。',
          zhTW: '檔案內容損壞、已加密或格式與副檔名不一致。',
          en: 'The file is damaged, encrypted, or does not match its extension.',
        ),
      _ => _text(
          zhCN: '文件读取失败，可以尝试使用其他应用打开。',
          zhTW: '檔案讀取失敗，可以嘗試使用其他應用程式開啟。',
          en: 'The file could not be read. Try opening it with another app.',
        ),
    };
  }

  IconData get _legacyIcon => switch (_extension) {
        'doc' => Icons.description_outlined,
        'xls' => Icons.table_chart_outlined,
        'ppt' => Icons.slideshow_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  String _modernOfficeExtension() => switch (_extension) {
        'doc' => 'DOCX',
        'xls' => 'XLSX',
        'ppt' => 'PPTX',
        _ => '',
      };
}

class _AndroidPdfPreview extends StatefulWidget {
  final String path;
  final Color backgroundColor;

  const _AndroidPdfPreview({
    required this.path,
    required this.backgroundColor,
  });

  @override
  State<_AndroidPdfPreview> createState() => _AndroidPdfPreviewState();
}

class _AndroidPdfPreviewState extends State<_AndroidPdfPreview> {
  late final Future<AndroidPdfInfo> _info =
      AndroidPdfPreviewService.getInfo(widget.path);
  var _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AndroidPdfInfo>(
      future: _info,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
          );
        }
        final pageCount = snapshot.data!.pageCount;
        return LayoutBuilder(
          builder: (context, constraints) {
            final pixelRatio = MediaQuery.devicePixelRatioOf(context);
            final targetWidth =
                (constraints.maxWidth * pixelRatio).round().clamp(480, 1800);
            return Stack(
              children: [
                ColoredBox(
                  color: widget.backgroundColor,
                  child: PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: pageCount,
                    onPageChanged: (value) =>
                        setState(() => _currentPage = value),
                    itemBuilder: (context, index) => _AndroidPdfPageView(
                      path: widget.path,
                      pageIndex: index,
                      targetWidth: targetWidth,
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_currentPage + 1} / $pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AndroidPdfPageView extends StatefulWidget {
  final String path;
  final int pageIndex;
  final int targetWidth;

  const _AndroidPdfPageView({
    required this.path,
    required this.pageIndex,
    required this.targetWidth,
  });

  @override
  State<_AndroidPdfPageView> createState() => _AndroidPdfPageViewState();
}

class _AndroidPdfPageViewState extends State<_AndroidPdfPageView> {
  late Future<AndroidPdfPage> _page = _load();

  Future<AndroidPdfPage> _load() => AndroidPdfPreviewService.renderPage(
        path: widget.path,
        pageIndex: widget.pageIndex,
        targetWidth: widget.targetWidth,
      );

  @override
  void didUpdateWidget(covariant _AndroidPdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.targetWidth != widget.targetWidth) {
      _page = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AndroidPdfPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: IconButton(
              tooltip: MaterialLocalizations.of(context)
                  .refreshIndicatorSemanticLabel,
              onPressed: () => setState(() => _page = _load()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.file(
                File(snapshot.data!.imagePath),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const _PreviewStatus({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.55,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TruncatedBanner extends StatelessWidget {
  final String text;

  const _TruncatedBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionedTablePreview extends StatefulWidget {
  final List<DocumentPreviewSection> sections;
  final String emptyLabel;

  const _SectionedTablePreview({
    required this.sections,
    required this.emptyLabel,
  });

  @override
  State<_SectionedTablePreview> createState() => _SectionedTablePreviewState();
}

class _SectionedTablePreviewState extends State<_SectionedTablePreview> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return Center(child: Text(widget.emptyLabel));
    }
    final selected = widget.sections[_selectedIndex];
    return Column(
      children: [
        if (widget.sections.length > 1)
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              scrollDirection: Axis.horizontal,
              itemCount: widget.sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final selectedIndex = index == _selectedIndex;
                return ChoiceChip(
                  label: Text(widget.sections[index].title),
                  selected: selectedIndex,
                  onSelected: (_) => setState(() => _selectedIndex = index),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: selected.rows.isEmpty
              ? Center(child: Text(widget.emptyLabel))
              : _SpreadsheetGrid(rows: selected.rows),
        ),
      ],
    );
  }
}

class _SpreadsheetGrid extends StatelessWidget {
  final List<List<String>> rows;

  const _SpreadsheetGrid({required this.rows});

  @override
  Widget build(BuildContext context) {
    final columnCount = rows.fold<int>(
      1,
      (current, row) => row.length > current ? row.length : current,
    );
    const cellWidth = 164.0;
    const rowHeight = 58.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (columnCount * cellWidth).clamp(
          constraints.maxWidth,
          double.infinity,
        );
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: ListView.builder(
                itemCount: rows.length,
                itemExtent: rowHeight,
                itemBuilder: (context, rowIndex) {
                  final row = rows[rowIndex];
                  final header = rowIndex == 0;
                  return Row(
                    children: List<Widget>.generate(columnCount, (columnIndex) {
                      final value =
                          columnIndex < row.length ? row[columnIndex] : '';
                      return Container(
                        width: cellWidth,
                        height: rowHeight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: header
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                              : null,
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                            bottom: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                header ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlidePreview extends StatefulWidget {
  final List<DocumentPreviewSection> sections;
  final String Function(int index) slideLabel;

  const _SlidePreview({required this.sections, required this.slideLabel});

  @override
  State<_SlidePreview> createState() => _SlidePreviewState();
}

class _SlidePreviewState extends State<_SlidePreview> {
  final _pageController = PageController();
  var _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.sections.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final slide = widget.sections[index];
              return Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    margin: const EdgeInsets.all(18),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        slide.text,
                        style: const TextStyle(fontSize: 18, height: 1.55),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).previousPageTooltip,
                  onPressed: _page == 0
                      ? null
                      : () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    '${widget.slideLabel(_page)} / ${widget.sections.length}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                  onPressed: _page >= widget.sections.length - 1
                      ? null
                      : () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
