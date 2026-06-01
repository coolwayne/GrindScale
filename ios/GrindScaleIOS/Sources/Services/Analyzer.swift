import Foundation
import CoreGraphics
import UIKit

final class GrindAnalyzer {
    struct QualityReport {
        let pass: Bool
        let brightness: Double
        let occupancy: Double
        let contrast: Double
    }

    private struct CoinCandidate {
        let diameterPx: Double
        let score: Double
    }

    private struct CoinSelectionResult {
        let component: [Int]?
        let diagnostics: [CoinCandidateDebug]
        let overlays: [CoinCandidateOverlay]
    }

    private struct CoinComponentFeature {
        let component: [Int]
        let center: CGPoint
        let diameter: Double
        let circularity: Double
        let ratio: Double
        let fill: Double
        let radial: Double
        let contrastToPaper: Double
    }

    private struct CircleScanCandidate {
        let center: CGPoint
        let radius: Double
        let score: Double
        let support: Double
        let contrast: Double
    }

    /// 過小連通塊多為熱雜訊或紙紋；略提高下限以減少紙面細點誤判。
    private let minArea = 8

    /// 硬幣徑向量測略偏小時，統一略放大（疊圖、抑制區、µm 校正一致）。
    private let coinDiameterScale = 1.035

    private func effectiveCoinDiameterPx(diameterPx: Double, seedDiameter: Double, capFactor: Double) -> Double {
        min(diameterPx, seedDiameter * capFactor) * coinDiameterScale
    }
    private let maxArea = 160_000

    func checkQuality(_ image: UIImage) -> QualityReport {
        guard let gray = ImageProcessing.grayscale(image, maxDimension: 720) else {
            return QualityReport(pass: false, brightness: 0, occupancy: 0, contrast: 0)
        }

        let brightness = gray.pixels.reduce(0.0) { $0 + Double($1) } / Double(gray.pixels.count)
        let mean = brightness
        let variance = gray.pixels.reduce(0.0) { partial, px in
            let d = Double(px) - mean
            return partial + (d * d)
        } / Double(gray.pixels.count)
        let contrast = sqrt(variance)
        let threshold = ImageProcessing.otsuThreshold(gray)
        let mask = ImageProcessing.binaryMask(gray, threshold: threshold)
        let occupancy = Double(mask.reduce(0) { $0 + Int($1) }) / Double(mask.count)

        let pass = brightness >= 40 && brightness <= 220 && contrast >= 20 && occupancy > 0.02
        return QualityReport(pass: pass, brightness: brightness, occupancy: occupancy, contrast: contrast)
    }

    func analyze(_ image: UIImage, profile: BrewProfile) -> AnalysisResult {
        analyze(image, profile: profile, referenceDiameterMM: nil, coinROINormalized: nil)
    }

    func analyze(
        _ image: UIImage,
        profile: BrewProfile,
        referenceDiameterMM: Double?,
        coinROINormalized: CGRect? = nil
    ) -> AnalysisResult {
        guard let gray = ImageProcessing.grayscale(image) else {
            return AnalysisResult(
                stats: emptyStats,
                particles: [],
                diameters: [],
                calibrationText: "影像讀取失敗",
                analyzedWidth: 0,
                analyzedHeight: 0,
                coinMarker: nil,
                coinCandidates: [],
                coinCandidateOverlays: []
            )
        }
        // 不預先 blur：避免邊緣被抹開後二值化變「胖」；去噪改由遮罩形態學處理。
        let blurred = ImageProcessing.boxBlur(gray, radius: 0)
        // 略提高 gain，讓較大／對比略弱之粗顆粒在正規化後仍易與紙面區隔。
        let normalized = localContrastNormalize(gray: blurred, backgroundRadius: 8, gain: 1.52)
        let gradient = gradientMagnitude(gray: normalized)
        let gradientBase = gradientMagnitude(gray: blurred)
        let globalOtsu = ImageProcessing.otsuThreshold(blurred)
        let paperMask = detectPaperMask(gray: blurred)
        let meanPaper = meanIntensity(gray: blurred, mask: paperMask)
        let stdPaper = stdIntensity(gray: blurred, mask: paperMask, mean: meanPaper)
        let coinROI = coinROINormalized.map { normalizedRectToPixelRect($0, width: gray.width, height: gray.height) }
        let objectMask = makeObjectMask(gray: blurred, paperMask: paperMask, meanPaper: meanPaper)
        var particleMask = buildParticleMaskRobust(
            gray: blurred,
            normalized: normalized,
            paperMask: paperMask,
            meanPaper: meanPaper,
            stdPaper: stdPaper,
            globalOtsu: globalOtsu
        )
        let umPerPx = estimateUmPerPx(
            gray: blurred,
            paperMask: paperMask,
            meanPaper: meanPaper,
            objectMask: objectMask,
            referenceDiameterMM: referenceDiameterMM,
            coinROI: coinROI
        )
        let coinSelection = detectCoinComponentForSuppression(
            gray: blurred,
            paperMask: paperMask,
            meanPaper: meanPaper,
            objectMask: objectMask,
            width: gray.width,
            height: gray.height,
            coinROI: coinROI
        )
        let coinComponent = coinSelection.component
        let coinGeometry = coinComponent.map {
            coinGeometryFromComponent(
                component: $0,
                gray: blurred,
                paperMask: paperMask,
                meanPaper: meanPaper,
                width: gray.width,
                height: gray.height,
                coinROI: coinROI
            )
        }
        let coinMarker = coinGeometry.map {
            let displayDiameter = effectiveCoinDiameterPx(
                diameterPx: $0.diameterPx,
                seedDiameter: $0.seedDiameter,
                capFactor: 1.20
            )
            return CoinMarker(center: $0.center, radius: CGFloat(displayDiameter * 0.5))
        }
        if let coinComponent {
            var appliedCoinSuppression = false
            var suppressDiameter: Double?
            if let coinGeometry {
                let d = effectiveCoinDiameterPx(
                    diameterPx: coinGeometry.diameterPx,
                    seedDiameter: coinGeometry.seedDiameter,
                    capFactor: 1.20
                )
                let suppressArea = Double.pi * pow(d * 0.56, 2)
                let imageArea = Double(gray.width * gray.height)
                if suppressArea / max(1.0, imageArea) <= 0.22 {
                    for idx in coinComponent {
                        particleMask[idx] = 0
                    }
                    suppressDiameter = d
                    appliedCoinSuppression = true
                }
            }
            if appliedCoinSuppression, let coinGeometry, let suppressDiameter {
                suppressCircularRegion(
                    mask: &particleMask,
                    width: gray.width,
                    height: gray.height,
                    center: coinGeometry.center,
                    radius: suppressDiameter * 0.56
                )
            }
        }
        var components = connectedComponents(
            mask: particleMask,
            width: gray.width,
            height: gray.height,
            minArea: minArea,
            maxArea: maxArea
        )
        if components.isEmpty {
            // Fallback: recover from aggressive white-paper segmentation.
            let fallbackThreshold = UInt8(max(6, Int(ImageProcessing.otsuThreshold(blurred)) - 24))
            var fallbackMask = ImageProcessing.binaryMask(blurred, threshold: fallbackThreshold)
            for i in 0..<fallbackMask.count where paperMask[i] == 0 {
                fallbackMask[i] = 0
            }
            if let coinComponent {
                var appliedCoinSuppression = false
                var suppressDiameter: Double?
                if let coinGeometry {
                    let d = effectiveCoinDiameterPx(
                        diameterPx: coinGeometry.diameterPx,
                        seedDiameter: coinGeometry.seedDiameter,
                        capFactor: 1.20
                    )
                    let suppressArea = Double.pi * pow(d * 0.56, 2)
                    let imageArea = Double(gray.width * gray.height)
                    if suppressArea / max(1.0, imageArea) <= 0.22 {
                        for idx in coinComponent {
                            fallbackMask[idx] = 0
                        }
                        suppressDiameter = d
                        appliedCoinSuppression = true
                    }
                }
                if appliedCoinSuppression, let coinGeometry, let suppressDiameter {
                    suppressCircularRegion(
                        mask: &fallbackMask,
                        width: gray.width,
                        height: gray.height,
                        center: coinGeometry.center,
                        radius: suppressDiameter * 0.56
                    )
                }
            }
            components = connectedComponents(
                mask: fallbackMask,
                width: gray.width,
                height: gray.height,
                minArea: minArea,
                maxArea: maxArea
            )
        }
        if !components.isEmpty {
            components = splitTouchingComponents(
                components: components,
                width: gray.width,
                height: gray.height
            )
            components = components.filter {
                isLikelyParticle(
                    component: $0,
                    gray: normalized,
                    gradient: gradient,
                    width: gray.width,
                    height: gray.height,
                    meanPaper: meanPaper,
                    grayBase: blurred,
                    gradientBase: gradientBase
                )
            }
        }
        guard !components.isEmpty else {
            let emptyMode: AnalysisMode = umPerPx == nil ? .relative : .calibrated
            return AnalysisResult(
                stats: emptyStats(mode: emptyMode),
                particles: [],
                diameters: [],
                calibrationText: calibrationText(umPerPx: umPerPx, requested: referenceDiameterMM != nil),
                analyzedWidth: gray.width,
                analyzedHeight: gray.height,
                coinMarker: coinMarker,
                coinCandidates: coinSelection.diagnostics,
                coinCandidateOverlays: coinSelection.overlays
            )
        }

        // 等效圓直徑略減：二值邊界仍偏外 + 像素量化，乘係數貼近實體量測。
        let diametersPx = components.map { component -> Double in
            equivalentDiskDiameterPx(pixelCount: component.count)
        }
        let sorted = diametersPx.sorted()
        let thresholds = relativeThresholds(diametersSorted: sorted, profile: profile)

        var centers: [CGPoint] = []
        var radii: [CGFloat] = []
        var diametersUM: [Double?] = []
        var classes: [ParticleClass] = []
        var diametersOutput: [Double] = []
        centers.reserveCapacity(components.count)
        radii.reserveCapacity(components.count)
        diametersUM.reserveCapacity(components.count)
        classes.reserveCapacity(components.count)

        for (idx, component) in components.enumerated() {
            let dPx = diametersPx[idx]
            let dUM = umPerPx.map { dPx * $0 }
            var kind = classify(
                diameterPx: dPx,
                diameterUM: dUM,
                profile: profile,
                thresholds: thresholds
            )
            // Coarse grounds can be irregular; downgrade streak-like artifacts.
            if kind == .coarse {
                let roundness = circularity(component: component, width: gray.width, height: gray.height)
                let ratio = aspectRatioScore(component: component, width: gray.width)
                let fill = boundingBoxFillRatio(component: component, width: gray.width)
                if roundness < 0.07 && ratio < 0.11 {
                    kind = .target
                } else if isLikelyAgglomeratedFineCluster(
                    circularity: roundness,
                    bboxFill: fill,
                    aspectRatio: ratio
                ) {
                    // 多顆細粉黏成一團：等效直徑大但輪廓破碎／框內不緻密，不當成單顆粗粉。
                    kind = .target
                }
            }
            classes.append(kind)

            var sx = 0.0
            var sy = 0.0
            for pixelIndex in component {
                let y = pixelIndex / gray.width
                let x = pixelIndex % gray.width
                sx += Double(x)
                sy += Double(y)
            }
            let cx = sx / Double(component.count)
            let cy = sy / Double(component.count)
            diametersOutput.append(dUM ?? dPx)
            centers.append(CGPoint(x: cx, y: cy))
            // Display radius is intentionally capped for visual reliability.
            radii.append(CGFloat(max(2.0, min(14.0, dPx * 0.35))))
            diametersUM.append(dUM)
        }

        var particles: [Particle] = []
        particles.reserveCapacity(components.count)
        for i in 0..<components.count {
            let contour = contourPointsForComponent(
                component: components[i],
                width: gray.width,
                height: gray.height
            )
            particles.append(
                Particle(
                    center: centers[i],
                    radius: radii[i],
                    diameterPx: diametersPx[i],
                    diameterUM: diametersUM[i],
                    kind: classes[i],
                    contour: contour
                )
            )
        }

        let mode: AnalysisMode = umPerPx == nil ? .relative : .calibrated
        let stats = buildStats(diameters: diametersOutput, classes: classes, mode: mode)
        return AnalysisResult(
            stats: stats,
            particles: particles,
            diameters: diametersOutput,
            calibrationText: calibrationText(umPerPx: umPerPx, requested: referenceDiameterMM != nil),
            analyzedWidth: gray.width,
            analyzedHeight: gray.height,
            coinMarker: coinMarker,
            coinCandidates: coinSelection.diagnostics,
            coinCandidateOverlays: coinSelection.overlays
        )
    }

