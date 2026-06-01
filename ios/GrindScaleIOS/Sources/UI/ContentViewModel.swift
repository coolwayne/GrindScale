import Foundation
import SwiftUI
import UIKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedProfile: BrewProfile = Profiles.all[0]
    @Published var selectedCoin: CoinReference = CoinReferences.all[0]
    /// 選填：豆種描述（可自填）
    @Published var beanDescription: String = ""
    @Published var roastLevel: RoastLevel = .medium
    /// 選填：磨豆機型號
    @Published var grinderDescription: String = ""
    /// 分析進度 0...1（時間模擬緩升，完成時至 100%）
    @Published var analysisProgress: Double = 0
    @Published var selectedImage: UIImage?
    @Published var coinROINormalized: CGRect?
    @Published var overlayImage: UIImage?
    @Published var stats: AnalysisStats?
    @Published var recommendation: String = ""
    @Published var qualityText: String = "尚未分析"
    @Published var calibrationText: String = "相對模式（未校正）"
    @Published var histogram: [HistogramBin] = []
    @Published var histogramMetaText: String = ""
    @Published var chartRevision: Int = 0
    @Published var particleDiameters: [Double] = []
    @Published var particleDiameterUnit: String = "px"
    @Published var coinCandidates: [CoinCandidateDebug] = []
    @Published var history: [AnalysisHistoryRecord] = []
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var saveResultMessage: String?
    /// 非 nil 時以 sheet 開啟系統分享（Excel CSV / PDF）。
    @Published var exportDocument: ExportDocument?
    @Published var exportErrorMessage: String?
    private let historyStore = HistoryStore()
    private var imageSaver: ImageSaver?
    private var analysisProgressTimer: Timer?
    private var analysisProgressStart: Date?

    /// 分析目標時長（秒），進度條先線性緩升至約 92%，之後極慢爬升以免長時間看起來像卡死；完成時直接至 100%。
    private let analysisProgressTargetSeconds: TimeInterval = 240

    init() {
        history = historyStore.load()
    }

    func analyzeImage() {
        guard let image = selectedImage else {
            errorMessage = "請先選擇或拍攝照片。"
            return
        }
        let normalizedImage = Self.normalizedImage(image)
        selectedImage = normalizedImage
        let profile = selectedProfile
        let coin = selectedCoin
        let coinROI = coinROINormalized
        errorMessage = nil
        isAnalyzing = true
        analysisProgress = 0.02
        startAnalysisProgressTimer()

        DispatchQueue.global(qos: .userInitiated).async {
            let analyzer = GrindAnalyzer()
            let quality = analyzer.checkQuality(normalizedImage)
            let result = analyzer.analyze(
                normalizedImage,
                profile: profile,
                referenceDiameterMM: coin.diameterMM,
                coinROINormalized: coinROI
            )

            if coin.diameterMM != nil && result.stats.mode != .calibrated {
                DispatchQueue.main.async {
                    self.stopAnalysisProgressTimer(finishedSuccessfully: false)
                    self.errorMessage = "未偵測到硬幣，無法輸出 0-1000um 分布。請將硬幣完整放在白紙上並重拍。"
                    self.stats = nil
                    self.overlayImage = nil
                    self.recommendation = ""
                    self.calibrationText = "校正失敗"
                    self.histogram = []
                    self.histogramMetaText = ""
                    self.particleDiameters = []
                    self.particleDiameterUnit = "px"
                    self.coinCandidates = result.coinCandidates
                    self.isAnalyzing = false
                }
                return
            }

            let overlay = analyzer.overlayImage(
                base: normalizedImage,
                particles: result.particles,
                analyzedWidth: result.analyzedWidth,
                analyzedHeight: result.analyzedHeight,
                coinMarker: result.coinMarker,
                coinCandidateOverlays: result.coinCandidateOverlays
            )
            let recommendation = RecommendationService.text(for: result.stats, profileName: profile.name)
            let histogramResult = Self.makeHistogram(diameters: result.diameters, mode: result.stats.mode)

            DispatchQueue.main.async {
                self.stopAnalysisProgressTimer(finishedSuccessfully: true)
                self.stats = result.stats
                self.overlayImage = overlay
                self.recommendation = recommendation
                self.calibrationText = result.calibrationText
                self.histogram = histogramResult.bins
                self.histogramMetaText = histogramResult.meta
                self.chartRevision += 1
                self.particleDiameters = result.diameters.sorted()
                self.particleDiameterUnit = result.stats.unitLabel
                self.coinCandidates = result.coinCandidates
                self.qualityText = String(
                    format: "亮度 %.1f / 對比 %.1f / 覆蓋率 %.3f %@",
                    quality.brightness,
                    quality.contrast,
                    quality.occupancy,
                    quality.pass ? "（品質通過）" : "（建議重拍）"
                )
                let record = AnalysisHistoryRecord(
                    id: UUID(),
                    timestamp: Date(),
                    profileName: profile.name,
                    mode: result.stats.mode,
                    score: result.stats.uniformityScore,
                    particleCount: result.stats.particleCount,
                    cv: result.stats.cv
                )
                self.historyStore.save(record: record)
                self.history = self.historyStore.load()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isAnalyzing = false
                    self.analysisProgress = 0
                }
            }
        }
    }

    private func startAnalysisProgressTimer() {
        analysisProgressTimer?.invalidate()
        analysisProgressStart = Date()
        let target = analysisProgressTargetSeconds
        analysisProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let start = self.analysisProgressStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                let linear = elapsed / target
                if linear <= 0.92 {
                    self.analysisProgress = min(0.92, max(0.02, linear))
                } else {
                    // 超過約 3 分 40 秒後不再停在 92%，改為極慢爬升（最多約 99%），等實際完成再跳到 100%
                    let overrun = elapsed - target * 0.92
                    let extra = min(0.07, overrun / 2_000)
                    self.analysisProgress = min(0.99, 0.92 + extra)
                }
            }
        }
        if let t = analysisProgressTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func stopAnalysisProgressTimer(finishedSuccessfully: Bool) {
        analysisProgressTimer?.invalidate()
        analysisProgressTimer = nil
        analysisProgressStart = nil
        if finishedSuccessfully {
            withAnimation(.easeOut(duration: 0.35)) {
                analysisProgress = 1.0
            }
        } else {
            analysisProgress = 0
        }
    }

    func exportCSVReport() {
        guard let stats else {
            exportErrorMessage = "請先完成分析再匯出。"
            return
        }
        let data = ReportExportService.makeCSV(
            stats: stats,
            profileName: selectedProfile.name,
            coinName: selectedCoin.name,
            calibrationText: calibrationText,
            recommendation: recommendation,
            histogram: histogram,
            histogramMetaText: histogramMetaText,
            particleDiameters: particleDiameters,
            particleDiameterUnit: particleDiameterUnit,
            reportDate: Date()
        )
        let url = tempExportURL(suffix: "csv")
        do {
            try data.write(to: url, options: .atomic)
            exportDocument = ExportDocument(url: url)
        } catch {
            exportErrorMessage = "匯出失敗：\(error.localizedDescription)"
        }
    }

    func exportPDFReport() {
        guard let stats else {
            exportErrorMessage = "請先完成分析再匯出。"
            return
        }
        let data = ReportExportService.makePDF(
            stats: stats,
            profileName: selectedProfile.name,
            coinName: selectedCoin.name,
            calibrationText: calibrationText,
            recommendation: recommendation,
            histogram: histogram,
            histogramMetaText: histogramMetaText,
            particleDiameters: particleDiameters,
            particleDiameterUnit: particleDiameterUnit,
            reportDate: Date(),
            overlayImage: overlayImage
        )
        let url = tempExportURL(suffix: "pdf")
        do {
            try data.write(to: url, options: .atomic)
            exportDocument = ExportDocument(url: url)
        } catch {
            exportErrorMessage = "匯出失敗：\(error.localizedDescription)"
        }
    }

    private func tempExportURL(suffix: String) -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd_HHmmss"
        let name = "GrindScale_粒徑報告_\(df.string(from: Date())).\(suffix)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func saveOverlayImage() {
        guard let image = overlayImage else {
            saveResultMessage = "沒有可下載的辨識結果圖片。"
            return
        }
        imageSaver = ImageSaver { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.saveResultMessage = "儲存失敗：\(error.localizedDescription)"
                } else {
                    self?.saveResultMessage = "已儲存辨識圖片到相簿。"
                }
                self?.imageSaver = nil
            }
        }
        imageSaver?.writeToPhotoAlbum(image: image)
    }

    nonisolated private static func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    nonisolated private static func makeHistogram(
        diameters: [Double],
        mode: AnalysisMode
    ) -> (bins: [HistogramBin], meta: String) {
        if mode != .calibrated {
            return ([], "需要硬幣校正後才顯示 0-1000um 曲線")
        }

        if mode == .calibrated {
            let minValue = 0.0
            let maxValue = 1000.0
            let binsCount = 40  // 25 um per bin for better sensitivity
            let step = (maxValue - minValue) / Double(binsCount)
            var buckets = Array(repeating: 0, count: binsCount)
            var underflow = 0
            var overflow = 0
            for d in diameters {
                if d < minValue {
                    underflow += 1
                    continue
                }
                if d > maxValue {
                    overflow += 1
                    continue
                }
                let idx = min(binsCount - 1, max(0, Int((d - minValue) / step)))
                buckets[idx] += 1
            }
            let bins = (0..<binsCount).map { i in
                let start = minValue + Double(i) * step
                let end = start + step
                return HistogramBin(start: start, end: end, count: buckets[i])
            }
            let minD = diameters.min() ?? 0
            let maxD = diameters.max() ?? 0
            let meta = String(
                format: "顆粒總數 %d | 範圍外: <0um %d, >1000um %d | 本次最小/最大: %.1f / %.1f um",
                diameters.count,
                underflow,
                overflow,
                minD,
                maxD
            )
            return (bins, meta)
        }

        return ([], "")
    }
}

struct ExportDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private final class ImageSaver: NSObject {
    private let completion: (Error?) -> Void

    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }

    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveCompleted(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        completion(error)
    }
}
