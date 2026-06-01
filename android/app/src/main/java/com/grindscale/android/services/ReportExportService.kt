package com.grindscale.android.services

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import com.grindscale.android.domain.AnalysisMode
import com.grindscale.android.domain.AnalysisStats
import com.grindscale.android.domain.HistogramBin
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.min

/**
 * UTF-8 BOM CSV for Excel parity with iOS, and a pragmatic multi-page PDF.
 */
object ReportExportService {

    fun makeCsv(
        stats: AnalysisStats,
        profileName: String,
        coinName: String,
        calibrationText: String,
        recommendation: String,
        histogram: List<HistogramBin>,
        histogramMetaText: String,
        particleDiameters: List<Double>,
        particleDiameterUnit: String,
        reportDate: Date
    ): ByteArray {
        val lines = ArrayList<String>()
        val df = SimpleDateFormat("yyyy年M月d日 a h:mm", Locale.TAIWAN)
        lines.add(csvRow(listOf("咖啡粉粒徑分析報告", "GrindScale")))
        lines.add(csvRow(listOf("產生時間", df.format(reportDate))))
        lines.add(csvRow(listOf("器具 / Brew device", profileName)))
        lines.add(csvRow(listOf("參照物 / Reference", coinName)))
        lines.add(
            csvRow(
                listOf(
                    "分析模式",
                    if (stats.mode == AnalysisMode.calibrated) "校正 (µm)" else "相對 (px)"
                )
            )
        )
        lines.add(csvRow(listOf("校正說明", calibrationText)))
        lines.add("")
        lines.add(csvRow(listOf("— 統計摘要 —")))
        lines.add(csvRow(listOf("項目", "數值", "單位")))
        lines.add(csvRow(listOf("顆粒數", "${stats.particleCount}", "—")))
        lines.add(csvRow(listOf("均勻度 Score", "${stats.uniformityScore}", "—")))
        lines.add(csvRow(listOf("平均粒徑", String.format(Locale.US, "%.2f", stats.mean), stats.unitLabel)))
        lines.add(csvRow(listOf("標準差", String.format(Locale.US, "%.2f", stats.std), stats.unitLabel)))
        lines.add(csvRow(listOf("變異係數 CV", String.format(Locale.US, "%.4f", stats.cv), "—")))
        lines.add(csvRow(listOf("D10", String.format(Locale.US, "%.2f", stats.d10), stats.unitLabel)))
        lines.add(csvRow(listOf("D50", String.format(Locale.US, "%.2f", stats.d50), stats.unitLabel)))
        lines.add(csvRow(listOf("D90", String.format(Locale.US, "%.2f", stats.d90), stats.unitLabel)))
        lines.add(csvRow(listOf("細粉比例", String.format(Locale.US, "%.2f%%", stats.fineRatio * 100), "%")))
        lines.add(csvRow(listOf("目標區比例", String.format(Locale.US, "%.2f%%", stats.targetRatio * 100), "%")))
        lines.add(csvRow(listOf("粗粉比例", String.format(Locale.US, "%.2f%%", stats.coarseRatio * 100), "%")))
        lines.add(csvRow(listOf("雙峰特徵", if (stats.bimodal) "是" else "否", "—")))
        lines.add("")
        lines.add(csvRow(listOf("研磨建議 / Recommendation")))
        lines.add(csvRow(listOf(recommendation)))
        if (histogramMetaText.isNotBlank()) {
            lines.add("")
            lines.add(csvRow(listOf("直方圖備註")))
            lines.add(csvRow(listOf(histogramMetaText)))
        }
        lines.add("")
        lines.add(csvRow(listOf("— 粒徑分佈區間 (0–1000 µm) —")))
        lines.add(csvRow(listOf("區間起 (µm)", "區間迄 (µm)", "顆粒數")))
        for (bin in histogram) {
            lines.add(
                csvRow(
                    listOf(
                        String.format(Locale.US, "%.1f", bin.start),
                        String.format(Locale.US, "%.1f", bin.end),
                        "${bin.count}"
                    )
                )
            )
        }
        lines.add("")
        lines.add(csvRow(listOf("— 顆粒明細（等效直徑）—")))
        lines.add(csvRow(listOf("序號", "等效直徑 ($particleDiameterUnit)")))
        particleDiameters.forEachIndexed { i, d ->
            lines.add(csvRow(listOf("${i + 1}", String.format(Locale.US, "%.2f", d))))
        }
        val body = lines.joinToString("\r\n").toByteArray(Charsets.UTF_8)
        return byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + body
    }