    func overlayImage(
        base: UIImage,
        particles: [Particle],
        analyzedWidth: Int,
        analyzedHeight: Int,
        coinMarker: CoinMarker?,
        coinCandidateOverlays: [CoinCandidateOverlay]
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = base.scale
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { context in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            let cg = context.cgContext
            let sx = base.size.width / CGFloat(max(analyzedWidth, 1))
            let sy = base.size.height / CGFloat(max(analyzedHeight, 1))
            cg.setLineWidth(1.5)

            // 先畫顆粒，再畫候選圈圈與黃色最終硬幣，否則顆粒點會覆蓋掉彩色候選圈。
            for particle in particles {
                // fill() 使用 fill color；先前只設 stroke，輪廓全變成預設黑色。
                let particleColor = color(for: particle.kind).cgColor
                cg.setFillColor(particleColor)
                cg.setStrokeColor(particleColor)
                if !particle.contour.isEmpty {
                    // Draw irregular contour points for more faithful particle visualization.
                    for p in particle.contour {
                        let x = p.x * sx
                        let y = p.y * sy
                        cg.fill(CGRect(x: x, y: y, width: max(1.0, sx), height: max(1.0, sy)))
                    }
                } else {
                    let rect = CGRect(
                        x: particle.center.x * sx - particle.radius * sx,
                        y: particle.center.y * sy - particle.radius * sy,
                        width: particle.radius * 2 * sx,
                        height: particle.radius * 2 * sy
                    )
                    cg.strokeEllipse(in: rect)
                }
            }

            for candidate in coinCandidateOverlays {
                let rank = max(1, min(20, candidate.rank))
                let color = CoinCandidatePalette.uiColor(rank: rank, selected: candidate.selected)
                let radiusX = candidate.radius * sx
                let radiusY = candidate.radius * sy
                let rect = CGRect(
                    x: candidate.center.x * sx - radiusX,
                    y: candidate.center.y * sy - radiusY,
                    width: radiusX * 2,
                    height: radiusY * 2
                )
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(candidate.selected ? 4.0 : 2.5)
                cg.strokeEllipse(in: rect)
            }
            cg.setLineWidth(1.5)

            if let coinMarker {
                let radiusX = coinMarker.radius * sx
                let radiusY = coinMarker.radius * sy
                let rect = CGRect(
                    x: coinMarker.center.x * sx - radiusX,
                    y: coinMarker.center.y * sy - radiusY,
                    width: radiusX * 2,
                    height: radiusY * 2
                )
                cg.setStrokeColor(UIColor.systemYellow.cgColor)
                cg.setLineWidth(3.5)
                cg.strokeEllipse(in: rect)
                cg.setLineWidth(1.5)
            }
        }
    }

    private var emptyStats: AnalysisStats { emptyStats(mode: .relative) }

    private func emptyStats(mode: AnalysisMode) -> AnalysisStats {
        AnalysisStats(
            particleCount: 0,
            mean: 0,
            std: 0,
            cv: 0,
            d10: 0,
            d50: 0,
            d90: 0,
            fineRatio: 0,
            targetRatio: 0,
            coarseRatio: 0,
            bimodal: false,
            uniformityScore: 0,
            mode: mode,
            unitLabel: mode == .calibrated ? "um" : "px"
        )
    }

    /// 連通塊面積對應等效圓直徑（px）；係數依使用者指定縮至與實體接近。
    private func equivalentDiskDiameterPx(pixelCount: Int) -> Double {
        let area = max(1.0, Double(pixelCount))
        let d = 2.0 * sqrt(area / Double.pi)
        return max(1.0, d * 0.4)
    }

    private func classify(
        diameterPx: Double,
        diameterUM: Double?,
        profile: BrewProfile,
        thresholds: (fineMax: Double, coarseMin: Double)
    ) -> ParticleClass {
        if let diameterUM {
            if diameterUM < profile.fineThresholdUM { return .fine }
            if diameterUM > profile.coarseThresholdUM { return .coarse }
            return .target
        }

        if diameterPx < thresholds.fineMax { return .fine }
        if diameterPx > thresholds.coarseMin { return .coarse }
        return .target
    }

    /// 細粉黏連成團時，等效直徑偏大但常見：圓度低、邊界崎嶇、在包圍盒內填滿率偏低（與單顆實心粗粉不同）。
    private func isLikelyAgglomeratedFineCluster(
        circularity: Double,
        bboxFill: Double,
        aspectRatio: Double
    ) -> Bool {
        if circularity < 0.36 && bboxFill < 0.34 { return true }
        if circularity < 0.30 && bboxFill < 0.42 { return true }
        if circularity < 0.42 && bboxFill < 0.26 { return true }
        if aspectRatio < 0.34 && circularity < 0.22 && bboxFill < 0.40 { return true }
        return false
    }

    private func relativeThresholds(diametersSorted: [Double], profile: BrewProfile) -> (fineMax: Double, coarseMin: Double) {
        guard !diametersSorted.isEmpty else { return (0.0, Double.greatestFiniteMagnitude) }
        let p25 = percentile(diametersSorted, 0.25)
        let p50 = percentile(diametersSorted, 0.50)
        let p85 = percentile(diametersSorted, 0.85)

        // Keep "fine" conservative to avoid over-blue on noisy edges.
        let fineMax = min(p50 * profile.relativeFineRatio, p25 * 0.95)
        // Relax relative coarse threshold so coarse samples can still be recognized without calibration.
        var coarseMin = max(p50 * profile.relativeCoarseRatio, p85 * 1.03)
        if coarseMin <= fineMax {
            coarseMin = fineMax * 1.25
        }
        return (fineMax, coarseMin)
    }

