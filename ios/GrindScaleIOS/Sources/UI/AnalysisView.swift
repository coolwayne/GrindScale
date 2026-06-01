import AVFoundation
import AVKit
import Charts
import SwiftUI

struct AnalysisView: View {
    @ObservedObject var vm: ContentViewModel
    var onBackToHome: () -> Void

    @State private var showCamera = false

    var body: some View {
        ZStack {
            CoffeeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sessionSummarySection

                    Text("拍攝建議：只拍白紙區域，將咖啡粉與硬幣都放在同一張白紙上，避免陽光直射。")
                        .font(.subheadline)
                        .foregroundStyle(Color.black.opacity(0.58))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("沖煮：\(vm.selectedProfile.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CoffeeTheme.labelBlack)
                        Picker("參照物", selection: $vm.selectedCoin) {
                            ForEach(CoinReferences.all) { coin in
                                Text(coin.name).tag(coin)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(CoffeeTheme.labelBlack)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(CoffeeTheme.card)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CoffeeTheme.cardStroke, lineWidth: 1))
                    )

                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                        }
                        .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.amber))

                        LibraryPicker(image: $vm.selectedImage)
                    }

                    if let image = vm.selectedImage {
                        ROIImageEditor(
                            image: image,
                            roi: $vm.coinROINormalized
                        )
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Text("手動硬幣 ROI：只在框內找硬幣")
                                .font(.footnote)
                                .foregroundStyle(Color.black.opacity(0.58))
                            Spacer()
                            Button("清除 ROI") {
                                vm.coinROINormalized = nil
                            }
                            .font(.footnote)
                            .foregroundStyle(CoffeeTheme.labelBlack)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(CoffeeTheme.card)
                            .frame(height: 220)
                            .overlay(Text("尚未選擇照片").foregroundStyle(Color.black.opacity(0.58)))
                    }

                    Button {
                        vm.analyzeImage()
                    } label: {
                        if vm.isAnalyzing {
                            ProgressView()
                                .tint(CoffeeTheme.labelBlack)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("開始分析")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.card))
                    .disabled(vm.selectedImage == nil || vm.isAnalyzing)

                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }

                    if let stats = vm.stats {
                        statsSection(stats: stats)
                        Text(vm.calibrationText)
                            .font(.footnote)
                            .foregroundStyle(Color.black.opacity(0.58))
                        Text("建議：\(vm.recommendation)")
                            .font(.body)
                            .foregroundStyle(CoffeeTheme.labelBlack)
                        if !vm.histogram.isEmpty {
                            histogramSection
                        } else if !vm.histogramMetaText.isEmpty {
                            Text(vm.histogramMetaText)
                                .font(.footnote)
                                .foregroundStyle(Color.black.opacity(0.58))
                        }
                        if !vm.particleDiameters.isEmpty {
                            particleDetailsSection
                        }

                        if let overlay = vm.overlayImage {
                            Image(uiImage: overlay)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Button {
                                vm.saveOverlayImage()
                            } label: {
                                Label("下載辨識照片", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.amber.opacity(0.35)))
                            Text("藍: 細粉 / 綠: 適合 / 紅: 粗粉")
                                .font(.footnote)
                                .foregroundStyle(Color.black.opacity(0.58))
                        }

                        HStack(spacing: 12) {
                            Button {
                                vm.exportCSVReport()
                            } label: {
                                Label("匯出 Excel (CSV)", systemImage: "tablecells")
                            }
                            .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.amber.opacity(0.30)))

                            Button {
                                vm.exportPDFReport()
                            } label: {
                                Label("匯出 PDF 報告", systemImage: "doc.richtext")
                            }
                            .buttonStyle(CoffeeProminentButtonStyle(fill: CoffeeTheme.amber.opacity(0.30)))
                        }
                        Text("Excel：UTF-8 CSV；PDF：粒徑分析報告。")
                            .font(.footnote)
                            .foregroundStyle(Color.black.opacity(0.58))
                    }

                    DisclosureGroup("硬幣偵測候選（除錯）") {
                        coinCandidateDebugSectionContent
                    }
                    .tint(CoffeeTheme.labelBlack)

                    Text(vm.qualityText)
                        .font(.footnote)
                        .foregroundStyle(Color.black.opacity(0.58))

                    if !vm.history.isEmpty {
                        historySection
                    }
                }
                .padding(20)
            }

            if vm.isAnalyzing {
                AnalysisLoadingOverlay(progress: vm.analysisProgress)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.isAnalyzing)
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CoffeeTheme.background, for: .navigationBar)
        .coffeeNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBackToHome()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("首頁")
                    }
                    .foregroundStyle(CoffeeTheme.labelBlack)
                }
                .disabled(vm.isAnalyzing)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $vm.selectedImage)
        }
        .sheet(item: $vm.exportDocument) { doc in
            ActivityShareView(activityItems: [doc.url])
        }
        .alert(
            "匯出",
            isPresented: Binding(
                get: { vm.exportErrorMessage != nil },
                set: { if !$0 { vm.exportErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { vm.exportErrorMessage = nil }
        } message: {
            Text(vm.exportErrorMessage ?? "")
        }
        .alert(
            "下載結果",
            isPresented: Binding(
                get: { vm.saveResultMessage != nil },
                set: { if !$0 { vm.saveResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                vm.saveResultMessage = nil
            }
        } message: {
            Text(vm.saveResultMessage ?? "")
        }
    }

    private var sessionSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本次沖煮設定")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.58))
            Text("\(vm.selectedProfile.name) · \(vm.roastLevel.label)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CoffeeTheme.labelBlack)
            if !vm.beanDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("豆種：\(vm.beanDescription)")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.58))
            }
            if !vm.grinderDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("磨豆機：\(vm.grinderDescription)")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CoffeeTheme.card.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoffeeTheme.cardStroke, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func statsSection(stats: AnalysisStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分析結果")
                .font(.title3.weight(.bold))
                .foregroundStyle(CoffeeTheme.labelBlack)
            HStack {
                metric("Score", "\(stats.uniformityScore)")
                metric("顆粒數", "\(stats.particleCount)")
                metric("CV", String(format: "%.3f", stats.cv))
            }
            HStack {
                metric("細粉", String(format: "%.1f%%", stats.fineRatio * 100))
                metric("目標", String(format: "%.1f%%", stats.targetRatio * 100))
                metric("粗粉", String(format: "%.1f%%", stats.coarseRatio * 100))
            }
            HStack {
                metric("D10", String(format: "%.0f %@", stats.d10, stats.unitLabel))
                metric("D50", String(format: "%.0f %@", stats.d50, stats.unitLabel))
                metric("D90", String(format: "%.0f %@", stats.d90, stats.unitLabel))
            }
        }
    }

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("粒徑分佈曲線（0–1000 µm）")
                .font(.headline)
                .foregroundStyle(CoffeeTheme.labelBlack)
            Chart(vm.histogram) { bin in
                let center = (bin.start + bin.end) / 2.0
                AreaMark(
                    x: .value("Diameter", center),
                    y: .value("Count", bin.count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(CoffeeTheme.accent.opacity(0.2))

                LineMark(
                    x: .value("Diameter", center),
                    y: .value("Count", bin.count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(CoffeeTheme.amber)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
            }
            .id(vm.chartRevision)
            .frame(height: 220)
            .chartXScale(domain: 0...1000)
            .chartXAxis {
                AxisMarks(values: .stride(by: 200)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .foregroundStyle(CoffeeTheme.labelBlack)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)")
                                .foregroundStyle(CoffeeTheme.labelBlack)
                        } else if let d = value.as(Double.self) {
                            Text("\(Int(d))")
                                .foregroundStyle(CoffeeTheme.labelBlack)
                        }
                    }
                }
            }
            .chartXAxisLabel("粒徑 (µm)")
            .chartYAxisLabel("顆粒數")
            if !vm.histogramMetaText.isEmpty {
                Text(vm.histogramMetaText)
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.58))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CoffeeTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(CoffeeTheme.cardStroke, lineWidth: 1))
        )
    }

    private var particleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("顆粒尺寸明細")
                .font(.headline)
                .foregroundStyle(CoffeeTheme.labelBlack)
            Text("共辨識 \(vm.particleDiameters.count) 顆（等效直徑）")
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.58))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.particleDiameters.enumerated()), id: \.offset) { index, value in
                        Text(String(format: "#%d  %.1f %@", index + 1, value, vm.particleDiameterUnit))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CoffeeTheme.labelBlack)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(8)
            .background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var coinCandidateDebugSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("左側色塊與圖上圈圈同色；★ 為演算法自動選出；黃色為最終校正圈。")
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.58))

            if vm.coinCandidates.isEmpty {
                Text("尚無候選資料，請先畫 ROI 再按「開始分析」。")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.58))
            } else {
                ForEach(vm.coinCandidates) { candidate in
                    let mark = candidate.selected ? "★" : " "
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(CoinCandidatePalette.swiftUIColor(rank: candidate.rank, selected: candidate.selected))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                        Text(
                            String(
                                format: "%@ #%d  delta %.0f  面積 %.0f  直徑 %.1f px  分 %.2f",
                                mark,
                                candidate.rank,
                                candidate.circularity,
                                candidate.area,
                                candidate.support,
                                candidate.score
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CoffeeTheme.labelBlack)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近分析紀錄")
                .font(.headline)
                .foregroundStyle(CoffeeTheme.labelBlack)
            ForEach(vm.history.prefix(5)) { item in
                HStack {
                    Text(item.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.5))
                    Spacer()
                    Text(item.profileName)
                        .font(.caption)
                        .foregroundStyle(CoffeeTheme.labelBlack)
                    Text(item.mode == .calibrated ? "校正" : "相對")
                        .font(.caption2)
                        .foregroundStyle(CoffeeTheme.labelBlack)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CoffeeTheme.card, in: Capsule())
                    Text("Score \(item.score)")
                        .font(.caption)
                        .foregroundStyle(CoffeeTheme.labelBlack)
                    Text("CV \(String(format: "%.3f", item.cv))")
                        .font(.caption)
                        .foregroundStyle(CoffeeTheme.labelBlack)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value)
                .font(.headline)
                .foregroundStyle(CoffeeTheme.labelBlack)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(CoffeeTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CoffeeTheme.cardStroke.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - 分析中覆蓋層（循環影片）

private struct LoopingAnalysisVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        context.coordinator.looper = looper
        context.coordinator.queue = queue

        let vc = AVPlayerViewController()
        vc.player = queue
        vc.showsPlaybackControls = false
        // 橫向影片放在方框內：用填滿裁切避免 letterbox 上下黑邊。
        vc.videoGravity = .resizeAspectFill
        vc.view.backgroundColor = .white
        queue.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        coordinator.looper = nil
        coordinator.queue = nil
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var queue: AVQueuePlayer?
    }
}

private struct AnalysisLoadingOverlay: View {
    let progress: Double

    /// 0~30% / 31~70% / 71~100% 對應不同說明（與進度條百分比一致）。
    private var phaseDetailText: String {
        if progress <= 0.30 {
            return "正在辨識顆粒並計算粒徑分布"
        }
        if progress <= 0.70 {
            return "正在分析數據"
        }
        return "正在撰寫Excel跟專業報告"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Group {
                    if let url = Bundle.main.url(forResource: "AnalysisLoadingLoop", withExtension: "mp4") {
                        ZStack {
                            Color.white
                            LoopingAnalysisVideoPlayer(url: url)
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(CoffeeTheme.labelBlack)
                    }
                }

                Text("專業分析報告需要慢工出細活")
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CoffeeTheme.labelBlack)

                Text(phaseDetailText)
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: phaseDetailText)

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(CoffeeTheme.labelBlack)
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CoffeeTheme.labelBlack)
                }
                .frame(maxWidth: 260)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 16, y: 6)
            )
            .padding(24)
        }
    }
}

