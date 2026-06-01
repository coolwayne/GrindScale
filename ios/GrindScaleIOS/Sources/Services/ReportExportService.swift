import Foundation
import UIKit

/// 產生可於 Microsoft Excel 開啟的 CSV（UTF-8 BOM）與粒徑分析 PDF 報告。
enum ReportExportService {

    // MARK: - CSV (Excel)

    static func makeCSV(
        stats: AnalysisStats,
        profileName: String,
        coinName: String,
        calibrationText: String,
        recommendation: String,
        histogram: [HistogramBin],
        histogramMetaText: String,
        particleDiameters: [Double],
        particleDiameterUnit: String,
        reportDate: Date
    ) -> Data {
        var lines: [String] = []
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateStyle = .long
        df.timeStyle = .medium

        lines.append(csvRow(["咖啡粉粒徑分析報告", "GrindScale"]))
        lines.append(csvRow(["產生時間", df.string(from: reportDate)]))
        lines.append(csvRow(["器具 / Brew device", profileName]))
        lines.append(csvRow(["參照物 / Reference", coinName]))
        lines.append(csvRow(["分析模式", stats.mode == .calibrated ? "校正 (µm)" : "相對 (px)"]))
        lines.append(csvRow(["校正說明", calibrationText]))
        lines.append("")
        lines.append(csvRow(["— 統計摘要 —"]))
        lines.append(csvRow(["項目", "數值", "單位"]))
        lines.append(csvRow(["顆粒數", "\(stats.particleCount)", "—"]))
        lines.append(csvRow(["均勻度 Score", "\(stats.uniformityScore)", "—"]))
        lines.append(csvRow(["平均粒徑", String(format: "%.2f", stats.mean), stats.unitLabel]))
        lines.append(csvRow(["標準差", String(format: "%.2f", stats.std), stats.unitLabel]))
        lines.append(csvRow(["變異係數 CV", String(format: "%.4f", stats.cv), "—"]))
        lines.append(csvRow(["D10", String(format: "%.2f", stats.d10), stats.unitLabel]))
        lines.append(csvRow(["D50", String(format: "%.2f", stats.d50), stats.unitLabel]))
        lines.append(csvRow(["D90", String(format: "%.2f", stats.d90), stats.unitLabel]))
        lines.append(csvRow(["細粉比例", String(format: "%.2f%%", stats.fineRatio * 100), "%"]))
        lines.append(csvRow(["目標區比例", String(format: "%.2f%%", stats.targetRatio * 100), "%"]))
        lines.append(csvRow(["粗粉比例", String(format: "%.2f%%", stats.coarseRatio * 100), "%"]))
        lines.append(csvRow(["雙峰特徵", stats.bimodal ? "是" : "否", "—"]))
        lines.append("")
        lines.append(csvRow(["研磨建議 / Recommendation"]))
        lines.append(csvRow([recommendation]))
        if !histogramMetaText.isEmpty {
            lines.append("")
            lines.append(csvRow(["直方圖備註"]))
            lines.append(csvRow([histogramMetaText]))
        }
        lines.append("")
        lines.append(csvRow(["— 粒徑分佈區間 (0–1000 µm) —"]))
        lines.append(csvRow(["區間起 (µm)", "區間迄 (µm)", "顆粒數"]))
        for bin in histogram {
            lines.append(csvRow([
                String(format: "%.1f", bin.start),
                String(format: "%.1f", bin.end),
                "\(bin.count)"
            ]))
        }
        lines.append("")
        lines.append(csvRow(["— 顆粒明細（等效直徑）—"]))
        lines.append(csvRow(["序號", "等效直徑 (\(particleDiameterUnit))"]))
        for (i, d) in particleDiameters.enumerated() {
            lines.append(csvRow(["\(i + 1)", String(format: "%.2f", d)]))
        }

        let body = lines.joined(separator: "\r\n")
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data(body.utf8))
        return bom
    }

    private static func csvRow(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",")
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - PDF

    private static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi
    private static let margin: CGFloat = 48
    private static let contentWidth = pageRect.width - margin * 2

    static func makePDF(
        stats: AnalysisStats,
        profileName: String,
        coinName: String,
        calibrationText: String,
        recommendation: String,
        histogram: [HistogramBin],
        histogramMetaText: String,
        particleDiameters: [Double],
        particleDiameterUnit: String,
        reportDate: Date,
        overlayImage: UIImage?
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "咖啡粉粒徑分析報告",
            kCGPDFContextAuthor as String: "GrindScale",
            kCGPDFContextCreator as String: "GrindScale iOS"
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_TW")
        df.dateStyle = .long
        df.timeStyle = .short

        return renderer.pdfData { ctx in
            var currentPage = 1
            var y = margin
            y = drawCoverBlock(
                ctx: ctx,
                startY: y,
                reportDateString: df.string(from: reportDate),
                profileName: profileName,
                coinName: coinName,
                stats: stats,
                calibrationText: calibrationText
            )

            if let img = overlayImage {
                y = drawOverlaySection(ctx: ctx, startY: y, image: img)
            }

            y = drawStatsTable(ctx: ctx, startY: y, stats: stats)
            y = drawDistributionSection(ctx: ctx, startY: y, stats: stats)

            if !histogram.isEmpty {
                y = drawHistogram(ctx: ctx, startY: y, bins: histogram)
            }

            if !histogramMetaText.isEmpty {
                y = drawParagraph(
                    ctx: ctx,
                    startY: y,
                    title: "直方圖說明",
                    body: histogramMetaText,
                    fontSize: 9
                )
            }

            y = drawParagraph(
                ctx: ctx,
                startY: y,
                title: "研磨建議",
                body: recommendation,
                fontSize: 10
            )

            let longList = particleDiameters.count > rowsPerParticlePage
            drawFooter(
                ctx: ctx,
                pageIndex: currentPage,
                extraLine: longList ? "顆粒明細列於後續頁次；完整數據請匯出 Excel（CSV）。" : nil
            )

            if !particleDiameters.isEmpty {
                var idx = 0
                while idx < particleDiameters.count {
                    ctx.beginPage()
                    currentPage += 1
                    let end = min(idx + rowsPerParticlePage, particleDiameters.count)
                    let slice = Array(particleDiameters[idx..<end])
                    _ = drawParticleTable(
                        ctx: ctx,
                        startY: margin,
                        diameters: slice,
                        unit: particleDiameterUnit,
                        startIndex: idx
                    )
                    if idx == 0, particleDiameters.count > rowsPerParticlePage {
                        let noteY = pageRect.height - margin - 36
                        drawText(
                            "（共 \(particleDiameters.count) 顆；以下分頁列出，完整明細請另匯出 Excel）",
                            x: margin,
                            y: noteY,
                            font: .italicSystemFont(ofSize: 8),
                            color: .darkGray
                        )
                    }
                    drawFooter(ctx: ctx, pageIndex: currentPage, extraLine: nil)
                    idx = end
                }
            }
        }
    }

    /// 單頁顆粒表列數上限（避免超出 A4 可印範圍）。
    private static let rowsPerParticlePage = 45

    private static func drawCoverBlock(
        ctx: UIGraphicsPDFRendererContext,
        startY: CGFloat,
        reportDateString: String,
        profileName: String,
        coinName: String,
        stats: AnalysisStats,
        calibrationText: String
    ) -> CGFloat {
        ctx.beginPage()
        var y = startY

        drawText("咖啡粉粒徑分析報告", x: margin, y: y, font: .boldSystemFont(ofSize: 20), color: .black)
        y += 28
        drawText("COFFEE GRIND PARTICLE SIZE ANALYSIS REPORT", x: margin, y: y, font: .systemFont(ofSize: 11), color: .darkGray)
        y += 36

        let lineHeight: CGFloat = 18
        y = drawKeyValueRow("報告日期", reportDateString, y: y, lineHeight: lineHeight)
        y = drawKeyValueRow("器具 (Brew device)", profileName, y: y, lineHeight: lineHeight)
        y = drawKeyValueRow("參照物 (Reference)", coinName, y: y, lineHeight: lineHeight)
        y = drawKeyValueRow(
            "分析模式",
            stats.mode == .calibrated ? "絕對粒徑（µm，硬幣校正）" : "相對粒徑（像素）",
            y: y,
            lineHeight: lineHeight
        )
        y += 8
        drawText("校正 / 量測說明", x: margin, y: y, font: .boldSystemFont(ofSize: 11), color: .black)
        y += 16
        y = drawWrappedText(calibrationText, x: margin, y: y, width: contentWidth, font: .systemFont(ofSize: 10), color: .darkGray)
        y += 20
        return y
    }

    private static func drawOverlaySection(ctx: UIGraphicsPDFRendererContext, startY: CGFloat, image: UIImage) -> CGFloat {
        var y = startY
        drawText("辨識結果示意", x: margin, y: y, font: .boldSystemFont(ofSize: 12), color: .black)
        y += 18
        let maxH: CGFloat = 200
        let scale = min(contentWidth / image.size.width, maxH / image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        let imgRect = CGRect(x: margin, y: y, width: w, height: h)
        image.draw(in: imgRect)
        y = imgRect.maxY + 12
        drawText("圖例：藍＝細粉　綠＝目標區　紅＝粗粉　黃圈＝硬幣參照", x: margin, y: y, font: .systemFont(ofSize: 8), color: .darkGray)
        y += 20
        return y
    }

    private static func drawStatsTable(ctx: UIGraphicsPDFRendererContext, startY: CGFloat, stats: AnalysisStats) -> CGFloat {
        var y = startY
        drawText("一、統計結果摘要", x: margin, y: y, font: .boldSystemFont(ofSize: 13), color: .black)
        y += 22

        let rows: [(String, String)] = [
            ("顆粒數 (N)", "\(stats.particleCount)"),
            ("均勻度 Score", "\(stats.uniformityScore)"),
            ("平均粒徑", String(format: "%.2f %@", stats.mean, stats.unitLabel)),
            ("標準差 σ", String(format: "%.2f %@", stats.std, stats.unitLabel)),
            ("變異係數 CV", String(format: "%.4f", stats.cv)),
            ("D10", String(format: "%.2f %@", stats.d10, stats.unitLabel)),
            ("D50", String(format: "%.2f %@", stats.d50, stats.unitLabel)),
            ("D90", String(format: "%.2f %@", stats.d90, stats.unitLabel))
        ]
        y = drawTwoColumnTable(ctx: ctx, rows: rows, startY: y)
        y += 16
        return y
    }

    private static func drawDistributionSection(ctx: UIGraphicsPDFRendererContext, startY: CGFloat, stats: AnalysisStats) -> CGFloat {
        var y = startY
        drawText("二、粒徑分佈（依器具區間）", x: margin, y: y, font: .boldSystemFont(ofSize: 13), color: .black)
        y += 22
        let rows: [(String, String)] = [
            ("細粉比例", String(format: "%.2f %%", stats.fineRatio * 100)),
            ("目標區比例", String(format: "%.2f %%", stats.targetRatio * 100)),
            ("粗粉比例", String(format: "%.2f %%", stats.coarseRatio * 100)),
            ("雙峰特徵", stats.bimodal ? "觀察到雙峰傾向" : "未顯著雙峰")
        ]
        y = drawTwoColumnTable(ctx: ctx, rows: rows, startY: y)
        y += 16
        return y
    }

    private static func drawTwoColumnTable(
        ctx: UIGraphicsPDFRendererContext,
        rows: [(String, String)],
        startY: CGFloat
    ) -> CGFloat {
        var y = startY
        let colW = contentWidth * 0.42
        let rowH: CGFloat = 20
        for (k, v) in rows {
            drawText(k, x: margin, y: y, font: .systemFont(ofSize: 10), color: .black)
            drawText(v, x: margin + colW + 8, y: y, font: .systemFont(ofSize: 10), color: .darkGray)
            y += rowH
        }
        return y
    }

    private static func drawHistogram(ctx: UIGraphicsPDFRendererContext, startY: CGFloat, bins: [HistogramBin]) -> CGFloat {
        var y = startY
        drawText("三、粒徑分佈直方圖 (0–1000 µm)", x: margin, y: y, font: .boldSystemFont(ofSize: 13), color: .black)
        y += 22

        let plotH: CGFloat = 120
        let plotW = contentWidth
        let maxC = max(bins.map(\.count).max() ?? 1, 1)

        let cg = ctx.cgContext
        cg.setStrokeColor(UIColor.lightGray.cgColor)
        cg.setLineWidth(0.5)
        cg.stroke(CGRect(x: margin, y: y, width: plotW, height: plotH))

        let n = CGFloat(bins.count)
        let barW = plotW / n
        for (i, bin) in bins.enumerated() {
            let h = CGFloat(bin.count) / CGFloat(maxC) * (plotH - 4)
            let x = margin + CGFloat(i) * barW + 0.5
            let barRect = CGRect(x: x, y: y + plotH - h, width: max(0.5, barW - 1), height: h)
            UIColor.systemBlue.withAlphaComponent(0.35).setFill()
            cg.fill(barRect)
        }
        y += plotH + 24
        return y
    }

    private static func drawParagraph(
        ctx: UIGraphicsPDFRendererContext,
        startY: CGFloat,
        title: String,
        body: String,
        fontSize: CGFloat
    ) -> CGFloat {
        var y = startY
        drawText(title, x: margin, y: y, font: .boldSystemFont(ofSize: 12), color: .black)
        y += 18
        y = drawWrappedText(body, x: margin, y: y, width: contentWidth, font: .systemFont(ofSize: fontSize), color: .darkGray)
        y += 16
        return y
    }

    private static func drawParticleTable(
        ctx: UIGraphicsPDFRendererContext,
        startY: CGFloat,
        diameters: [Double],
        unit: String,
        startIndex: Int
    ) -> CGFloat {
        var y = startY
        drawText("顆粒明細（等效直徑）", x: margin, y: y, font: .boldSystemFont(ofSize: 13), color: .black)
        y += 22
        drawText("序號", x: margin, y: y, font: .boldSystemFont(ofSize: 9), color: .black)
        drawText("等效直徑 (\(unit))", x: margin + 120, y: y, font: .boldSystemFont(ofSize: 9), color: .black)
        y += 16
        for (i, d) in diameters.enumerated() {
            drawText("\(startIndex + i + 1)", x: margin, y: y, font: .systemFont(ofSize: 9), color: .darkGray)
            drawText(String(format: "%.2f", d), x: margin + 120, y: y, font: .systemFont(ofSize: 9), color: .darkGray)
            y += 14
        }
        return y
    }

    private static func drawFooter(ctx: UIGraphicsPDFRendererContext, pageIndex: Int, extraLine: String?) {
        let disclaimer =
            "本報告由 GrindScale 影像分析產生，數值受拍攝光線、對焦與校正影響，僅供研磨參考，不作為商業或法規認證依據。"
        let footTop = pageRect.height - margin - 36
        drawText(disclaimer, x: margin, y: footTop, font: .systemFont(ofSize: 7), color: .gray, maxWidth: contentWidth - 72)
        if let extra = extraLine {
            drawText(extra, x: margin, y: footTop + 12, font: .systemFont(ofSize: 7), color: .gray, maxWidth: contentWidth - 72)
        }
        let pageStr = "第 \(pageIndex) 頁"
        drawText(pageStr, x: pageRect.width - margin - 52, y: footTop, font: .systemFont(ofSize: 8), color: .darkGray)
    }

    private static func drawKeyValueRow(_ key: String, _ value: String, y: CGFloat, lineHeight: CGFloat) -> CGFloat {
        drawText("\(key)：", x: margin, y: y, font: .boldSystemFont(ofSize: 10), color: .black)
        let nextY = drawWrappedText(value, x: margin + 118, y: y, width: contentWidth - 118, font: .systemFont(ofSize: 10), color: .darkGray)
        return max(y + lineHeight, nextY)
    }

    private static func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        font: UIFont,
        color: UIColor,
        maxWidth: CGFloat? = nil
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let s = text as NSString
        if let w = maxWidth {
            let r = CGRect(x: x, y: y, width: w, height: 800)
            s.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        } else {
            s.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    private static func drawWrappedText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let s = text as NSString
        let r = CGRect(x: x, y: y, width: width, height: 10_000)
        let rect = s.boundingRect(
            with: r.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        s.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        return y + ceil(rect.height) + 4
    }
}