    private func buildStats(diameters: [Double], classes: [ParticleClass], mode: AnalysisMode) -> AnalysisStats {
        guard !diameters.isEmpty else { return emptyStats(mode: mode) }
        let n = Double(diameters.count)
        let mean = diameters.reduce(0, +) / n
        let variance = diameters.reduce(0.0) { partial, d in
            let x = d - mean
            return partial + x * x
        } / n
        let std = sqrt(variance)
        let cv = mean > 0 ? std / mean : 0

        let fine = Double(classes.filter { $0 == .fine }.count) / n
        let target = Double(classes.filter { $0 == .target }.count) / n
        let coarse = Double(classes.filter { $0 == .coarse }.count) / n

        let bimodal = isBimodal(diameters: diameters)
        let cvPenalty = min(45.0, cv * 180.0)
        let outlierPenalty = min(45.0, (fine + coarse) * 90.0)
        let bimodalPenalty = bimodal ? 12.0 : 0.0
        let score = max(0, min(100, Int(round(100.0 - cvPenalty - outlierPenalty - bimodalPenalty))))

        let sorted = diameters.sorted()
        return AnalysisStats(
            particleCount: diameters.count,
            mean: mean,
            std: std,
            cv: cv,
            d10: percentile(sorted, 0.10),
            d50: percentile(sorted, 0.50),
            d90: percentile(sorted, 0.90),
            fineRatio: fine,
            targetRatio: target,
            coarseRatio: coarse,
            bimodal: bimodal,
            uniformityScore: score,
            mode: mode,
            unitLabel: mode == .calibrated ? "um" : "px"
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int(round(Double(sorted.count - 1) * p))))
        return sorted[index]
    }

    private func isBimodal(diameters: [Double]) -> Bool {
        if diameters.count < 40 { return false }
        guard let minValue = diameters.min(), let maxValue = diameters.max(), maxValue > minValue else {
            return false
        }
        let bins = 24
        var hist = [Int](repeating: 0, count: bins)
        let step = (maxValue - minValue) / Double(bins)
        for d in diameters {
            let idx = min(bins - 1, Int((d - minValue) / max(step, 1e-6)))
            hist[idx] += 1
        }

        var peaks = 0
        let threshold = max(2, Int(Double(hist.max() ?? 0) * 0.2))
        for i in 1..<(bins - 1) {
            if hist[i] > hist[i - 1], hist[i] > hist[i + 1], hist[i] >= threshold {
                peaks += 1
            }
        }
        return peaks >= 2
    }

    private func connectedComponents(
        mask: [UInt8],
        width: Int,
        height: Int,
        minArea: Int,
        maxArea: Int
    ) -> [[Int]] {
        var visited = [Bool](repeating: false, count: mask.count)
        let neighbors = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
        var components: [[Int]] = []

        for index in 0..<mask.count {
            if visited[index] || mask[index] == 0 { continue }
            visited[index] = true
            var queue = [index]
            var head = 0
            var component: [Int] = []
            component.reserveCapacity(128)

            while head < queue.count {
                let current = queue[head]
                head += 1
                component.append(current)

                let y = current / width
                let x = current % width
                for (dy, dx) in neighbors {
                    let ny = y + dy
                    let nx = x + dx
                    if ny < 0 || ny >= height || nx < 0 || nx >= width { continue }
                    let ni = ny * width + nx
                    if visited[ni] || mask[ni] == 0 { continue }
                    visited[ni] = true
                    queue.append(ni)
                }
            }

            if component.count >= minArea && component.count <= maxArea {
                components.append(component)
            }
        }

        return components
    }

    private func splitTouchingComponents(
        components: [[Int]],
        width: Int,
        height: Int
    ) -> [[Int]] {
        var output: [[Int]] = []
        output.reserveCapacity(components.count)

        for component in components {
            let circScore = circularity(component: component, width: width, height: height)
            let ratioScore = aspectRatioScore(component: component, width: width)
            let fillRatio = boundingBoxFillRatio(component: component, width: width)

            // 極小塊：已是單顆。
            if component.count < 28 {
                output.append(component)
                continue
            }
            // 中小塊：若看起來是緻密單粒則不切；若圓度低／填滿低，多半是細粉黏連，仍送進切分。
            if component.count < 240 {
                if circScore >= 0.44 && fillRatio >= 0.33 {
                    output.append(component)
                    continue
                }
                // fall through — 嘗試分水嶺拆開
            }
            // 僅在「像單顆大粗粒」且緻密時才保留整塊；細粉堆成略圓的團仍會被送進切分。
            if component.count > 900 && component.count < 4_500 &&
                circScore > 0.68 && ratioScore > 0.74 && fillRatio > 0.43 {
                output.append(component)
                continue
            }

            guard let first = component.first else { continue }
            var minX = first % width
            var maxX = minX
            var minY = first / width
            var maxY = minY
            for idx in component {
                let x = idx % width
                let y = idx / width
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }

            let bw = maxX - minX + 1
            let bh = maxY - minY + 1
            if bw < 6 || bh < 6 {
                output.append(component)
                continue
            }

            let localCount = bw * bh
            var localMask = [UInt8](repeating: 0, count: localCount)
            for idx in component {
                let x = idx % width
                let y = idx / width
                let lx = x - minX
                let ly = y - minY
                localMask[ly * bw + lx] = 1
            }

            var dist = distanceTransform(mask: localMask, width: bw, height: bh)
            smoothDistanceMap(&dist, mask: localMask, width: bw, height: bh)
            let seeds = distanceSeeds(dist: dist, mask: localMask, width: bw, height: bh)
            if seeds.count <= 1 {
                // Fallback for touching coarse particles when distance seeds collapse into one peak.
                let fallbackGroups = splitLargeConnectedComponent(
                    component: component,
                    width: width,
                    height: height
                )
                if fallbackGroups.count > 1 {
                    output.append(contentsOf: recursivelySplitLargeGroups(
                        fallbackGroups,
                        width: width,
                        height: height,
                        depth: 1
                    ))
                    continue
                }
                output.append(component)
                continue
            }

            let groups = assignPixelsToSeeds(
                mask: localMask,
                width: bw,
                height: bh,
                seeds: seeds,
                minX: minX,
                minY: minY,
                imageWidth: width
            )
            if groups.count <= 1 {
                output.append(component)
                continue
            }
            output.append(contentsOf: recursivelySplitLargeGroups(
                groups,
                width: width,
                height: height,
                depth: 1
            ))
        }

        return output
    }

    private func distanceTransform(mask: [UInt8], width: Int, height: Int) -> [Double] {
        let inf = 1_000_000.0
        var dist = [Double](repeating: inf, count: mask.count)
        for i in 0..<mask.count where mask[i] == 0 {
            dist[i] = 0.0
        }

        let diag = sqrt(2.0)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                var best = dist[idx]
                if x > 0 { best = min(best, dist[idx - 1] + 1.0) }
                if y > 0 { best = min(best, dist[idx - width] + 1.0) }
                if x > 0 && y > 0 { best = min(best, dist[idx - width - 1] + diag) }
                if x + 1 < width && y > 0 { best = min(best, dist[idx - width + 1] + diag) }
                dist[idx] = best
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                var best = dist[idx]
                if x + 1 < width { best = min(best, dist[idx + 1] + 1.0) }
                if y + 1 < height { best = min(best, dist[idx + width] + 1.0) }
                if x + 1 < width && y + 1 < height { best = min(best, dist[idx + width + 1] + diag) }
                if x > 0 && y + 1 < height { best = min(best, dist[idx + width - 1] + diag) }
                dist[idx] = best
            }
        }
        return dist
    }

    private func smoothDistanceMap(_ dist: inout [Double], mask: [UInt8], width: Int, height: Int) {
        var out = dist
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                var sum = 0.0
                var count = 0.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let ny = y + dy
                        let nx = x + dx
                        if ny < 0 || ny >= height || nx < 0 || nx >= width { continue }
                        let ni = ny * width + nx
                        if mask[ni] == 0 { continue }
                        sum += dist[ni]
                        count += 1.0
                    }
                }
                out[idx] = count > 0 ? (sum / count) : dist[idx]
            }
        }
        dist = out
    }

    private func distanceSeeds(dist: [Double], mask: [UInt8], width: Int, height: Int) -> [(x: Int, y: Int)] {
        var maxDistance = 0.0
        for i in 0..<dist.count where mask[i] == 1 {
            if dist[i] > maxDistance { maxDistance = dist[i] }
        }
        if maxDistance < 0.95 { return [] }

        let minPeakValue = max(0.52, maxDistance * 0.11)
        let minSpacing = max(2, Int(maxDistance * 0.26))
        var candidates: [(x: Int, y: Int, score: Double)] = []

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                let center = dist[idx]
                if center < minPeakValue { continue }

                var isPeak = true
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nidx = (y + dy) * width + (x + dx)
                        if dist[nidx] > center {
                            isPeak = false
                            break
                        }
                    }
                    if !isPeak { break }
                }
                if isPeak {
                    candidates.append((x: x, y: y, score: center))
                }
            }
        }
        if candidates.isEmpty { return [] }

        candidates.sort { $0.score > $1.score }
        var seeds: [(x: Int, y: Int)] = []
        for c in candidates {
            var tooClose = false
            for seed in seeds {
                let dx = seed.x - c.x
                let dy = seed.y - c.y
                if (dx * dx + dy * dy) < (minSpacing * minSpacing) {
                    tooClose = true
                    break
                }
            }
            if !tooClose {
                seeds.append((x: c.x, y: c.y))
            }
            if seeds.count >= 36 { break }
        }
        return seeds
    }

    private func splitLargeConnectedComponent(component: [Int], width: Int, height: Int) -> [[Int]] {
        guard component.count >= 380 else { return [] }

        let circ = circularity(component: component, width: width, height: height)
        let ratio = aspectRatioScore(component: component, width: width)
        if ratio > 0.82 && circ > 0.56 {
            return []
        }

        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
        for idx in component {
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let bw = max(1, maxX - minX + 1)
        let bh = max(1, maxY - minY + 1)
        let longOverShort = Double(max(bw, bh)) / Double(min(bw, bh))
        let fill = boundingBoxFillRatio(component: component, width: width)
        if longOverShort < 1.18 {
            // 接近正方形的大塊：若為低圓度、框內填滿低的黏連細粉團，仍嘗試切開。
            if !(fill < 0.37 && circ < 0.36 && component.count >= 700) {
                return []
            }
        }
        if longOverShort < 1.28 && circ > 0.34 {
            return []
        }

        let splitByX = bw >= bh
        var c1 = splitByX ? Double(minX) : Double(minY)
        var c2 = splitByX ? Double(maxX) : Double(maxY)
        if abs(c2 - c1) < 8 { return [] }

        // 1D k-means split along the long axis for merged/touching coarse clusters.
        for _ in 0..<8 {
            var sum1 = 0.0
            var cnt1 = 0
            var sum2 = 0.0
            var cnt2 = 0
            for idx in component {
                let axis = splitByX ? Double(idx % width) : Double(idx / width)
                if abs(axis - c1) <= abs(axis - c2) {
                    sum1 += axis
                    cnt1 += 1
                } else {
                    sum2 += axis
                    cnt2 += 1
                }
            }
            if cnt1 == 0 || cnt2 == 0 { return [] }
            c1 = sum1 / Double(cnt1)
            c2 = sum2 / Double(cnt2)
        }

        if abs(c2 - c1) < 6 { return [] }

        var g1: [Int] = []
        var g2: [Int] = []
        g1.reserveCapacity(component.count / 2)
        g2.reserveCapacity(component.count / 2)
        for idx in component {
            let axis = splitByX ? Double(idx % width) : Double(idx / width)
            if abs(axis - c1) <= abs(axis - c2) {
                g1.append(idx)
            } else {
                g2.append(idx)
            }
        }

        if g1.count < minArea || g2.count < minArea {
            return []
        }
        return [g1, g2]
    }

    private func recursivelySplitLargeGroups(
        _ groups: [[Int]],
        width: Int,
        height: Int,
        depth: Int
    ) -> [[Int]] {
        if depth >= 2 { return groups }
        var result: [[Int]] = []
        result.reserveCapacity(groups.count)

        for group in groups {
            let extra = splitLargeConnectedComponentMulti(
                component: group,
                width: width,
                height: height
            )
            if extra.count > 1 {
                let refined = recursivelySplitLargeGroups(
                    extra,
                    width: width,
                    height: height,
                    depth: depth + 1
                )
                result.append(contentsOf: refined)
            } else {
                result.append(group)
            }
        }
        return result
    }

    private func splitLargeConnectedComponentMulti(component: [Int], width: Int, height: Int) -> [[Int]] {
        guard component.count >= 650 else { return [] }

        let circ = circularity(component: component, width: width, height: height)
        let ratio = aspectRatioScore(component: component, width: width)
        let fill = boundingBoxFillRatio(component: component, width: width)

        // Trigger only on shapes likely to be merged particles.
        let likelyMerged =
            circ < 0.22 ||
            fill < 0.26 ||
            (ratio < 0.58 && fill < 0.46) ||
            (circ < 0.38 && fill < 0.34) ||
            component.count > 9_000
        if !likelyMerged { return [] }

        var k = Int(round(Double(component.count) / 2_200.0))
        k = max(2, min(6, k))

        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(component.count)
        for idx in component {
            let x = Double(idx % width)
            let y = Double(idx / width)
            points.append((x: x, y: y))
        }
        guard points.count >= k else { return [] }

        var centers: [(x: Double, y: Double)] = []
        centers.reserveCapacity(k)
        centers.append(points[0])
        while centers.count < k {
            var bestPoint = points[0]
            var bestDist = -1.0
            for p in points {
                var nearest = Double.greatestFiniteMagnitude
                for c in centers {
                    let dx = p.x - c.x
                    let dy = p.y - c.y
                    let d2 = dx * dx + dy * dy
                    if d2 < nearest { nearest = d2 }
                }
                if nearest > bestDist {
                    bestDist = nearest
                    bestPoint = p
                }
            }
            centers.append(bestPoint)
        }

        var assignments = [Int](repeating: 0, count: points.count)
        for _ in 0..<10 {
            var sumX = [Double](repeating: 0.0, count: k)
            var sumY = [Double](repeating: 0.0, count: k)
            var cnt = [Int](repeating: 0, count: k)

            for i in 0..<points.count {
                let p = points[i]
                var best = 0
                var bestD = Double.greatestFiniteMagnitude
                for c in 0..<k {
                    let dx = p.x - centers[c].x
                    let dy = p.y - centers[c].y
                    let d2 = dx * dx + dy * dy
                    if d2 < bestD {
                        bestD = d2
                        best = c
                    }
                }
                assignments[i] = best
                sumX[best] += p.x
                sumY[best] += p.y
                cnt[best] += 1
            }

            var changed = false
            for c in 0..<k where cnt[c] > 0 {
                let nx = sumX[c] / Double(cnt[c])
                let ny = sumY[c] / Double(cnt[c])
                let dx = nx - centers[c].x
                let dy = ny - centers[c].y
                if (dx * dx + dy * dy) > 0.25 {
                    changed = true
                }
                centers[c] = (x: nx, y: ny)
            }
            if !changed { break }
        }

        var groups = Array(repeating: [Int](), count: k)
        for i in 0..<component.count {
            groups[assignments[i]].append(component[i])
        }

        let valid = groups.filter { $0.count >= minArea }
        guard valid.count >= 2 else { return [] }

        let largest = valid.map(\.count).max() ?? component.count
        if Double(largest) / Double(component.count) > 0.90 {
            return []
        }
        return valid
    }

    private func assignPixelsToSeeds(
        mask: [UInt8],
        width: Int,
        height: Int,
        seeds: [(x: Int, y: Int)],
        minX: Int,
        minY: Int,
        imageWidth: Int
    ) -> [[Int]] {
        var groups = Array(repeating: [Int](), count: seeds.count)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                var bestSeed = 0
                var bestScore = Int.max
                for i in 0..<seeds.count {
                    let dx = x - seeds[i].x
                    let dy = y - seeds[i].y
                    let score = dx * dx + dy * dy
                    if score < bestScore {
                        bestScore = score
                        bestSeed = i
                    }
                }
                let globalX = minX + x
                let globalY = minY + y
                groups[bestSeed].append(globalY * imageWidth + globalX)
            }
        }

        var filtered: [[Int]] = []
        filtered.reserveCapacity(groups.count)
        for group in groups {
            if group.count >= minArea {
                filtered.append(group)
            }
        }
        return filtered
    }

    private func detectPaperMask(gray: GrayImage) -> [UInt8] {
        let otsu = Int(ImageProcessing.otsuThreshold(gray))
        let threshold = UInt8(max(160, min(245, otsu + 18)))
        var brightMask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count {
            brightMask[i] = gray.pixels[i] >= threshold ? 1 : 0
        }

        let components = connectedComponents(
            mask: brightMask,
            width: gray.width,
            height: gray.height,
            minArea: max(1000, Int(Double(gray.pixels.count) * 0.12)),
            maxArea: gray.pixels.count
        )
        guard let paper = components.max(by: { $0.count < $1.count }) else {
            return [UInt8](repeating: 1, count: gray.pixels.count)
        }

        let coverage = Double(paper.count) / Double(gray.pixels.count)
        if coverage < 0.15 {
            return [UInt8](repeating: 1, count: gray.pixels.count)
        }

        var coarseMask = [UInt8](repeating: 0, count: gray.pixels.count)
        for idx in paper { coarseMask[idx] = 1 }
        let filled = fillHoles(mask: coarseMask, width: gray.width, height: gray.height)
        return filled
    }

    private func meanIntensity(gray: GrayImage, mask: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0
        for i in 0..<gray.pixels.count where mask[i] == 1 {
            sum += Double(gray.pixels[i])
            count += 1
        }
        guard count > 0 else { return 200.0 }
        return sum / Double(count)
    }

    private func stdIntensity(gray: GrayImage, mask: [UInt8], mean: Double) -> Double {
        var sum = 0.0
        var count = 0
        for i in 0..<gray.pixels.count where mask[i] == 1 {
            let diff = Double(gray.pixels[i]) - mean
            sum += diff * diff
            count += 1
        }
        guard count > 0 else { return 0.0 }
        return sqrt(sum / Double(count))
    }

    private func makeObjectMask(gray: GrayImage, paperMask: [UInt8], meanPaper: Double) -> [UInt8] {
        let threshold = UInt8(max(35, min(220, Int(meanPaper - 22))))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            mask[i] = gray.pixels[i] < threshold ? 1 : 0
        }
        return mask
    }

    private func makeParticleMask(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        stdPaper: Double,
        otsuThreshold: UInt8
    ) -> [UInt8] {
        let delta = max(7.0, min(40.0, stdPaper * 0.52))
        let adaptiveThreshold = UInt8(max(10, min(220, Int(meanPaper - delta))))
        let otsuSoft = UInt8(max(8, Int(otsuThreshold) - 20))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            let px = gray.pixels[i]
            // Union two cues: adaptive paper-relative + global Otsu-soft threshold.
            mask[i] = (px < adaptiveThreshold || px < otsuSoft) ? 1 : 0
        }
        return mask
    }

    private func makeParticleMaskFromNormalized(normalized: GrayImage, paperMask: [UInt8]) -> [UInt8] {
        let otsu = ImageProcessing.otsuThreshold(normalized)
        let threshold = UInt8(max(50, min(185, Int(otsu) - 12)))
        var mask = [UInt8](repeating: 0, count: normalized.pixels.count)
        for i in 0..<normalized.pixels.count where paperMask[i] == 1 {
            mask[i] = normalized.pixels[i] < threshold ? 1 : 0
        }
        return mask
    }

    private func makeParticleMaskFromContrast(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        stdPaper: Double
    ) -> [UInt8] {
        let contrastThreshold = max(8.0, min(38.0, stdPaper * 0.58))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            let contrast = meanPaper - Double(gray.pixels[i])
            mask[i] = contrast >= contrastThreshold ? 1 : 0
        }
        return mask
    }

    /// 極寬鬆對比，補抓與紙面差異小的咖啡像素（與主遮罩合併）。
    private func makeParticleMaskSupplemental(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        stdPaper: Double
    ) -> [UInt8] {
        let soft = max(2.28, min(16.0, 1.58 + stdPaper * 0.16))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            let diff = meanPaper - Double(gray.pixels[i])
            mask[i] = diff >= soft ? 1 : 0
        }
        return mask
    }

    /// 比 makeParticleMaskFromContrast 更寬鬆，專供 OR 合併。
    private func makeParticleMaskContrastLoose(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        stdPaper: Double
    ) -> [UInt8] {
        let t = max(5.0, min(29.0, 4.25 + stdPaper * 0.27))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            let contrast = meanPaper - Double(gray.pixels[i])
            mask[i] = contrast >= t ? 1 : 0
        }
        return mask
    }

    /// 全域 Otsu 略下修，補抓略暗於主閾值的顆粒。
    private func makeParticleMaskLooseOtsu(
        gray: GrayImage,
        paperMask: [UInt8],
        globalOtsu: UInt8
    ) -> [UInt8] {
        let thr = UInt8(max(6, min(235, Int(globalOtsu) - 14)))
        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            mask[i] = gray.pixels[i] < thr ? 1 : 0
        }
        return mask
    }

    private func buildParticleMaskRobust(
        gray: GrayImage,
        normalized: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        stdPaper: Double,
        globalOtsu: UInt8
    ) -> [UInt8] {
        let background = ImageProcessing.boxBlur(gray, radius: 8)
        var darknessPixels = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count {
            let d = max(0, Int(background.pixels[i]) - Int(gray.pixels[i]))
            darknessPixels[i] = UInt8(min(255, d))
        }
        let darkness = GrayImage(width: gray.width, height: gray.height, pixels: darknessPixels)
        let darkOtsu = ImageProcessing.otsuThreshold(darkness)
        let darkThreshold = UInt8(max(2, min(90, Int(Double(darkOtsu) * 0.53) + 1)))
        let contrastMin = max(1.5, min(16.0, 1.78 + stdPaper * 0.16))

        let absoluteThreshold = UInt8(max(4, Int(globalOtsu) - 22))

        var mask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            let darknessPass = darknessPixels[i] >= darkThreshold
            let diff = meanPaper - Double(gray.pixels[i])
            let absPass = gray.pixels[i] <= absoluteThreshold
            let darkContrast = darknessPass && diff >= contrastMin
            mask[i] = darkContrast || absPass ? 1 : 0
        }

        // 多通道 OR：不同閾值/對比正規化，減少單一條件漏掉的顆粒。
        let adaptive = makeParticleMask(
            gray: gray, paperMask: paperMask, meanPaper: meanPaper,
            stdPaper: stdPaper, otsuThreshold: globalOtsu
        )
        let supplemental = makeParticleMaskSupplemental(
            gray: gray, paperMask: paperMask, meanPaper: meanPaper, stdPaper: stdPaper
        )
        let normMask = makeParticleMaskFromNormalized(normalized: normalized, paperMask: paperMask)
        let contrastLoose = makeParticleMaskContrastLoose(
            gray: gray, paperMask: paperMask, meanPaper: meanPaper, stdPaper: stdPaper
        )
        let otsuLoose = makeParticleMaskLooseOtsu(gray: gray, paperMask: paperMask, globalOtsu: globalOtsu)
        var merged = mergeMasks(mask, adaptive)
        merged = mergeMasks(merged, supplemental)
        merged = mergeMasks(merged, normMask)
        merged = mergeMasks(merged, contrastLoose)
        merged = mergeMasks(merged, otsuLoose)
        // 不併入 ultraLoose：過寬易把相鄰顆粒橋接成一塊，顆粒「計數」反而變少。

        // 形態學 opening 後雙重膨脹：補回粗顆粒邊緣並維持鄰近連通。
        let opened = erode(merged, width: gray.width, height: gray.height, minNeighbors: 2)
        var recovered = dilate(opened, width: gray.width, height: gray.height, minNeighbors: 2)
        recovered = dilate(recovered, width: gray.width, height: gray.height, minNeighbors: 2)
        return recovered
    }

    private func detectCoinComponentForSuppression(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        objectMask: [UInt8],
        width: Int,
        height: Int,
        coinROI: CGRect?
    ) -> CoinSelectionResult {
        // ROI mode: user told us exactly where the coin is – just measure it directly.
        if let roi = coinROI {
            return detectCoinInROI(
                gray: gray, paperMask: paperMask, meanPaper: meanPaper,
                width: width, height: height, roi: roi
            )
        }
        return detectCoinFromAllCandidates(
            gray: gray, paperMask: paperMask, meanPaper: meanPaper,
            objectMask: objectMask, width: width, height: height
        )
    }

    private func detectCoinInROI(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        width: Int,
        height: Int,
        roi: CGRect
    ) -> CoinSelectionResult {
        let minX = max(0, Int(roi.minX))
        let maxX = min(width - 1, Int(roi.maxX))
        let minY = max(0, Int(roi.minY))
        let maxY = min(height - 1, Int(roi.maxY))
        guard minX < maxX, minY < maxY else {
            return CoinSelectionResult(component: nil, diagnostics: [], overlays: [])
        }
        let bw = maxX - minX + 1
        let bh = maxY - minY + 1

        // ROI mode: ignore paperMask – the user told us where the coin is.
        // 多組 delta：由亮到暗逐步「長大」連通塊；再以形狀＋輪廓梯度＋面積成長穩定度選最佳（呼應人工標註的 #3/#5 類中間閾值）。
        let deltas: [Double] = [4.0, 9.0, 16.0, 24.0, 33.0, 45.0, 60.0, 78.0, 105.0, 140.0]
        var results: [(delta: Double, area: Int, component: [Int])] = []

        for delta in deltas {
            let t = max(4.0, meanPaper - delta)
            var localMask = [UInt8](repeating: 0, count: bw * bh)
            for y in minY...maxY {
                for x in minX...maxX {
                    if Double(gray.pixels[y * width + x]) <= t {
                        localMask[(y - minY) * bw + (x - minX)] = 1
                    }
                }
            }
            let comps = connectedComponents(mask: localMask, width: bw, height: bh,
                                            minArea: 30, maxArea: bw * bh)
            guard let largest = comps.max(by: { $0.count < $1.count }) else { continue }
            let globalPixels = largest.map { px in
                let lx = px % bw + minX
                let ly = px / bw + minY
                return ly * width + lx
            }
            results.append((delta: delta, area: largest.count, component: globalPixels))
        }

        guard !results.isEmpty else {
            return CoinSelectionResult(component: nil, diagnostics: [], overlays: [])
        }

        let gradient = gradientMagnitude(gray: gray)
        var selectionScores: [Double] = []
        selectionScores.reserveCapacity(results.count)
        for (idx, result) in results.enumerated() {
            let feat = coinFeature(
                component: result.component, width: width, height: height,
                gray: gray, meanPaper: meanPaper
            )
            let edgeC = meanGradientOnContour(
                gradient: gradient, component: result.component, width: width, height: height
            )
            let s = scoreROICoinThresholdCandidate(
                feature: feat, edgeContour: edgeC, index: idx, results: results
            )
            selectionScores.append(s)
        }

        var autoSelectedIndex = selectionScores.enumerated()
            .max(by: { $0.element < $1.element })?
            .offset ?? (results.count - 1)

        // 分數皆偏低時，退回「面積突增前一步」啟發式，避免全壞圖時亂選。
        if let maxS = selectionScores.max(), maxS < 0.28, results.count >= 2 {
            var fallback = results.count - 1
            for i in 1..<results.count {
                let prevArea = Double(results[i - 1].area)
                let currArea = Double(results[i].area)
                let growthRatio = prevArea > 0 ? (currArea - prevArea) / prevArea : 10.0
                if growthRatio > 0.40 && prevArea >= 36 {
                    fallback = i - 1
                    break
                }
            }
            autoSelectedIndex = fallback
        }

        // Build diagnostics and overlays for each delta (up to 10) so the user can compare.
        var diagnostics: [CoinCandidateDebug] = []
        var overlays: [CoinCandidateOverlay] = []
        for (idx, result) in results.prefix(10).enumerated() {
            let comp = result.component
            var sx = 0.0, sy = 0.0
            for px in comp { sx += Double(px % width); sy += Double(px / width) }
            let center = CGPoint(x: sx / Double(comp.count), y: sy / Double(comp.count))
            let areaDiam = 2.0 * sqrt(Double(comp.count) / Double.pi)
            var cMinX = width, cMaxX = 0, cMinY = height, cMaxY = 0
            for px in comp {
                let x = px % width; let y = px / width
                if x < cMinX { cMinX = x }; if x > cMaxX { cMaxX = x }
                if y < cMinY { cMinY = y }; if y > cMaxY { cMaxY = y }
            }
            let spanDiam = (Double(cMaxX - cMinX + 1) + Double(cMaxY - cMinY + 1)) * 0.5
            let diam = areaDiam * 0.65 + spanDiam * 0.35
            let isSel = idx == autoSelectedIndex
            let rankScore = idx < selectionScores.count ? selectionScores[idx] : 0.0

            diagnostics.append(CoinCandidateDebug(
                rank: idx + 1, area: Double(comp.count),
                circularity: Double(result.delta),
                support: diam, score: rankScore, selected: isSel
            ))
            overlays.append(CoinCandidateOverlay(
                rank: idx + 1, center: center,
                radius: CGFloat(diam * 0.5), selected: isSel
            ))
        }

        let selectedComp = results[min(autoSelectedIndex, results.count - 1)].component
        return CoinSelectionResult(component: selectedComp, diagnostics: diagnostics, overlays: overlays)
    }

    private func detectCoinFromAllCandidates(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        objectMask: [UInt8],
        width: Int,
        height: Int
    ) -> CoinSelectionResult {
        let allComponents = collectCoinCandidateComponents(
            gray: gray, paperMask: paperMask, meanPaper: meanPaper,
            objectMask: objectMask, width: width, height: height
        )
        guard !allComponents.isEmpty else {
            return CoinSelectionResult(component: nil, diagnostics: [], overlays: [])
        }
        let features = allComponents.map {
            coinFeature(component: $0, width: width, height: height, gray: gray, meanPaper: meanPaper)
        }
        let areasSorted = features.map { Double($0.component.count) }.sorted()
        let medianArea = percentile(areasSorted, 0.50)
        let p90Area = percentile(areasSorted, 0.90)
        let minCoinArea = max(320.0, medianArea * 4.2, p90Area * 1.45)
        var filtered = features.filter { Double($0.component.count) >= minCoinArea }
        if filtered.isEmpty {
            filtered = Array(features.sorted { $0.component.count > $1.component.count }.prefix(3))
        }
        var best: CoinComponentFeature?
        var bestScore = -1.0
        var scoredRows: [(feature: CoinComponentFeature, support: Double, score: Double)] = []
        let maxArea = filtered.map { Double($0.component.count) }.max() ?? minCoinArea
        for feature in filtered {
            let support = coinSupportScore(target: feature, all: filtered)
            let areaScore = min(1.0, Double(feature.component.count) / max(maxArea, 1.0))
            let shapeScore = feature.circularity * 0.37 + feature.ratio * 0.18 +
                feature.fill * 0.08 + feature.radial * 0.22 +
                min(1.0, feature.contrastToPaper / 28.0) * 0.15
            let passesShape = feature.circularity >= 0.18 && feature.ratio >= 0.30 &&
                feature.radial >= 0.16 && feature.contrastToPaper >= 6.0
            let score = (support * 0.42 + areaScore * 0.38 + shapeScore * 0.20) * (passesShape ? 1.0 : 0.35)
            scoredRows.append((feature: feature, support: support, score: score))
            if passesShape && score > bestScore { bestScore = score; best = feature }
        }
        let selected = best ?? scoredRows.max(by: { $0.score < $1.score })?.feature
        let sc = selected?.center; let sd = selected?.diameter
        let topRows = scoredRows.sorted { $0.score > $1.score }
        let diagnostics = topRows.prefix(20).enumerated().map { idx, row -> CoinCandidateDebug in
            let isSel: Bool
            if let sc, let sd {
                let dx = Double(row.feature.center.x - sc.x); let dy = Double(row.feature.center.y - sc.y)
                isSel = sqrt(dx*dx+dy*dy) < 2 && abs(row.feature.diameter - sd) < 2
            } else { isSel = false }
            return CoinCandidateDebug(rank: idx+1, area: Double(row.feature.component.count),
                circularity: row.feature.circularity, support: row.support, score: row.score, selected: isSel)
        }
        let overlays = topRows.prefix(20).enumerated().map { idx, row -> CoinCandidateOverlay in
            let isSel: Bool
            if let sc, let sd {
                let dx = Double(row.feature.center.x - sc.x); let dy = Double(row.feature.center.y - sc.y)
                isSel = sqrt(dx*dx+dy*dy) < 2 && abs(row.feature.diameter - sd) < 2
            } else { isSel = false }
            return CoinCandidateOverlay(rank: idx+1, center: row.feature.center,
                radius: CGFloat(row.feature.diameter * 0.5), selected: isSel)
        }
        return CoinSelectionResult(component: selected?.component, diagnostics: diagnostics, overlays: overlays)
    }

    private func collectCoinCandidateComponents(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        objectMask: [UInt8],
        width: Int,
        height: Int
    ) -> [[Int]] {
        var masks: [[UInt8]] = [objectMask]
        for delta in [2.0, 4.0, 6.0, 10.0, 16.0, 24.0, 36.0] {
            let t = UInt8(max(6, min(245, Int(meanPaper - delta))))
            var darkMask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                darkMask[i] = gray.pixels[i] < t ? 1 : 0
            }
            masks.append(darkMask)

            var deviationMask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                let dev = abs(Double(gray.pixels[i]) - meanPaper)
                deviationMask[i] = dev >= delta ? 1 : 0
            }
            masks.append(deviationMask)
        }

        // Gradient-based edge candidate: useful when coin interior is low-contrast but boundary exists.
        let grad = gradientMagnitude(gray: gray)
        var gradVals: [Double] = []
        gradVals.reserveCapacity(gray.pixels.count / 4)
        for i in 0..<grad.count where paperMask[i] == 1 {
            gradVals.append(grad[i])
        }
        if !gradVals.isEmpty {
            let meanG = gradVals.reduce(0.0, +) / Double(gradVals.count)
            let varG = gradVals.reduce(0.0) { acc, g in
                let d = g - meanG
                return acc + d * d
            } / Double(gradVals.count)
            let stdG = sqrt(varG)
            let edgeThreshold = max(5.0, meanG + stdG * 0.85)
            var edgeMask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<grad.count where paperMask[i] == 1 {
                edgeMask[i] = grad[i] >= edgeThreshold ? 1 : 0
            }
            edgeMask = dilate(edgeMask, width: width, height: height, minNeighbors: 1)
            edgeMask = dilate(edgeMask, width: width, height: height, minNeighbors: 1)
            var edgeFilled = fillHoles(mask: edgeMask, width: width, height: height)
            // Keep only paper region and remove image border to avoid filling the whole paper.
            for x in 0..<width {
                edgeFilled[x] = 0
                edgeFilled[(height - 1) * width + x] = 0
            }
            for y in 0..<height {
                edgeFilled[y * width] = 0
                edgeFilled[y * width + (width - 1)] = 0
            }
            for i in 0..<edgeFilled.count where paperMask[i] == 0 {
                edgeFilled[i] = 0
            }
            masks.append(edgeFilled)
        }

        let minArea = max(80, Int(Double(gray.pixels.count) * 0.00015))
        let maxArea = Int(Double(gray.pixels.count) * 0.85)
        var allComponents: [[Int]] = []
        allComponents.reserveCapacity(120)
        for mask in masks {
            let comps = connectedComponents(
                mask: mask,
                width: width,
                height: height,
                minArea: minArea,
                maxArea: maxArea
            )
            allComponents.append(contentsOf: comps)
        }
        return allComponents
    }

    private func detectCoinByCircleScan(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        width: Int,
        height: Int,
        coinROI: CGRect?
    ) -> CircleScanCandidate? {
        let gradient = gradientMagnitude(gray: gray)
        var centers: [CGPoint] = []
        centers.reserveCapacity(16)

        // Candidate centers from loose dark regions (coin is dark).
        let darkThreshold = UInt8(max(6, min(245, Int(meanPaper - 4.0))))
        var darkMask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            darkMask[i] = gray.pixels[i] < darkThreshold ? 1 : 0
        }
        let darkComps = connectedComponents(
            mask: darkMask,
            width: width,
            height: height,
            minArea: max(120, Int(Double(gray.pixels.count) * 0.00018)),
            maxArea: Int(Double(gray.pixels.count) * 0.9)
        )
        for comp in darkComps.sorted(by: { $0.count > $1.count }).prefix(14) {
            var sx = 0.0
            var sy = 0.0
            for idx in comp {
                sx += Double(idx % width)
                sy += Double(idx / width)
            }
            let c = CGPoint(x: sx / Double(comp.count), y: sy / Double(comp.count))
            if let coinROI, !coinROI.contains(c) { continue }
            centers.append(c)
        }
        if centers.isEmpty, let coinROI {
            centers.append(CGPoint(x: coinROI.midX, y: coinROI.midY))
        }
        if centers.isEmpty { return nil }

        let minImageDim = Double(min(width, height))
        let minR = max(10.0, minImageDim * 0.03)
        let maxR = min(minImageDim * 0.42, max(28.0, minImageDim * 0.26))
        if maxR <= minR + 2 { return nil }

        var best: CircleScanCandidate?
        var bestScore = -1.0
        let samples = 72

        for center in centers {
            if let coinROI, !coinROI.contains(center) { continue }
            var r = minR
            while r <= maxR {
                var valid = 0
                var ringGrad = 0.0
                var insideI = 0.0
                var outsideI = 0.0
                var insideN = 0
                var outsideN = 0

                for k in 0..<samples {
                    let theta = 2.0 * Double.pi * Double(k) / Double(samples)
                    let ux = cos(theta)
                    let uy = sin(theta)

                    let rx = center.x + ux * r
                    let ry = center.y + uy * r
                    if rx < 1 || ry < 1 || rx >= Double(width - 1) || ry >= Double(height - 1) {
                        continue
                    }
                    let ridx = Int(ry) * width + Int(rx)
                    if paperMask[ridx] == 0 { continue }

                    valid += 1
                    ringGrad += gradient[ridx]

                    let ix = center.x + ux * (r * 0.70)
                    let iy = center.y + uy * (r * 0.70)
                    if ix >= 0, iy >= 0, ix < Double(width), iy < Double(height) {
                        let iidx = Int(iy) * width + Int(ix)
                        if paperMask[iidx] == 1 {
                            insideI += Double(gray.pixels[iidx])
                            insideN += 1
                        }
                    }

                    let ox = center.x + ux * (r * 1.18)
                    let oy = center.y + uy * (r * 1.18)
                    if ox >= 0, oy >= 0, ox < Double(width), oy < Double(height) {
                        let oidx = Int(oy) * width + Int(ox)
                        if paperMask[oidx] == 1 {
                            outsideI += Double(gray.pixels[oidx])
                            outsideN += 1
                        }
                    }
                }

                let support = Double(valid) / Double(samples)
                if support < 0.55 || insideN < 20 || outsideN < 20 {
                    r += 2.0
                    continue
                }
                let ringGradMean = ringGrad / Double(max(valid, 1))
                let insideMean = insideI / Double(max(insideN, 1))
                let outsideMean = outsideI / Double(max(outsideN, 1))
                let contrast = max(0.0, outsideMean - insideMean)
                let darkRatio = darkPixelRatioInCircle(
                    gray: gray,
                    paperMask: paperMask,
                    center: center,
                    radius: r * 0.72,
                    threshold: max(6.0, meanPaper - 8.0)
                )

                if support < 0.62 || contrast < 7.0 || darkRatio < 0.20 {
                    r += 2.0
                    continue
                }

                let score = min(1.0, ringGradMean / 24.0) * 0.42 +
                    min(1.0, contrast / 24.0) * 0.36 +
                    support * 0.12 +
                    min(1.0, darkRatio / 0.55) * 0.10
                if score > bestScore {
                    bestScore = score
                    best = CircleScanCandidate(
                        center: center,
                        radius: r,
                        score: score,
                        support: support,
                        contrast: contrast
                    )
                }
                r += 2.0
            }
        }

        guard let best else { return nil }
        if best.score < 0.34 { return nil }
        return best
    }

    private func componentFromCircle(
        center: CGPoint,
        radius: Double,
        width: Int,
        height: Int,
        paperMask: [UInt8]
    ) -> [Int] {
        let r = max(1.0, radius)
        let r2 = r * r
        let minX = max(0, Int(floor(center.x - r)))
        let maxX = min(width - 1, Int(ceil(center.x + r)))
        let minY = max(0, Int(floor(center.y - r)))
        let maxY = min(height - 1, Int(ceil(center.y + r)))
        if minX > maxX || minY > maxY { return [] }

        var out: [Int] = []
        out.reserveCapacity(Int(Double(maxX - minX + 1) * Double(maxY - minY + 1) * 0.65))
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                if dx * dx + dy * dy <= r2 {
                    let idx = y * width + x
                    if paperMask[idx] == 1 {
                        out.append(idx)
                    }
                }
            }
        }
        return out
    }

    private func normalizedRectToPixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        let x0 = max(0.0, min(1.0, rect.minX))
        let y0 = max(0.0, min(1.0, rect.minY))
        let x1 = max(0.0, min(1.0, rect.maxX))
        let y1 = max(0.0, min(1.0, rect.maxY))
        let minX = min(x0, x1) * Double(width)
        let minY = min(y0, y1) * Double(height)
        let maxX = max(x0, x1) * Double(width)
        let maxY = max(y0, y1) * Double(height)
        return CGRect(x: minX, y: minY, width: max(1.0, maxX - minX), height: max(1.0, maxY - minY))
    }

    private func componentInsideROI(_ component: [Int], width: Int, roi: CGRect) -> Bool {
        guard let first = component.first else { return false }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for idx in component {
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let box = CGRect(
            x: Double(minX),
            y: Double(minY),
            width: Double(max(1, maxX - minX + 1)),
            height: Double(max(1, maxY - minY + 1))
        )
        // Strict ROI mode: candidate must be mostly inside ROI.
        let inter = box.intersection(roi)
        if inter.isNull { return false }
        let interArea = max(0.0, inter.width * inter.height)
        let boxArea = max(1.0, box.width * box.height)
        let overlapRatio = interArea / boxArea
        let center = CGPoint(x: box.midX, y: box.midY)
        return overlapRatio >= 0.72 && roi.contains(center)
    }

    private func darkPixelRatioInCircle(
        gray: GrayImage,
        paperMask: [UInt8],
        center: CGPoint,
        radius: Double,
        threshold: Double
    ) -> Double {
        let r = max(1.0, radius)
        let r2 = r * r
        let minX = max(0, Int(floor(center.x - r)))
        let maxX = min(gray.width - 1, Int(ceil(center.x + r)))
        let minY = max(0, Int(floor(center.y - r)))
        let maxY = min(gray.height - 1, Int(ceil(center.y + r)))
        if minX > maxX || minY > maxY { return 0.0 }

        var dark = 0
        var total = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                if dx * dx + dy * dy > r2 { continue }
                let idx = y * gray.width + x
                if paperMask[idx] == 0 { continue }
                total += 1
                if Double(gray.pixels[idx]) <= threshold {
                    dark += 1
                }
            }
        }
        if total == 0 { return 0.0 }
        return Double(dark) / Double(total)
    }

    private func coinFeature(
        component: [Int],
        width: Int,
        height: Int,
        gray: GrayImage,
        meanPaper: Double
    ) -> CoinComponentFeature {
        var sx = 0.0
        var sy = 0.0
        for idx in component {
            sx += Double(idx % width)
            sy += Double(idx / width)
        }
        let center = CGPoint(
            x: sx / Double(max(1, component.count)),
            y: sy / Double(max(1, component.count))
        )
        let area = Double(component.count)
        let diameter = 2.0 * sqrt(area / Double.pi)
        return CoinComponentFeature(
            component: component,
            center: center,
            diameter: diameter,
            circularity: circularity(component: component, width: width, height: height),
            ratio: aspectRatioScore(component: component, width: width),
            fill: boundingBoxFillRatio(component: component, width: width),
            radial: radialConsistency(component: component, width: width, height: height, center: center),
            contrastToPaper: max(0.0, meanPaper - meanIntensityForComponent(gray: gray, component: component))
        )
    }

    private func radialConsistency(
        component: [Int],
        width: Int,
        height: Int,
        center: CGPoint
    ) -> Double {
        let contour = contourPointsForComponent(component: component, width: width, height: height)
        if contour.count < 12 { return 0.0 }
        var radii: [Double] = []
        radii.reserveCapacity(contour.count)
        for p in contour {
            let dx = Double(p.x) - center.x
            let dy = Double(p.y) - center.y
            radii.append(sqrt(dx * dx + dy * dy))
        }
        let meanR = radii.reduce(0.0, +) / Double(radii.count)
        if meanR <= 0 { return 0.0 }
        let variance = radii.reduce(0.0) { acc, r in
            let d = r - meanR
            return acc + d * d
        } / Double(radii.count)
        let stdR = sqrt(variance)
        return max(0.0, min(1.0, 1.0 - stdR / meanR))
    }

    private func coinSupportScore(target: CoinComponentFeature, all: [CoinComponentFeature]) -> Double {
        if all.isEmpty { return 0.0 }
        let distTol = max(8.0, target.diameter * 0.22)
        var support = 0
        for candidate in all {
            let dx = Double(candidate.center.x - target.center.x)
            let dy = Double(candidate.center.y - target.center.y)
            let distance = sqrt(dx * dx + dy * dy)
            let diameterRatio = candidate.diameter / max(target.diameter, 1.0)
            if distance <= distTol && diameterRatio >= 0.62 && diameterRatio <= 1.60 {
                support += 1
            }
        }
        return min(1.0, Double(support) / Double(max(1, all.count)))
    }

    private func largestCircularComponent(
        components: [[Int]],
        width: Int,
        height: Int,
        minCircularity: Double,
        minAspectRatio: Double
    ) -> [Int]? {
        var best: [Int]?
        var bestDiameter = 0.0
        for comp in components {
            let diameter = 2.0 * sqrt(Double(comp.count) / Double.pi)
            if diameter <= bestDiameter { continue }
            let circ = circularity(component: comp, width: width, height: height)
            let ratio = aspectRatioScore(component: comp, width: width)
            if circ < minCircularity || ratio < minAspectRatio { continue }
            bestDiameter = diameter
            best = comp
        }
        return best
    }

    private func dominantCoinComponent(
        components: [[Int]],
        width: Int,
        height: Int
    ) -> [Int]? {
        guard !components.isEmpty else { return nil }

        let diametersAll = components.map { 2.0 * sqrt(Double($0.count) / Double.pi) }.sorted()
        guard !diametersAll.isEmpty else { return nil }
        let medianD = percentile(diametersAll, 0.50)
        let p75 = percentile(diametersAll, 0.75)
        let p90 = percentile(diametersAll, 0.90)
        // Coin should be much larger than coffee particles.
        let minDominantD = max(26.0, medianD * 2.4, p75 * 1.7, p90 * 1.15)

        var best: [Int]?
        var bestScore = -1.0
        for comp in components {
            let diameter = 2.0 * sqrt(Double(comp.count) / Double.pi)
            if diameter < minDominantD { continue }

            let circ = circularity(component: comp, width: width, height: height)
            let ratio = aspectRatioScore(component: comp, width: width)
            let fill = boundingBoxFillRatio(component: comp, width: width)
            // Keep shape filter permissive for blurred coin edges.
            if circ < 0.12 || ratio < 0.35 { continue }

            let dominance = min(1.0, diameter / max(minDominantD, 1.0))
            let score = dominance * 0.65 + circ * 0.18 + ratio * 0.12 + fill * 0.05
            if score > bestScore {
                bestScore = score
                best = comp
            }
        }
        return best
    }

    private func mergeMasks(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var out = a
        for i in 0..<out.count {
            out[i] = (a[i] == 1 || b[i] == 1) ? 1 : 0
        }
        return out
    }

    private func cleanupParticleMask(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        let opened = erode(mask, width: width, height: height, minNeighbors: 2)
        let denoised = dilate(opened, width: width, height: height, minNeighbors: 4)
        let closed = dilate(denoised, width: width, height: height, minNeighbors: 5)
        return erode(closed, width: width, height: height, minNeighbors: 2)
    }

    private func erode(_ mask: [UInt8], width: Int, height: Int, minNeighbors: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: mask.count)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] == 0 { continue }
                var neighbors = 0
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let ny = y + dy
                        let nx = x + dx
                        if ny < 0 || ny >= height || nx < 0 || nx >= width { continue }
                        let ni = ny * width + nx
                        if mask[ni] == 1 { neighbors += 1 }
                    }
                }
                out[idx] = neighbors >= minNeighbors ? 1 : 0
            }
        }
        return out
    }

    private func dilate(_ mask: [UInt8], width: Int, height: Int, minNeighbors: Int) -> [UInt8] {
        var out = mask
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask[idx] == 1 { continue }
                var neighbors = 0
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let ny = y + dy
                        let nx = x + dx
                        if ny < 0 || ny >= height || nx < 0 || nx >= width { continue }
                        let ni = ny * width + nx
                        if mask[ni] == 1 { neighbors += 1 }
                    }
                }
                if neighbors >= minNeighbors {
                    out[idx] = 1
                }
            }
        }
        return out
    }

    private func localContrastNormalize(gray: GrayImage, backgroundRadius: Int, gain: Double) -> GrayImage {
        let bg = ImageProcessing.boxBlur(gray, radius: backgroundRadius)
        var out = gray.pixels
        for i in 0..<gray.pixels.count {
            let v = Double(gray.pixels[i])
            let b = Double(bg.pixels[i])
            let corrected = 128.0 + (v - b) * gain
            out[i] = UInt8(max(0, min(255, Int(corrected))))
        }
        return GrayImage(width: gray.width, height: gray.height, pixels: out)
    }

    private func gradientMagnitude(gray: GrayImage) -> [Double] {
        let w = gray.width
        let h = gray.height
        var out = [Double](repeating: 0.0, count: gray.pixels.count)
        if w < 3 || h < 3 { return out }
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let idx = y * w + x
                let gx = Int(gray.pixels[idx + 1]) - Int(gray.pixels[idx - 1])
                let gy = Int(gray.pixels[idx + w]) - Int(gray.pixels[idx - w])
                out[idx] = sqrt(Double(gx * gx + gy * gy))
            }
        }
        return out
    }

    private func boundingBoxExtent(component: [Int], width: Int) -> (w: Int, h: Int) {
        guard let first = component.first else { return (1, 1) }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for idx in component {
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        return (maxX - minX + 1, maxY - minY + 1)
    }

    /// 與白紙對比夠深、或表面紋理／梯度明顯 — 較可能是真咖啡（含不規則粗顆粒），不當紙紋／陰影濾掉。
    private func resemblesCoffeeGroundParticle(
        contrastBase: Double,
        stdBase: Double,
        edgeBase: Double,
        area: Int
    ) -> Bool {
        if contrastBase >= 40 { return true }
        if contrastBase >= 28 && stdBase >= 4.8 { return true }
        if contrastBase >= 24 && edgeBase >= 10.5 { return true }
        if area >= 90 && contrastBase >= 26 && stdBase >= 4.5 { return true }
        if area >= 140 && contrastBase >= 21 && stdBase >= 4.9 { return true }
        if area >= 200 && contrastBase >= 17 && stdBase >= 4.0 && edgeBase >= 7.5 { return true }
        return false
    }

    /// 大塊、填滿率較高之粗顆粒（對比未必極高），避免被紙紋／陰影規則誤殺。
    private func plausibleCoarseCoffeeGround(
        contrastBase: Double,
        stdBase: Double,
        edgeBase: Double,
        area: Int,
        fill: Double
    ) -> Bool {
        if resemblesCoffeeGroundParticle(
            contrastBase: contrastBase,
            stdBase: stdBase,
            edgeBase: edgeBase,
            area: area
        ) {
            return true
        }
        if area >= 220 && contrastBase >= 15 && stdBase >= 3.8 && fill > 0.28 { return true }
        if area >= 150 && contrastBase >= 18 && fill > 0.32 { return true }
        if area >= 320 && contrastBase >= 13 && edgeBase >= 7.0 { return true }
        return false
    }

    /// 紙張纖維／紋路：狹長線段、短邊極小之細碎塊、或對比偏弱的小圓點。
    private func isLikelyPaperFiberTexture(
        component: [Int],
        grayBase: GrayImage,
        gradientBase: [Double],
        width: Int,
        height: Int,
        meanPaper: Double
    ) -> Bool {
        let area = component.count
        if area < 8 || area > 520 { return false }

        let stdBase = stdIntensityForComponent(gray: grayBase, component: component)
        let edgeBase = meanGradientForComponent(gradient: gradientBase, component: component)
        let meanObjBase = meanIntensityForComponent(gray: grayBase, component: component)
        let contrastBase = max(0.0, meanPaper - meanObjBase)
        let fill = boundingBoxFillRatio(component: component, width: width)
        if plausibleCoarseCoffeeGround(
            contrastBase: contrastBase,
            stdBase: stdBase,
            edgeBase: edgeBase,
            area: area,
            fill: fill
        ) {
            return false
        }

        let ar = aspectRatioScore(component: component, width: width)
        let circ = circularity(component: component, width: width, height: height)
        let (bw, bh) = boundingBoxExtent(component: component, width: width)
        let shortSide = min(bw, bh)
        let longSide = max(bw, bh)
        let elongation = Double(longSide) / Double(max(shortSide, 1))

        // 細線狀纖維：短邊極窄、長邊明顯（紙纖維走向）。
        if shortSide <= 3 && longSide >= 7 && elongation >= 2.4 && area < 260 && stdBase < 6.5 {
            if contrastBase < 42 && edgeBase < 14.0 {
                return true
            }
        }
        // 極狹長、低圓度、填滿率低
        if ar < 0.18 && area < 280 && circ < 0.14 && fill < 0.42 && stdBase < 6.5 && edgeBase < 13.5 {
            return true
        }
        // 狹長帶狀紋路
        if ar < 0.24 && area < 200 && fill < 0.38 && circ < 0.16 && contrastBase < 36 && edgeBase < 12.0 {
            return true
        }
        // 紙面微小圓點／細紋：面積小、形狀略圓但對比與梯度偏弱（非咖啡粉塊）
        if area <= 48 && ar > 0.45 && circ > 0.30 && contrastBase < 22 && edgeBase < 10.0
            && stdBase < 5.2
        {
            return true
        }

        return false
    }

    /// 連通塊內「四鄰皆同塊」為內部，否則為邊界；用於區分陰影（邊界梯度 >> 平坦內部）與顆粒紋理。
    private func meanGradientBorderInterior(
        gradient: [Double],
        component: [Int],
        width: Int,
        height: Int
    ) -> (border: Double, interior: Double, borderCount: Int, interiorCount: Int) {
        let set = Set(component)
        let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var borderSum = 0.0
        var borderCount = 0
        var interiorSum = 0.0
        var interiorCount = 0
        for idx in component {
            let y = idx / width
            let x = idx % width
            var isBorder = false
            for (dy, dx) in neighbors {
                let nx = x + dx
                let ny = y + dy
                if ny < 0 || ny >= height || nx < 0 || nx >= width {
                    isBorder = true
                    break
                }
                let ni = ny * width + nx
                if !set.contains(ni) {
                    isBorder = true
                    break
                }
            }
            let g = gradient[idx]
            if isBorder {
                borderSum += g
                borderCount += 1
            } else {
                interiorSum += g
                interiorCount += 1
            }
        }
        let b = borderCount > 0 ? borderSum / Double(borderCount) : 0.0
        let i = interiorCount > 0 ? interiorSum / Double(interiorCount) : 0.0
        return (b, i, borderCount, interiorCount)
    }

    /// 紙面摺痕／陰影／亮度漸層：原圖平坦、形狀不圓、或梯度集中在邊緣（含中小面積碎塊）。
    private func isLikelyPaperShadow(
        component: [Int],
        grayBase: GrayImage,
        gradientBase: [Double],
        width: Int,
        height: Int,
        meanPaper: Double
    ) -> Bool {
        let area = component.count
        if area < 55 { return false }

        let stdBase = stdIntensityForComponent(gray: grayBase, component: component)
        let circ = circularity(component: component, width: width, height: height)
        let fill = boundingBoxFillRatio(component: component, width: width)
        let gMean = meanGradientForComponent(gradient: gradientBase, component: component)
        let meanObjBase = meanIntensityForComponent(gray: grayBase, component: component)
        let contrastBase = max(0.0, meanPaper - meanObjBase)
        if plausibleCoarseCoffeeGround(
            contrastBase: contrastBase,
            stdBase: stdBase,
            edgeBase: gMean,
            area: area,
            fill: fill
        ) {
            return false
        }
        let ar = aspectRatioScore(component: component, width: width)
        let (borderG, interiorG, _, interiorCount) = meanGradientBorderInterior(
            gradient: gradientBase,
            component: component,
            width: width,
            height: height
        )

        // 小～中塊：邊界梯度明顯高於內部、內部極平 — 常見陰影邊緣被切出的碎塊。
        if area >= 85 && interiorCount >= 5 && interiorG < 4.6 && borderG > 6.2
            && borderG > interiorG * 1.62 && stdBase < 6.4
        {
            return true
        }
        // 中塊狹長或扁帶狀陰影。
        if area >= 160 && ar < 0.30 && stdBase < 6.5 && fill < 0.48 && gMean < 15.5 && circ < 0.23 {
            return true
        }
        // 中～大面積、灰階極平坦、不圓、填滿率低。
        if area >= 260 && stdBase < 5.5 && circ < 0.17 && fill < 0.48 {
            return true
        }
        // 大面積、灰階極平坦、填滿率低或極不圓 — 典型柔和陰影／摺痕。
        if area >= 360 && stdBase < 5.3 && circ < 0.168 && fill < 0.47 {
            return true
        }
        // 狹長陰影帶。
        if area >= 400 {
            if ar < 0.26 && stdBase < 5.8 && fill < 0.44 && gMean < 14.5 {
                return true
            }
        }
        // 梯度主要在邊緣、內部近平坦。
        if area >= 160 && interiorCount >= 10 && interiorG < 4.3 && borderG > 6.8
            && borderG > interiorG * 1.88 + 0.35
        {
            return true
        }
        // 大塊但整體梯度仍低（柔和漸層）。
        if area >= 900 && stdBase < 6.8 && fill < 0.44 && contrastBase < 56 && gMean < 11.0 {
            return true
        }
        // 很大塊、對比不極高卻極「空」— 大範圍亮度漸層誤連成塊。
        if area >= 1500 && stdBase < 7.0 && fill < 0.50 && contrastBase < 54 && gMean < 13.0 {
            return true
        }

        return false
    }

    /// 熱雜訊／極小亮暗點：面積極小且對紙面幾乎無穩定對比。
    private func isLikelyImagingNoise(
        component: [Int],
        grayBase: GrayImage,
        meanPaper: Double,
        width: Int,
        height: Int
    ) -> Bool {
        let area = component.count
        if area > 28 { return false }

        let meanObjBase = meanIntensityForComponent(gray: grayBase, component: component)
        let contrastBase = max(0.0, meanPaper - meanObjBase)
        let stdBase = stdIntensityForComponent(gray: grayBase, component: component)
        let circ = circularity(component: component, width: width, height: height)

        if area <= 4 {
            return contrastBase < 10.0
        }
        if area <= 18 && contrastBase < 9.5 && stdBase < 2.2 {
            return true
        }
        if area <= 26 && contrastBase < 11.0 && stdBase < 2.0 && circ < 0.42 {
            return true
        }
        return false
    }

    private func isLikelyParticle(
        component: [Int],
        gray: GrayImage,
        gradient: [Double],
        width: Int,
        height: Int,
        meanPaper: Double,
        grayBase: GrayImage,
        gradientBase: [Double]
    ) -> Bool {
        if isLikelyImagingNoise(
            component: component,
            grayBase: grayBase,
            meanPaper: meanPaper,
            width: width,
            height: height
        ) {
            return false
        }
        if isLikelyPaperFiberTexture(
            component: component,
            grayBase: grayBase,
            gradientBase: gradientBase,
            width: width,
            height: height,
            meanPaper: meanPaper
        ) {
            return false
        }
        if isLikelyPaperShadow(
            component: component,
            grayBase: grayBase,
            gradientBase: gradientBase,
            width: width,
            height: height,
            meanPaper: meanPaper
        ) {
            return false
        }

        let area = component.count
        if area < minArea || area > maxArea { return false }

        let circ = circularity(component: component, width: width, height: height)
        let ratio = aspectRatioScore(component: component, width: width)
        let meanObj = meanIntensityForComponent(gray: gray, component: component)
        let contrast = max(0.0, meanPaper - meanObj)
        let edge = meanGradientForComponent(gradient: gradient, component: component)

        let meanObjBase = meanIntensityForComponent(gray: grayBase, component: component)
        let contrastBase = max(0.0, meanPaper - meanObjBase)
        let stdBase = stdIntensityForComponent(gray: grayBase, component: component)
        let edgeBase = meanGradientForComponent(gradient: gradientBase, component: component)
        let fillParticle = boundingBoxFillRatio(component: component, width: width)
        let (bGrad, iGrad, _, iCount) = meanGradientBorderInterior(
            gradient: gradientBase,
            component: component,
            width: width,
            height: height
        )

        // 原圖平坦、對紙面對比中等、整體梯度低：陰影／漸層殘塊（粗顆粒若對比／填滿像真咖啡則保留）。
        if area >= 140 && contrastBase >= 6.0 && contrastBase < 44 && stdBase < 5.6 && edgeBase < 11.2
            && circ < 0.21
        {
            if edgeBase < 8.5 || (iCount >= 6 && iGrad < 4.8 && bGrad > iGrad * 1.4) {
                if !plausibleCoarseCoffeeGround(
                    contrastBase: contrastBase,
                    stdBase: stdBase,
                    edgeBase: edgeBase,
                    area: area,
                    fill: fillParticle
                ) {
                    return false
                }
            }
        }

        var score = 0.09
        // For coffee grounds, contrast and edge are stronger signals than shape regularity.
        score += min(1.0, contrast / 26.0) * 0.58
        score += min(1.0, edge / 28.0) * 0.30
        score += min(1.0, max(0.0, circ) / 0.42) * 0.09
        score += min(1.0, ratio / 0.62) * 0.05
        // 面積較大之塊多為粗顆粒，略加分以免邊緣分數不足。
        if area >= 190 {
            score += 0.035
        }
        if area >= 380 {
            score += 0.025
        }

        if contrast < 1.0 && edge < 1.75 { return false }

        if area > 580 && ratio < 0.045 && circ < 0.022 { return false }

        let passThreshold = area >= 200 ? 0.068 : 0.075
        return score >= passThreshold
    }

    private func coinMarkerFromComponent(component: [Int], width: Int) -> CoinMarker {
        var sx = 0.0
        var sy = 0.0
        for idx in component {
            sx += Double(idx % width)
            sy += Double(idx / width)
        }
        let cx = sx / Double(component.count)
        let cy = sy / Double(component.count)
        let area = Double(component.count)
        let radius = CGFloat(max(4.0, sqrt(area / Double.pi)))
        return CoinMarker(center: CGPoint(x: cx, y: cy), radius: radius)
    }

    private func coinGeometryFromComponent(
        component: [Int],
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        width: Int,
        height: Int,
        coinROI: CGRect?
    ) -> (center: CGPoint, diameterPx: Double, seedDiameter: Double) {
        var sx = 0.0
        var sy = 0.0
        for idx in component {
            sx += Double(idx % width)
            sy += Double(idx / width)
        }
        let center = CGPoint(x: sx / Double(component.count), y: sy / Double(component.count))
        let seedDiameter = 2.0 * sqrt(Double(component.count) / Double.pi)
        let refinedDiameter = refineCoinDiameterByRadialScan(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper,
            center: center,
            seedDiameter: seedDiameter,
            width: width,
            height: height,
            coinROI: coinROI
        )
        return (center, refinedDiameter, seedDiameter)
    }

    private func refineCoinDiameterByRadialScan(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        center: CGPoint,
        seedDiameter: Double,
        width: Int,
        height: Int,
        coinROI: CGRect?
    ) -> Double {
        let seedRadius = max(4.0, seedDiameter * 0.5)
        let rMin = max(8.0, seedRadius * 0.65)
        let rMax = min(Double(min(width, height)) * 0.48, seedRadius * 3.2)
        if rMax <= rMin + 2 { return seedDiameter }

        var radii: [Double] = []
        radii.reserveCapacity(72)
        let angleCount = 72
        for i in 0..<angleCount {
            let theta = 2.0 * Double.pi * Double(i) / Double(angleCount)
            let ux = cos(theta)
            let uy = sin(theta)
            var bestR = 0.0
            var bestScore = 0.0

            var prevR = rMin
            var prevI = sampleGray(gray, x: center.x + ux * prevR, y: center.y + uy * prevR)
            var prevDev = abs(prevI - meanPaper)
            var r = rMin + 1.0
            while r <= rMax {
                let x = center.x + ux * r
                let y = center.y + uy * r
                if x < 1 || y < 1 || x >= Double(width - 1) || y >= Double(height - 1) { break }
                if let coinROI, !coinROI.contains(CGPoint(x: x, y: y)) { break }
                let idx = Int(y) * width + Int(x)
                if paperMask[idx] == 0 { break }

                let currI = sampleGray(gray, x: x, y: y)
                let currDev = abs(currI - meanPaper)
                let drop = max(0.0, prevDev - currDev)
                let edge = abs(currI - prevI)
                let score = drop * 0.72 + edge * 0.28
                if score > bestScore {
                    bestScore = score
                    bestR = r
                }
                prevR = r
                prevI = currI
                prevDev = currDev
                r += 1.0
            }
            if bestR > 0, bestScore >= 2.0 {
                radii.append(bestR)
            }
        }

        if radii.count >= 18 {
            let sorted = radii.sorted()
            let median = sorted[sorted.count / 2]
            let refined = median * 2.0
            return max(seedDiameter * 0.85, min(seedDiameter * 1.75, refined))
        }
        return seedDiameter
    }

    private func sampleGray(_ gray: GrayImage, x: Double, y: Double) -> Double {
        let ix = min(max(0, Int(round(x))), gray.width - 1)
        let iy = min(max(0, Int(round(y))), gray.height - 1)
        return Double(gray.pixels[iy * gray.width + ix])
    }

    private func suppressCircularRegion(
        mask: inout [UInt8],
        width: Int,
        height: Int,
        center: CGPoint,
        radius: Double
    ) {
        let r = max(1.0, radius)
        let r2 = r * r
        let minX = max(0, Int(floor(center.x - r)))
        let maxX = min(width - 1, Int(ceil(center.x + r)))
        let minY = max(0, Int(floor(center.y - r)))
        let maxY = min(height - 1, Int(ceil(center.y + r)))
        if minX > maxX || minY > maxY { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                if dx * dx + dy * dy <= r2 {
                    mask[y * width + x] = 0
                }
            }
        }
    }

    private func meanGradientForComponent(gradient: [Double], component: [Int]) -> Double {
        guard !component.isEmpty else { return 0.0 }
        var sum = 0.0
        for idx in component {
            sum += gradient[idx]
        }
        return sum / Double(component.count)
    }

    /// 只統計輪廓上的梯度，較能反映「硬幣邊緣」與白紙的對比，而非整塊陰影內部。
    private func meanGradientOnContour(
        gradient: [Double],
        component: [Int],
        width: Int,
        height: Int
    ) -> Double {
        let contour = contourPointsForComponent(component: component, width: width, height: height)
        guard !contour.isEmpty else { return 0.0 }
        var sum = 0.0
        for p in contour {
            let ix = min(max(0, Int(p.x)), width - 1)
            let iy = min(max(0, Int(p.y)), height - 1)
            sum += gradient[iy * width + ix]
        }
        return sum / Double(contour.count)
    }

    /// ROI 內多閾值候選：綜合圓度、徑向一致、輪廓邊緣強度、與白紙對比，並抑制「突然變大」的合併事件。
    private func scoreROICoinThresholdCandidate(
        feature: CoinComponentFeature,
        edgeContour: Double,
        index: Int,
        results: [(delta: Double, area: Int, component: [Int])]
    ) -> Double {
        let circ = min(1.0, feature.circularity / 0.38)
        let radial = feature.radial
        let edgeN = min(1.0, edgeContour / 28.0)
        let contrast = min(1.0, feature.contrastToPaper / 26.0)
        let fill = feature.fill
        let ratio = min(1.0, feature.ratio)

        var mergePenalty = 0.0
        if index > 0 {
            let prev = Double(results[index - 1].area)
            let curr = Double(results[index].area)
            let g = prev > 0 ? (curr - prev) / prev : 0
            if g > 0.60 { mergePenalty += 0.48 }
            else if g > 0.42 { mergePenalty += 0.26 }
            else if g > 0.30 { mergePenalty += 0.10 }
        }

        var plateauBonus = 0.0
        if index >= 2 {
            let a0 = Double(results[index - 2].area)
            let a1 = Double(results[index - 1].area)
            let a2 = Double(results[index].area)
            let g0 = a0 > 0 ? (a1 - a0) / a0 : 0
            let g1 = a1 > 0 ? (a2 - a1) / a1 : 0
            if g1 < 0.16 && g0 > 0.04 && g1 < g0 * 0.70 { plateauBonus = 0.08 }
        }

        let maxArea = results.map { $0.area }.max() ?? 1
        let areaRatio = Double(results[index].area) / Double(max(maxArea, 1))
        let tinyPenalty = (areaRatio < 0.11 && results[index].area < 220) ? 0.14 : 0.0

        let shape = circ * 0.24 + radial * 0.26 + ratio * 0.08 + fill * 0.06
        let photo = edgeN * 0.22 + contrast * 0.12
        return shape + photo + plateauBonus - mergePenalty - tinyPenalty
    }

    private func contourPointsForComponent(component: [Int], width: Int, height: Int) -> [CGPoint] {
        guard !component.isEmpty else { return [] }
        let set = Set(component)
        let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var points: [CGPoint] = []
        points.reserveCapacity(component.count / 3)

        for idx in component {
            let y = idx / width
            let x = idx % width
            var boundary = false
            for (dy, dx) in neighbors {
                let ny = y + dy
                let nx = x + dx
                if ny < 0 || ny >= height || nx < 0 || nx >= width {
                    boundary = true
                    break
                }
                let ni = ny * width + nx
                if !set.contains(ni) {
                    boundary = true
                    break
                }
            }
            if boundary {
                points.append(CGPoint(x: Double(x), y: Double(y)))
            }
        }
        return points
    }

    private func estimateUmPerPx(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        objectMask: [UInt8],
        referenceDiameterMM: Double?,
        coinROI: CGRect?
    ) -> Double? {
        guard let referenceDiameterMM, referenceDiameterMM > 0 else { return nil }

        // ROI mode：與分析流程同一顆連通塊，並用徑向掃描精煉直徑（勿只用 overlay 近似半徑）。
        if let roi = coinROI {
            let roiResult = detectCoinInROI(
                gray: gray, paperMask: paperMask, meanPaper: meanPaper,
                width: gray.width, height: gray.height, roi: roi
            )
            guard let comp = roiResult.component else { return nil }
            let geometry = coinGeometryFromComponent(
                component: comp,
                gray: gray,
                paperMask: paperMask,
                meanPaper: meanPaper,
                width: gray.width,
                height: gray.height,
                coinROI: roi
            )
            let diameterPx = effectiveCoinDiameterPx(
                diameterPx: geometry.diameterPx,
                seedDiameter: geometry.seedDiameter,
                capFactor: 1.20
            )
            let umPerPx = (referenceDiameterMM * 1000.0) / max(1.0, diameterPx)
            if isValidUmPerPx(umPerPx) { return umPerPx }
            return nil
        }

        if let coinComp = detectCoinComponentForSuppression(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper,
            objectMask: objectMask,
            width: gray.width,
            height: gray.height,
            coinROI: coinROI
        ).component {
            let geometry = coinGeometryFromComponent(
                component: coinComp,
                gray: gray,
                paperMask: paperMask,
                meanPaper: meanPaper,
                width: gray.width,
                height: gray.height,
                coinROI: coinROI
            )
            let diameterPx = effectiveCoinDiameterPx(
                diameterPx: geometry.diameterPx,
                seedDiameter: geometry.seedDiameter,
                capFactor: 1.25
            )
            let umPerPx = (referenceDiameterMM * 1000.0) / max(1.0, diameterPx)
            if isValidUmPerPx(umPerPx) {
                return umPerPx
            }
        }

        if coinROI != nil {
            // In manual ROI mode, do not fall back to global coin search outside ROI.
            return nil
        }

        // Per product requirement: if no other circular objects exist,
        // treat the detected circular object as the selected coin.
        if let permissiveDiameterPx = detectCoinDiameterPxPermissive(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper,
            objectMask: objectMask
        ) {
            let umPerPx = (referenceDiameterMM * 1000.0) / permissiveDiameterPx
            if isValidUmPerPx(umPerPx) {
                return umPerPx
            }
        }

        // Pass 1: detect a circular "coin shadow" region from paper brightness drop.
        if let shadowDiameterPx = detectCoinDiameterPxFromShadow(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper
        ) {
            let umPerPx = (referenceDiameterMM * 1000.0) / shadowDiameterPx
            if isValidUmPerPx(umPerPx) {
                return umPerPx
            }
        }

        // Pass 2 (fallback): use the dark-object mask candidate search.
        let components = connectedComponents(
            mask: objectMask,
            width: gray.width,
            height: gray.height,
            minArea: 500,
            maxArea: Int(Double(gray.pixels.count) * 0.35)
        )
        guard !components.isEmpty else { return nil }

        var bestDiameterPx: Double?
        var bestScore = 0.0
        for component in components {
            guard let candidate = coinCandidateFromComponent(
                component: component,
                width: gray.width,
                height: gray.height
            ) else { continue }
            let score = candidate.score
            if score <= bestScore { continue }
            bestScore = score
            bestDiameterPx = candidate.diameterPx
        }
        guard let bestDiameterPx, bestDiameterPx > 0 else { return nil }
        let umPerPx = (referenceDiameterMM * 1000.0) / bestDiameterPx
        if isValidUmPerPx(umPerPx) {
            return umPerPx
        }

        // Last fallback: assume the largest plausible object on paper is the selected coin.
        if let fallbackDiameterPx = detectCoinDiameterPxByLargestObject(
            objectMask: objectMask,
            width: gray.width,
            height: gray.height
        ) {
            let fallbackUmPerPx = (referenceDiameterMM * 1000.0) / fallbackDiameterPx
            if isValidUmPerPx(fallbackUmPerPx) {
                return fallbackUmPerPx
            }
        }

        // Absolute fallback: rescan grayscale inside paper region with broad thresholds.
        if let ultimateDiameterPx = detectCoinDiameterPxUltimate(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper
        ) {
            let ultimateUmPerPx = (referenceDiameterMM * 1000.0) / ultimateDiameterPx
            if ultimateUmPerPx > 0.2 && ultimateUmPerPx < 1000 {
                return ultimateUmPerPx
            }
        }

        // Non-nil fallback: detect by absolute deviation from paper (both brighter and darker).
        if let deviationDiameterPx = detectCoinDiameterPxByPaperDeviation(
            gray: gray,
            paperMask: paperMask,
            meanPaper: meanPaper
        ) {
            let deviationUmPerPx = (referenceDiameterMM * 1000.0) / deviationDiameterPx
            if deviationUmPerPx > 0.1 && deviationUmPerPx < 1500 {
                return deviationUmPerPx
            }
        }

        return nil
    }

    private func detectCoinDiameterPxPermissive(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double,
        objectMask: [UInt8]
    ) -> Double? {
        var masks: [[UInt8]] = [objectMask]
        for delta in [5.0, 8.0, 12.0, 16.0, 22.0] {
            let threshold = UInt8(max(10, min(245, Int(meanPaper - delta))))
            var mask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                mask[i] = gray.pixels[i] < threshold ? 1 : 0
            }
            masks.append(mask)
        }

        let minArea = max(120, Int(Double(gray.pixels.count) * 0.00035))
        let maxArea = Int(Double(gray.pixels.count) * 0.55)
        var candidates: [CoinCandidate] = []
        candidates.reserveCapacity(24)

        for mask in masks {
            let components = connectedComponents(
                mask: mask,
                width: gray.width,
                height: gray.height,
                minArea: minArea,
                maxArea: maxArea
            )
            for component in components {
                guard let candidate = coinCandidateFromComponent(
                    component: component,
                    width: gray.width,
                    height: gray.height
                ) else { continue }
                candidates.append(candidate)
            }
        }

        return weightedMedianDiameter(candidates: candidates)
    }

    private func detectCoinDiameterPxFromShadow(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double
    ) -> Double? {
        let deltas: [Double] = [6, 8, 10, 12, 15, 18, 22]
        var candidates: [CoinCandidate] = []
        candidates.reserveCapacity(20)

        for delta in deltas {
            let threshold = UInt8(max(12, min(245, Int(meanPaper - delta))))
            var shadowMask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                shadowMask[i] = gray.pixels[i] < threshold ? 1 : 0
            }

            let minArea = max(180, Int(Double(gray.pixels.count) * 0.0006))
            let maxArea = Int(Double(gray.pixels.count) * 0.45)
            let components = connectedComponents(
                mask: shadowMask,
                width: gray.width,
                height: gray.height,
                minArea: minArea,
                maxArea: maxArea
            )

            for component in components {
                guard let baseCandidate = coinCandidateFromComponent(
                    component: component,
                    width: gray.width,
                    height: gray.height
                ) else { continue }

                let meanObject = meanIntensityForComponent(gray: gray, component: component)
                let contrast = max(0.0, meanPaper - meanObject)
                let contrastScore = min(1.0, contrast / 38.0)

                // Shadow pass relies on darkness, but still keeps geometric confidence dominant.
                let score = baseCandidate.score * 0.82 + contrastScore * 0.18
                candidates.append(CoinCandidate(diameterPx: baseCandidate.diameterPx, score: score))
            }
        }

        return weightedMedianDiameter(candidates: candidates)
    }

    private func coinCandidateFromComponent(component: [Int], width: Int, height: Int) -> CoinCandidate? {
        let area = Double(component.count)
        if area <= 0 { return nil }

        let areaDiameter = 2.0 * sqrt(area / Double.pi)
        let minImageDim = Double(min(width, height))
        if areaDiameter < max(20.0, minImageDim * 0.04) { return nil }
        if areaDiameter > minImageDim * 0.92 { return nil }

        let circ = circularity(component: component, width: width, height: height)
        let ratio = aspectRatioScore(component: component, width: width)
        let fill = boundingBoxFillRatio(component: component, width: width)
        if circ < 0.25 || ratio < 0.50 || fill < 0.18 { return nil }

        let contour = contourPointsForComponent(component: component, width: width, height: height)
        guard contour.count >= 12 else { return nil }

        var sx = 0.0
        var sy = 0.0
        for idx in component {
            sx += Double(idx % width)
            sy += Double(idx / width)
        }
        let cx = sx / Double(component.count)
        let cy = sy / Double(component.count)

        var radii: [Double] = []
        radii.reserveCapacity(contour.count)
        for p in contour {
            let dx = Double(p.x) - cx
            let dy = Double(p.y) - cy
            radii.append(sqrt(dx * dx + dy * dy))
        }
        let meanR = radii.reduce(0.0, +) / Double(radii.count)
        if meanR < 6.0 { return nil }
        let varR = radii.reduce(0.0) { acc, r in
            let d = r - meanR
            return acc + d * d
        } / Double(radii.count)
        let stdR = sqrt(varR)
        let radial = max(0.0, min(1.0, 1.0 - (stdR / max(meanR, 1e-6))))
        if radial < 0.30 { return nil }

        // Diameter from contour radius is less sensitive to binary threshold drift.
        let contourDiameter = meanR * 2.0
        let diameter = 0.65 * contourDiameter + 0.35 * areaDiameter
        let sizeScore = min(1.0, diameter / (minImageDim * 0.28))
        let score = radial * 0.40 + circ * 0.26 + ratio * 0.16 + fill * 0.08 + sizeScore * 0.10

        return CoinCandidate(diameterPx: diameter, score: score)
    }

    private func weightedMedianDiameter(candidates: [CoinCandidate]) -> Double? {
        if candidates.isEmpty { return nil }

        let top = candidates.sorted { $0.score > $1.score }.prefix(9)
        if top.isEmpty { return nil }

        let maxDiameter = top.map(\.diameterPx).max() ?? 0.0
        let largeTop = top.filter { $0.diameterPx >= max(18.0, maxDiameter * 0.62) }
        let effective = largeTop.isEmpty ? Array(top) : largeTop

        let sortedByDiameter = effective.sorted { $0.diameterPx < $1.diameterPx }
        let totalWeight = sortedByDiameter.reduce(0.0) { $0 + max(0.001, $1.score) }
        var acc = 0.0
        for c in sortedByDiameter {
            acc += max(0.001, c.score)
            if acc >= totalWeight * 0.5 {
                return c.diameterPx
            }
        }
        return sortedByDiameter.last?.diameterPx
    }

    private func isValidUmPerPx(_ value: Double) -> Bool {
        // Practical handheld capture range, keeps close-up shots valid.
        return value >= 1.0 && value <= 450.0
    }

    private func detectCoinDiameterPxByLargestObject(
        objectMask: [UInt8],
        width: Int,
        height: Int
    ) -> Double? {
        let minArea = max(100, Int(Double(objectMask.count) * 0.00025))
        let maxArea = Int(Double(objectMask.count) * 0.70)
        let components = connectedComponents(
            mask: objectMask,
            width: width,
            height: height,
            minArea: minArea,
            maxArea: maxArea
        )
        guard !components.isEmpty else { return nil }

        var maxDiameter = 0.0
        for comp in components {
            let d = 2.0 * sqrt(Double(comp.count) / Double.pi)
            if d > maxDiameter { maxDiameter = d }
        }
        let minCoinDiameter = max(18.0, maxDiameter * 0.60)

        var bestDiameter: Double?
        var bestScore = -1.0
        for comp in components {
            let area = Double(comp.count)
            let diameter = 2.0 * sqrt(area / Double.pi)
            if diameter < minCoinDiameter { continue }

            let circ = circularity(component: comp, width: width, height: height)
            let ratio = aspectRatioScore(component: comp, width: width)
            if circ < 0.20 || ratio < 0.45 { continue }

            let fill = boundingBoxFillRatio(component: comp, width: width)
            let sizeDominance = maxDiameter > 0 ? min(1.0, diameter / maxDiameter) : 0
            let score = sizeDominance * 0.55 + max(0.0, circ) * 0.24 + ratio * 0.15 + fill * 0.06
            if score > bestScore {
                bestScore = score
                bestDiameter = diameter
            }
        }
        return bestDiameter
    }

    private func detectCoinDiameterPxUltimate(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double
    ) -> Double? {
        var candidates: [CoinCandidate] = []
        candidates.reserveCapacity(40)

        var deltas: [Int] = [4, 6, 8, 10, 12, 15, 18, 22, 28, 36, 44]
        let otsu = Int(ImageProcessing.otsuThreshold(gray))
        deltas.append(max(2, Int(meanPaper) - otsu))

        let minArea = max(80, Int(Double(gray.pixels.count) * 0.00018))
        let maxArea = Int(Double(gray.pixels.count) * 0.78)

        for delta in deltas {
            let t = UInt8(max(6, min(245, Int(meanPaper) - delta)))
            var mask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                mask[i] = gray.pixels[i] < t ? 1 : 0
            }
            let components = connectedComponents(
                mask: mask,
                width: gray.width,
                height: gray.height,
                minArea: minArea,
                maxArea: maxArea
            )
            for comp in components {
                guard let candidate = coinCandidateFromComponent(
                    component: comp,
                    width: gray.width,
                    height: gray.height
                ) else { continue }
                candidates.append(candidate)
            }
        }

        if let d = weightedMedianDiameter(candidates: candidates) {
            return d
        }

        // Final fallback in this pass: largest plausible component under a loose threshold.
        let looseThreshold = UInt8(max(6, min(245, Int(meanPaper) - 6)))
        var looseMask = [UInt8](repeating: 0, count: gray.pixels.count)
        for i in 0..<gray.pixels.count where paperMask[i] == 1 {
            looseMask[i] = gray.pixels[i] < looseThreshold ? 1 : 0
        }
        let looseComponents = connectedComponents(
            mask: looseMask,
            width: gray.width,
            height: gray.height,
            minArea: minArea,
            maxArea: maxArea
        )
        guard let largest = looseComponents.max(by: { $0.count < $1.count }) else { return nil }
        let area = Double(largest.count)
        let diameter = 2.0 * sqrt(area / Double.pi)
        return diameter > 8 ? diameter : nil
    }

    private func detectCoinDiameterPxByPaperDeviation(
        gray: GrayImage,
        paperMask: [UInt8],
        meanPaper: Double
    ) -> Double? {
        let minArea = max(80, Int(Double(gray.pixels.count) * 0.00015))
        let maxArea = Int(Double(gray.pixels.count) * 0.85)
        var bestDiameter: Double?
        var bestScore = -1.0

        for delta in [5.0, 8.0, 12.0, 16.0, 22.0, 30.0, 40.0] {
            var mask = [UInt8](repeating: 0, count: gray.pixels.count)
            for i in 0..<gray.pixels.count where paperMask[i] == 1 {
                let dev = abs(Double(gray.pixels[i]) - meanPaper)
                mask[i] = dev >= delta ? 1 : 0
            }
            let components = connectedComponents(
                mask: mask,
                width: gray.width,
                height: gray.height,
                minArea: minArea,
                maxArea: maxArea
            )
            var maxDiameter = 0.0
            for comp in components {
                let d = 2.0 * sqrt(Double(comp.count) / Double.pi)
                if d > maxDiameter { maxDiameter = d }
            }
            let minCoinDiameter = max(18.0, maxDiameter * 0.60)
            for comp in components {
                let area = Double(comp.count)
                let diameter = 2.0 * sqrt(area / Double.pi)
                if diameter < minCoinDiameter { continue }

                let circ = circularity(component: comp, width: gray.width, height: gray.height)
                let ratio = aspectRatioScore(component: comp, width: gray.width)
                let fill = boundingBoxFillRatio(component: comp, width: gray.width)
                let sizeDominance = maxDiameter > 0 ? min(1.0, diameter / maxDiameter) : 0
                let score = sizeDominance * 0.55 + max(0, circ) * 0.25 + ratio * 0.14 + fill * 0.06

                if score > bestScore {
                    bestScore = score
                    bestDiameter = diameter
                }
            }
        }
        return bestDiameter
    }

    private func meanIntensityForComponent(gray: GrayImage, component: [Int]) -> Double {
        guard !component.isEmpty else { return 255.0 }
        var sum = 0.0
        for idx in component {
            sum += Double(gray.pixels[idx])
        }
        return sum / Double(component.count)
    }

    private func stdIntensityForComponent(gray: GrayImage, component: [Int]) -> Double {
        guard component.count >= 2 else { return 0.0 }
        let mean = meanIntensityForComponent(gray: gray, component: component)
        var acc = 0.0
        for idx in component {
            let d = Double(gray.pixels[idx]) - mean
            acc += d * d
        }
        return sqrt(acc / Double(component.count))
    }

    private func circularity(component: [Int], width: Int, height: Int) -> Double {
        let area = Double(component.count)
        if area <= 0 { return 0 }

        let set = Set(component)
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var perimeter = 0.0
        for idx in component {
            let y = idx / width
            let x = idx % width
            for (dy, dx) in offsets {
                let ny = y + dy
                let nx = x + dx
                if ny < 0 || ny >= height || nx < 0 || nx >= width {
                    perimeter += 1
                    continue
                }
                let ni = ny * width + nx
                if !set.contains(ni) {
                    perimeter += 1
                }
            }
        }
        if perimeter <= 0 { return 0 }
        return (4.0 * Double.pi * area) / (perimeter * perimeter)
    }

    private func aspectRatioScore(component: [Int], width: Int) -> Double {
        guard let first = component.first else { return 0 }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY

        for idx in component {
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let w = max(1, maxX - minX + 1)
        let h = max(1, maxY - minY + 1)
        return Double(min(w, h)) / Double(max(w, h))
    }

    private func boundingBoxFillRatio(component: [Int], width: Int) -> Double {
        guard let first = component.first else { return 0.0 }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for idx in component {
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let bw = max(1, maxX - minX + 1)
        let bh = max(1, maxY - minY + 1)
        return Double(component.count) / Double(bw * bh)
    }

    private func fillHoles(mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        if width <= 0 || height <= 0 { return mask }
        var outside = [UInt8](repeating: 0, count: mask.count)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        func tryPush(_ idx: Int) {
            if idx < 0 || idx >= mask.count { return }
            if mask[idx] == 0 && outside[idx] == 0 {
                outside[idx] = 1
                queue.append(idx)
            }
        }

        for x in 0..<width {
            tryPush(x)
            tryPush((height - 1) * width + x)
        }
        for y in 0..<height {
            tryPush(y * width)
            tryPush(y * width + (width - 1))
        }

        var head = 0
        let steps = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        while head < queue.count {
            let idx = queue[head]
            head += 1
            let y = idx / width
            let x = idx % width
            for (dy, dx) in steps {
                let ny = y + dy
                let nx = x + dx
                if ny < 0 || ny >= height || nx < 0 || nx >= width { continue }
                let ni = ny * width + nx
                if mask[ni] == 0 && outside[ni] == 0 {
                    outside[ni] = 1
                    queue.append(ni)
                }
            }
        }

        var result = mask
        for i in 0..<result.count where result[i] == 0 && outside[i] == 0 {
            result[i] = 1
        }
        return result
    }

    private func calibrationText(umPerPx: Double?, requested: Bool) -> String {
        guard let umPerPx else {
            return requested ? "未偵測到硬幣，改為相對模式" : "相對模式（未校正）"
        }
        return String(format: "校正模式：1 px ≈ %.2f um", umPerPx)
    }

    private func color(for kind: ParticleClass) -> UIColor {
        switch kind {
        case .fine:
            return UIColor.systemBlue
        case .target:
            return UIColor.systemGreen
        case .coarse:
            return UIColor.systemRed
        }
    }
}