private struct ROIImageEditor: View {
    let image: UIImage
    @Binding var roi: CGRect?
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let canvas = proxy.size
            let imageRect = fittedRect(imageSize: image.size, canvasSize: canvas)
            ZStack {
                CoffeeTheme.card
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: canvas.width, height: canvas.height)

                if let roi {
                    let rect = rectFromNormalized(roi, in: imageRect)
                    Path { p in
                        p.addRect(rect)
                    }
                    .stroke(Color.yellow, lineWidth: 2.5)
                    .background(
                        Rectangle()
                            .path(in: rect)
                            .fill(Color.yellow.opacity(0.08))
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = clamped(value.location, to: imageRect)
                        if dragStart == nil { dragStart = p }
                        guard let s = dragStart else { return }
                        let drawRect = CGRect(
                            x: min(s.x, p.x),
                            y: min(s.y, p.y),
                            width: abs(s.x - p.x),
                            height: abs(s.y - p.y)
                        )
                        if drawRect.width > 6, drawRect.height > 6 {
                            roi = normalizedRect(from: drawRect, in: imageRect)
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
        }
    }

    private func fittedRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: canvasSize) }
        let imageAspect = imageSize.width / imageSize.height
        let canvasAspect = canvasSize.width / max(canvasSize.height, 1)
        if imageAspect > canvasAspect {
            let w = canvasSize.width
            let h = w / imageAspect
            return CGRect(x: 0, y: (canvasSize.height - h) * 0.5, width: w, height: h)
        } else {
            let h = canvasSize.height
            let w = h * imageAspect
            return CGRect(x: (canvasSize.width - w) * 0.5, y: 0, width: w, height: h)
        }
    }

    private func clamped(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(p.x, rect.minX), rect.maxX),
            y: min(max(p.y, rect.minY), rect.maxY)
        )
    }

    private func normalizedRect(from rect: CGRect, in imageRect: CGRect) -> CGRect {
        let x = (rect.minX - imageRect.minX) / max(imageRect.width, 1)
        let y = (rect.minY - imageRect.minY) / max(imageRect.height, 1)
        let w = rect.width / max(imageRect.width, 1)
        let h = rect.height / max(imageRect.height, 1)
        return CGRect(x: max(0, min(1, x)), y: max(0, min(1, y)), width: max(0.01, min(1, w)), height: max(0.01, min(1, h)))
    }

    private func rectFromNormalized(_ roi: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + roi.minX * imageRect.width,
            y: imageRect.minY + roi.minY * imageRect.height,
            width: roi.width * imageRect.width,
            height: roi.height * imageRect.height
        )
    }
}