    private fun csvRow(fields: List<String>): String =
        fields.joinToString(",", transform = ::csvEscape)

    private fun csvEscape(field: String): String {
        if (field.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
            return "\"" + field.replace("\"", "\"\"") + "\""
        }
        return field
    }

    private const val PDF_W = 595
    private const val PDF_H = 842

    fun makePdf(
        stats: AnalysisStats,
        profileName: String,
        coinName: String,
        calibrationText: String,
        recommendation: String,
        histogram: List<HistogramBin>,
        histogramMetaText: String,
        particleDiameters: List<Double>,
        particleDiameterUnit: String,
        reportDate: Date,
        overlayImage: Bitmap?
    ): ByteArray {
        val doc = PdfDocument()
        val margin = 48f
        val contentW = PDF_W - 2 * margin
        val titlePaint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = 18f
                typeface = Typeface.DEFAULT_BOLD
                color = 0xff111111.toInt()
            }
        val headingPaint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                color = 0xff111111.toInt()
            }
        val bodyPaint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = 10f
                color = 0xff222222.toInt()
            }
        val footerPaint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = 8f
                color = 0xff666666.toInt()
            }
        val barPaintFill =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
                color = 0xffd4a056.toInt()
            }
        val barPaintStroke =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1f
                color = 0xff888888.toInt()
            }

        val df = SimpleDateFormat("yyyy年M月d日 HH:mm", Locale.TAIWAN)
        var renderedPageLabel = 0

        fun startNextPage(): Pair<PdfDocument.Page, Canvas> {
            renderedPageLabel++
            val info =
                PdfDocument.PageInfo.Builder(PDF_W, PDF_H, renderedPageLabel).setContentRect(
                    Rect(0, 0, PDF_W, PDF_H)
                ).create()
            val p = doc.startPage(info)
            return Pair(p, p.canvas)
        }

        fun drawFooter(c: Canvas) {
            c.drawLine(margin, PDF_H - margin - 8, PDF_W - margin, PDF_H - margin - 8, barPaintStroke)
            c.drawText(
                "頁次 $renderedPageLabel",
                PDF_W - margin - 80,
                PDF_H - 28,
                footerPaint
            )
        }

        var (page, canvas) = startNextPage()
        var y = margin + 8f

        canvas.drawText("咖啡粉粒徑分析報告", margin, y + 20f, titlePaint)
        y += 52f
        canvas.drawText("產生：${df.format(reportDate)}", margin, y, bodyPaint); y += 17f
        canvas.drawText("器具：$profileName", margin, y, bodyPaint); y += 17f
        canvas.drawText("參照物：$coinName", margin, y, bodyPaint); y += 22f
        for (line in wrapText(calibrationText, contentW.toInt(), bodyPaint)) {
            canvas.drawText(line, margin, y, bodyPaint); y += 14f
        }
        y += 10f

        overlayImage?.let { bmp ->
            val mh = 200f
            val scale = min(contentW / bmp.width.toFloat(), mh / bmp.height.toFloat())
            val dw = (bmp.width * scale).toInt().coerceAtLeast(1)
            val dh = (bmp.height * scale).toInt().coerceAtLeast(1)
            if (y + dh > PDF_H - margin - 40) {
                drawFooter(canvas)
                doc.finishPage(page)
                val next = startNextPage()
                page = next.first
                canvas = next.second
                y = margin + 16f
            }
            canvas.drawBitmap(bmp, null, Rect(margin.toInt(), y.toInt(), (margin + dw).toInt(), (y + dh).toInt()), null)
            y += dh + 18f
        }

        canvas.drawText("統計數值", margin, y + 14f, headingPaint); y += 34f
        val statLines =
            listOf(
                "顆粒數　${stats.particleCount}",
                "Score　${stats.uniformityScore}",
                "CV　${String.format(Locale.US, "%.4f", stats.cv)}",
                "細／目／粗　${String.format(Locale.US, "%.1f", stats.fineRatio * 100)}%／" +
                    "${String.format(Locale.US, "%.1f", stats.targetRatio * 100)}%／" +
                    "${String.format(Locale.US, "%.1f", stats.coarseRatio * 100)}%",
                "D10／D50／D90　${String.format(Locale.US, "%.0f", stats.d10)}／" +
                    "${String.format(Locale.US, "%.0f", stats.d50)}／" +
                    "${String.format(Locale.US, "%.0f", stats.d90)}　${stats.unitLabel}"
            )
        for (s in statLines) {
            canvas.drawText(s, margin, y, bodyPaint); y += 16f
        }
        y += 12f

        if (histogram.isNotEmpty()) {
            canvas.drawText("粒徑分佈（0–1000 µm）", margin, y + 14f, headingPaint); y += 30f
            val chartLeft = margin
            val chartRight = margin + contentW
            val chartHeight = 100f
            val chartBottom = y + chartHeight
            canvas.drawRect(chartLeft, y, chartRight, chartBottom, barPaintStroke)
            val maxC = histogram.maxOf { it.count }.coerceAtLeast(1)
            val n = histogram.size.coerceAtLeast(1).toFloat()
            val band = (chartRight - chartLeft) / n
            histogram.forEachIndexed { i, b ->
                val h = (b.count.toFloat() / maxC) * (chartBottom - y - 4f)
                val left = chartLeft + i * band + 1f
                canvas.drawRect(
                    left,
                    chartBottom - h.coerceAtLeast(1f),
                    left + band - 3f,
                    chartBottom - 2f,
                    barPaintFill
                )
            }
            y = chartBottom + 20f
        }

        if (histogramMetaText.isNotBlank()) {
            canvas.drawText("直方圖說明", margin, y + 14f, headingPaint); y += 28f
            for (line in wrapText(histogramMetaText, contentW.toInt(), bodyPaint)) {
                if (y > PDF_H - margin - 50) break
                canvas.drawText(line, margin, y, bodyPaint); y += 14f
            }
            y += 8f
        }

        canvas.drawText("研磨建議", margin, y + 14f, headingPaint); y += 28f
        for (line in wrapText(recommendation, contentW.toInt(), bodyPaint)) {
            if (y > PDF_H - margin - 50) break
            canvas.drawText(line, margin, y, bodyPaint); y += 14f
        }

        drawFooter(canvas)
        doc.finishPage(page)

        if (particleDiameters.isNotEmpty()) {
            val listPaint =
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    textSize = 9f
                    color = 0xff333333.toInt()
                }
            val lineH = 12f
            val next = startNextPage()
            page = next.first
            canvas = next.second
            y = margin + 24f
            canvas.drawText("顆粒明細 ($particleDiameterUnit)", margin, y, headingPaint)
            y += 28f

            particleDiameters.forEachIndexed { i, d ->
                if (y > PDF_H - margin - 40) {
                    drawFooter(canvas)
                    doc.finishPage(page)
                    val p2 = startNextPage()
                    page = p2.first
                    canvas = p2.second
                    y = margin + 18f
                }
                canvas.drawText(
                    "#${i + 1}  ${String.format(Locale.US, "%.2f", d)}  $particleDiameterUnit",
                    margin,
                    y,
                    listPaint
                )
                y += lineH
            }
            drawFooter(canvas)
            doc.finishPage(page)
        }

        val out = ByteArrayOutputStream()
        doc.writeTo(out)
        doc.close()
        return out.toByteArray()
    }

    private fun wrapText(text: String, maxWidth: Int, paint: Paint): List<String> {
        if (text.isEmpty()) return listOf("")
        val out = ArrayList<String>()
        for (para in text.split("\n")) {
            if (para.isEmpty()) {
                out.add("")
                continue
            }
            var line = ""
            para.forEach { ch ->
                val t = line + ch
                if (paint.measureText(t) <= maxWidth) line = t
                else {
                    if (line.isNotEmpty()) out.add(line)
                    line = ch.toString()
                }
            }
            if (line.isNotEmpty()) out.add(line)
        }
        return out
    }
}
