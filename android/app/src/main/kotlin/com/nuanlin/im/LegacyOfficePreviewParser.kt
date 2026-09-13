// 文件用途：从旧版 OLE Office 文件提取受限的可读文本、表格和幻灯片内容。
// 核心逻辑：Apache POI 只做本地结构解析，输出严格限制大小，不渲染宏、外部链接或嵌入对象。
package com.nuanlin.im

import org.apache.poi.hslf.usermodel.HSLFSlideShow
import org.apache.poi.hslf.usermodel.HSLFTextShape
import org.apache.poi.hwpf.OldWordFileFormatException
import org.apache.poi.hwpf.extractor.Word6Extractor
import org.apache.poi.hwpf.extractor.WordExtractor
import org.apache.poi.ss.usermodel.DataFormatter
import org.apache.poi.util.IOUtils
import org.apache.poi.hssf.usermodel.HSSFWorkbook
import java.io.File
import java.io.FileInputStream

internal object LegacyOfficePreviewParser {
    private const val maxRows = 1000
    private const val maxColumns = 64
    private const val maxSheets = 50
    private const val maxSlides = 500
    private const val maxOutputCharacters = 2 * 1024 * 1024
    private const val maxArrayBytes = 24 * 1024 * 1024

    fun extract(file: File, extension: String): Map<String, Any> {
        IOUtils.setByteArrayMaxOverride(maxArrayBytes)
        return when (extension) {
            "doc" -> extractDoc(file)
            "xls" -> extractXls(file)
            "ppt" -> extractPpt(file)
            else -> mapOf("available" to false, "reason" to "unsupported_extension")
        }
    }

    private fun extractDoc(file: File): Map<String, Any> {
        val text = try {
            FileInputStream(file).use { input ->
                WordExtractor(input).use { extractor -> extractor.text }
            }
        } catch (_: OldWordFileFormatException) {
            FileInputStream(file).use { input ->
                Word6Extractor(input).use { extractor -> extractor.text }
            }
        }
        val bounded = boundText(text)
        return mapOf(
            "available" to true,
            "kind" to "doc",
            "text" to bounded.first,
            "truncated" to bounded.second,
        )
    }

    private fun extractXls(file: File): Map<String, Any> {
        val formatter = DataFormatter()
        val sections = mutableListOf<Map<String, Any>>()
        val budget = TextBudget()
        var truncated = false
        FileInputStream(file).use { input ->
            HSSFWorkbook(input).use { workbook ->
                val sheetCount = minOf(workbook.numberOfSheets, maxSheets)
                truncated = workbook.numberOfSheets > maxSheets
                for (sheetIndex in 0 until sheetCount) {
                    val sheet = workbook.getSheetAt(sheetIndex)
                    val rows = mutableListOf<List<String>>()
                    val rowLimit = minOf(sheet.lastRowNum + 1, maxRows)
                    if (sheet.lastRowNum + 1 > maxRows) truncated = true
                    for (rowIndex in 0 until rowLimit) {
                        val row = sheet.getRow(rowIndex)
                        if (row == null) {
                            rows.add(emptyList())
                            continue
                        }
                        val columnLimit = minOf(row.lastCellNum.toInt().coerceAtLeast(0), maxColumns)
                        if (row.lastCellNum > maxColumns) truncated = true
                        rows.add(
                            (0 until columnLimit).map { columnIndex ->
                                val cell = row.getCell(columnIndex)
                                if (cell == null) "" else budget.take(formatter.formatCellValue(cell))
                            },
                        )
                    }
                    sections += mapOf(
                        "title" to (sheet.sheetName.ifBlank { "Sheet ${sheetIndex + 1}" }),
                        "rows" to rows,
                    )
                }
            }
        }
        return mapOf(
            "available" to true,
            "kind" to "xls",
            "sections" to sections,
            "truncated" to (truncated || budget.truncated),
        )
    }

    private fun extractPpt(file: File): Map<String, Any> {
        val sections = mutableListOf<Map<String, Any>>()
        val budget = TextBudget()
        var truncated = false
        FileInputStream(file).use { input ->
            HSLFSlideShow(input).use { slideshow ->
                val slides = slideshow.slides
                val slideLimit = minOf(slides.size, maxSlides)
                truncated = slides.size > maxSlides
                for (slideIndex in 0 until slideLimit) {
                    val text = slides[slideIndex].shapes
                        .filterIsInstance<HSLFTextShape>()
                        .mapNotNull { it.text?.trim()?.takeIf(String::isNotEmpty) }
                        .map(budget::take)
                        .filter(String::isNotEmpty)
                        .joinToString("\n\n")
                    sections += mapOf(
                        "title" to "Slide ${slideIndex + 1}",
                        "text" to text,
                    )
                }
            }
        }
        return mapOf(
            "available" to true,
            "kind" to "ppt",
            "sections" to sections,
            "truncated" to (truncated || budget.truncated),
        )
    }

    private fun boundText(value: String): Pair<String, Boolean> =
        if (value.length <= maxOutputCharacters) value to false
        else value.substring(0, maxOutputCharacters) to true

    private class TextBudget {
        var truncated = false
            private set
        private var remaining = maxOutputCharacters

        fun take(value: String): String {
            if (value.length <= remaining) {
                remaining -= value.length
                return value
            }
            truncated = true
            if (remaining == 0) return ""
            return value.substring(0, remaining).also { remaining = 0 }
        }
    }
}
