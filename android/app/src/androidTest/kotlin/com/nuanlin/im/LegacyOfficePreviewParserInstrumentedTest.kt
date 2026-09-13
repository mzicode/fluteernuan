// 文件用途：在真实 Android Runtime 上验证旧版 Office 解析器及 Apache POI 兼容性。
package com.nuanlin.im

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.apache.poi.hssf.usermodel.HSSFWorkbook
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

@RunWith(AndroidJUnit4::class)
class LegacyOfficePreviewParserInstrumentedTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun parsesGeneratedXls() {
        val file = File(context.cacheDir, "legacy-preview-test.xls")
        HSSFWorkbook().use { workbook ->
            val sheet = workbook.createSheet("Overview")
            sheet.createRow(0).apply {
                createCell(0).setCellValue("Name")
                createCell(1).setCellValue("Value")
            }
            sheet.createRow(1).apply {
                createCell(0).setCellValue("Alice")
                createCell(1).setCellValue(42.0)
            }
            FileOutputStream(file).use(workbook::write)
        }

        val result = LegacyOfficePreviewParser.extract(file, "xls")
        assertEquals(true, result["available"])
        val sections = result["sections"] as List<*>
        assertEquals("Overview", (sections.single() as Map<*, *>)["title"])
    }

    @Test
    fun parsesProvidedPptSample() {
        val path = InstrumentationRegistry.getArguments().getString("pptSample")
        assumeTrue("Pass -e pptSample with an app-owned PPT file", !path.isNullOrBlank())

        val result = LegacyOfficePreviewParser.extract(File(path!!), "ppt")
        assertEquals(true, result["available"])
        val sections = result["sections"] as List<*>
        assertTrue(sections.isNotEmpty())
        assertTrue(sections.any { (it as Map<*, *>)["text"].toString().isNotBlank() })
    }

    @Test
    fun parsesProvidedDocSample() {
        val path = InstrumentationRegistry.getArguments().getString("docSample")
        assumeTrue("Pass -e docSample with an app-owned DOC file", !path.isNullOrBlank())

        val result = LegacyOfficePreviewParser.extract(File(path!!), "doc")
        assertEquals(true, result["available"])
        assertTrue(result["text"].toString().isNotBlank())
    }
}
