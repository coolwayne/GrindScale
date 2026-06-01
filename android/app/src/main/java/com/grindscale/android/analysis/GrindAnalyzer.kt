package com.grindscale.android.analysis

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import com.grindscale.android.domain.AnalysisMode
import com.grindscale.android.domain.AnalysisResult
import com.grindscale.android.domain.AnalysisStats
import com.grindscale.android.domain.BrewProfile
import com.grindscale.android.domain.CoinCandidateOverlay
import com.grindscale.android.domain.CoinMarker
import com.grindscale.android.domain.Particle
import com.grindscale.android.domain.ParticleClass
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object GrindAnalyzer {

    data class QualityReport(val pass: Boolean, val brightness: Double, val occupancy: Double, val contrast: Double)

    fun checkQuality(bitmap: Bitmap): QualityReport {
        val gray =
            ImageProcessing.grayscale(bitmap, maxDimension = 720) ?: return QualityReport(false, 0.0, 0.0, 0.0)
        val n = gray.pixels.size.toDouble()
        val brightness =
            gray.pixels.sumOf { (it.toInt() and 0xFF).toDouble() } / n
        val variance =
            gray.pixels.sumOf {
                val d = (it.toInt() and 0xFF).toDouble() - brightness
                d * d
            } / n
        val contrast = sqrt(variance)
        val threshold = ImageProcessing.otsuThreshold(gray)
        val mask = ImageProcessing.binaryMask(gray, threshold)
        val occupancy =
            mask.count { it != 0.toByte() }.toDouble() / mask.size.toDouble()
        val pass = brightness >= 40 && brightness <= 220 && contrast >= 20 && occupancy > 0.02
        return QualityReport(pass, brightness, occupancy, contrast)
    }

    fun analyze(
        bitmap: Bitmap,
        profile: BrewProfile,
        referenceDiameterMM: Double? = null,
        coinRoiNormalized: NormalizedRoi? = null
    ): AnalysisResult {
        val gray = ImageProcessing.grayscale(bitmap) ?: return emptyAnalysisFailure("影像讀取失敗")
        val blurred = ImageProcessing.boxBlur(gray, radius = 0)
        val normalized = localContrastNormalize(blurred, backgroundRadius = 8, gain = 1.52)
        val gradient = gradientMagnitude(normalized)
        val gradientBase = gradientMagnitude(blurred)
        val globalOtsu = ImageProcessing.otsuThreshold(blurred)
        val paperMask = detectPaperMask(blurred)
        val meanPaper = meanIntensity(blurred, paperMask)
        val stdPaper = stdIntensity(blurred, paperMask, meanPaper)
        val coinPixelRoi =
            coinRoiNormalized?.let { normalizedRoiToPixelRect(it, gray.width, gray.height) }
        val objectMask = makeObjectMask(blurred, paperMask, meanPaper)
        var particleMask = buildParticleMaskRobust(blurred, normalized, paperMask, meanPaper, stdPaper, globalOtsu)
        val umPerPx =
            estimateUmPerPx(blurred, paperMask, meanPaper, objectMask, referenceDiameterMM, coinPixelRoi)

        val coinSelection = detectCoinComponentForSuppression(
            blurred, paperMask, meanPaper, objectMask,
            gray.width, gray.height, coinPixelRoi
        )
        val coinComponent = coinSelection.component

        val coinGeometry = coinComponent?.let {
            coinGeometryFromComponent(it, blurred, paperMask, meanPaper, gray.width, gray.height, coinPixelRoi)
        }

        val coinMarker = coinGeometry?.let { geo ->
            val displayDiameter =
                effectiveCoinDiameterPx(
                    geo.diameterPx,
                    geo.seedDiameter,
                    1.20
                )
            CoinMarker(geo.centerX, geo.centerY, (displayDiameter * 0.5).toFloat())
        }

        if (coinComponent != null && coinGeometry != null) {
            var appliedCoinSuppression = false
            var suppressDiameter: Double? = null
            val d = effectiveCoinDiameterPx(coinGeometry.diameterPx, coinGeometry.seedDiameter, 1.20)
            val suppressArea = kotlin.math.PI * (d * 0.56) * (d * 0.56)
            val imageArea = (gray.width * gray.height).toDouble()
            if (suppressArea / max(1.0, imageArea) <= 0.22) {
                for (idx in coinComponent) particleMask[idx] = 0
                suppressDiameter = d
                appliedCoinSuppression = true
            }
            if (appliedCoinSuppression && suppressDiameter != null) {
                suppressCircularRegion(
                    particleMask,
                    gray.width,
                    gray.height,
                    coinGeometry.centerX,
                    coinGeometry.centerY,
                    suppressDiameter!! * 0.56
                )
            }
        }

        var components = connectedComponents(
            particleMask, gray.width, gray.height,
            minArea = AnalyzerConstants.MIN_AREA, maxArea = AnalyzerConstants.MAX_AREA
        )

        if (components.isEmpty()) {
            val fallbackThr = max(6, (ImageProcessing.otsuThreshold(blurred).toInt() and 0xFF) - 24)
            val fallbackMask = ImageProcessing.binaryMask(blurred, fallbackThr.toUInt().toUByte())
            for (i in fallbackMask.indices) {
                if (paperMask[i] == 0.toByte()) fallbackMask[i] = 0
            }
            if (coinComponent != null && coinGeometry != null) {
                var applied = false
                var supD: Double? = null
                val d = effectiveCoinDiameterPx(coinGeometry.diameterPx, coinGeometry.seedDiameter, 1.20)
                val supArea = kotlin.math.PI * (d * 0.56) * (d * 0.56)
                val imgArea = (gray.width * gray.height).toDouble()
                if (supArea / max(1.0, imgArea) <= 0.22) {
                    for (idx in coinComponent) fallbackMask[idx] = 0
                    supD = d
                    applied = true
                }
                if (applied && supD != null) {
                    suppressCircularRegion(
                        fallbackMask, gray.width, gray.height,
                        coinGeometry.centerX, coinGeometry.centerY, supD * 0.56
                    )
                }
            }
            components = connectedComponents(
                fallbackMask, gray.width, gray.height,
                minArea = AnalyzerConstants.MIN_AREA, maxArea = AnalyzerConstants.MAX_AREA
            )
        }

        if (components.isNotEmpty()) {
            components = splitTouchingComponents(components, gray.width, gray.height)
            components = components.filter {
                isLikelyParticle(it, normalized, gradient, gray.width, gray.height, meanPaper, blurred, gradientBase)
            }
        }

        if (components.isEmpty()) {
            val mode = if (umPerPx == null) AnalysisMode.relative else AnalysisMode.calibrated
            return AnalysisResult(
                stats = emptyStats(mode),
                particles = emptyList(),
                diameters = emptyList(),
                calibrationText = calibrationText(umPerPx, referenceDiameterMM != null),
                analyzedWidth = gray.width,
                analyzedHeight = gray.height,
                coinMarker = coinMarker,
                coinCandidates = coinSelection.diagnostics,
                coinCandidateOverlays = coinSelection.overlays
            )
        }

        val diametersPx = components.map { equivalentDiskDiameterPx(it.size) }.toList()
        val sorted = diametersPx.sorted()
        val thresholds = relativeThresholds(sorted, profile)

        val particles = ArrayList<Particle>(components.size)
        val diametersOut = ArrayList<Double>(components.size)
        components.forEachIndexed { idx, comp ->
            var dPx = diametersPx[idx]
            val dUm = umPerPx?.times(dPx)

            var kind = classifyParticle(dPx, dUm, profile, thresholds)

            if (kind == ParticleClass.coarse) {
                val roundness = circularity(comp, gray.width, gray.height)
                val ratio = aspectRatioScore(comp, gray.width)
                val fill = boundingBoxFillRatio(comp, gray.width)
                kind = when {
                    roundness < 0.07 && ratio < 0.11 -> ParticleClass.target
                    isLikelyAgglomeratedFineCluster(roundness, fill, ratio) -> ParticleClass.target
                    else -> ParticleClass.coarse
                }
            }

            var sx = 0.0
            var sy = 0.0
            for (pixelIndex in comp) {
                sy += pixelIndex / gray.width
                sx += pixelIndex % gray.width
            }
            val cx = sx / comp.size
            val cy = sy / comp.size
            diametersOut.add(dUm ?: dPx)
            val visRadius = max(2.0, min(14.0, dPx * 0.35)).toFloat()

            val contourPts = contourPointsForComponent(comp, gray.width, gray.height)

            particles.add(
                Particle(
                    centerX = cx,
                    centerY = cy,
                    radiusPx = visRadius,
                    diameterPx = dPx,
                    diameterUM = dUm,
                    kind = kind,
                    contour = contourPts
                )
            )
        }

        val classes = particles.map { it.kind }
        val mode = if (umPerPx == null) AnalysisMode.relative else AnalysisMode.calibrated
        val stats = buildStats(diametersOut, classes, mode)
        return AnalysisResult(
            stats = stats,
            particles = particles,
            diameters = diametersOut,
            calibrationText = calibrationText(umPerPx, referenceDiameterMM != null),
            analyzedWidth = gray.width,
            analyzedHeight = gray.height,
            coinMarker = coinMarker,
            coinCandidates = coinSelection.diagnostics,
            coinCandidateOverlays = coinSelection.overlays
        )
    }

    fun overlayBitmap(
        base: Bitmap,
        particles: List<Particle>,
        analyzedWidth: Int,
        analyzedHeight: Int,
        coinMarker: CoinMarker?,
        coinCandidateOverlays: List<CoinCandidateOverlay>
    ): Bitmap {
        val out = base.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(out)
        val sx = base.width.toFloat() / max(analyzedWidth, 1)
        val sy = base.height.toFloat() / max(analyzedHeight, 1)

        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }

        for (particle in particles) {
            val color = when (particle.kind) {
                ParticleClass.fine -> 0xFF2196F3.toInt()
                ParticleClass.target -> 0xFF4CAF50.toInt()
                ParticleClass.coarse -> 0xFFF44336.toInt()
            }
            fillPaint.color = color
            strokePaint.color = color
            if (particle.contour.isNotEmpty()) {
                val w = max(1f, sx)
                val h = max(1f, sy)
                for (pt in particle.contour) {
                    val x = pt.first * sx
                    val y = pt.second * sy
                    canvas.drawRect(x, y, x + w, y + h, fillPaint)
                }
            } else {
                val rsx = particle.radiusPx * sx
                val rsy = particle.radiusPx * sy
                val left = (particle.centerX * sx - rsx).toFloat()
                val top = (particle.centerY * sy - rsy).toFloat()
                canvas.drawOval(left, top, left + 2 * rsx, top + 2 * rsy, strokePaint)
            }
        }

        for (cand in coinCandidateOverlays) {
            val rank = cand.rank.coerceIn(1, 20)
            strokePaint.strokeWidth = if (cand.selected) 4f else 2.5f
            strokePaint.color = CoinCandidateColors.colorForRank(rank, cand.selected)
            val rx = cand.radiusPx * sx
            val ry = cand.radiusPx * sy
            val left = (cand.centerX * sx - rx).toFloat()
            val top = (cand.centerY * sy - ry).toFloat()
            canvas.drawOval(left, top, left + 2 * rx, top + 2 * ry, strokePaint)
        }

        strokePaint.strokeWidth = 3.5f
        strokePaint.color = 0xFFFFEB3B.toInt()
        coinMarker?.let { m ->
            val rx = m.radiusPx * sx
            val ry = m.radiusPx * sy
            val l = (m.centerX * sx - rx).toFloat()
            val t = (m.centerY * sy - ry).toFloat()
            canvas.drawOval(l, t, l + 2 * rx, t + 2 * ry, strokePaint)
        }

        return out
    }

    private fun emptyAnalysisFailure(msg: String) = AnalysisResult(
        stats = emptyStats(AnalysisMode.relative),
        particles = emptyList(),
        diameters = emptyList(),
        calibrationText = msg,
        analyzedWidth = 0,
        analyzedHeight = 0,
        coinMarker = null,
        coinCandidates = emptyList(),
        coinCandidateOverlays = emptyList()
    )

    private fun emptyStats(mode: AnalysisMode) = AnalysisStats(
        particleCount = 0,
        mean = 0.0,
        std = 0.0,
        cv = 0.0,
        d10 = 0.0,
        d50 = 0.0,
        d90 = 0.0,
        fineRatio = 0.0,
        targetRatio = 0.0,
        coarseRatio = 0.0,
        bimodal = false,
        uniformityScore = 0,
        mode = mode,
        unitLabel = if (mode == AnalysisMode.calibrated) "um" else "px"
    )

    private fun classifyParticle(
        diameterPx: Double,
        diameterUM: Double?,
        profile: BrewProfile,
        thresholds: Pair<Double, Double>
    ): ParticleClass {
        val dUm = diameterUM
        if (dUm != null) {
            if (dUm < profile.fineThresholdUM) return ParticleClass.fine
            if (dUm > profile.coarseThresholdUM) return ParticleClass.coarse
            return ParticleClass.target
        }
        if (diameterPx < thresholds.first) return ParticleClass.fine
        if (diameterPx > thresholds.second) return ParticleClass.coarse
        return ParticleClass.target
    }

    private fun relativeThresholds(diametersSorted: List<Double>, profile: BrewProfile): Pair<Double, Double> {
        if (diametersSorted.isEmpty()) return Pair(0.0, Double.POSITIVE_INFINITY)
        val p25 = percentile(diametersSorted, 0.25)
        val p50 = percentile(diametersSorted, 0.50)
        val p85 = percentile(diametersSorted, 0.85)
        var fineMax = min(p50 * profile.relativeFineRatio, p25 * 0.95)
        var coarseMin = max(p50 * profile.relativeCoarseRatio, p85 * 1.03)
        if (coarseMin <= fineMax) coarseMin = fineMax * 1.25
        return Pair(fineMax, coarseMin)
    }

    private fun percentile(sorted: List<Double>, p: Double): Double {
        if (sorted.isEmpty()) return 0.0
        val index = min(sorted.size - 1, max(0, kotlin.math.round((sorted.size - 1) * p).toInt()))
        return sorted[index]
    }

    private fun isBimodal(diameters: List<Double>): Boolean {
        if (diameters.size < 40) return false
        val minValue = diameters.minOrNull() ?: return false
        val maxValue = diameters.maxOrNull() ?: return false
        if (maxValue <= minValue) return false
        val bins = 24
        val hist = IntArray(bins)
        val step = (maxValue - minValue) / bins.toDouble()
        for (d in diameters) {
            val idx = min(bins - 1, max(0, ((d - minValue) / max(step, 1e-6)).toInt()))
            hist[idx]++
        }
        var peaks = 0
        val threshold = max(2, ((hist.maxOrNull() ?: 0) * 0.2).toInt())
        for (i in 1 until bins - 1) {
            if (hist[i] > hist[i - 1] && hist[i] > hist[i + 1] && hist[i] >= threshold) peaks++
        }
        return peaks >= 2
    }

    private fun buildStats(diameters: List<Double>, classes: List<ParticleClass>, mode: AnalysisMode): AnalysisStats {
        if (diameters.isEmpty()) return emptyStats(mode)
        val n = diameters.size.toDouble()
        val mean = diameters.sum() / n
        val variance = diameters.sumOf { val x = it - mean; x * x } / n
        val std = sqrt(variance)
        val cv = if (mean > 0) std / mean else 0.0
        val fine = classes.count { it == ParticleClass.fine } / n
        val target = classes.count { it == ParticleClass.target } / n
        val coarse = classes.count { it == ParticleClass.coarse } / n
        val bimodal = isBimodal(diameters)
        val cvPenalty = min(45.0, cv * 180.0)
        val outlierPenalty = min(45.0, (fine + coarse) * 90.0)
        val bimodalPenalty = if (bimodal) 12.0 else 0.0
        val score = max(0, min(100, kotlin.math.round(100.0 - cvPenalty - outlierPenalty - bimodalPenalty).toInt()))
        val sorted = diameters.sorted()
        return AnalysisStats(
            particleCount = diameters.size,
            mean = mean,
            std = std,
            cv = cv,
            d10 = percentile(sorted, 0.10),
            d50 = percentile(sorted, 0.50),
            d90 = percentile(sorted, 0.90),
            fineRatio = fine,
            targetRatio = target,
            coarseRatio = coarse,
            bimodal = bimodal,
            uniformityScore = score,
            mode = mode,
            unitLabel = if (mode == AnalysisMode.calibrated) "um" else "px"
        )
    }

    private fun calibrationText(umPerPx: Double?, requested: Boolean): String {
        if (umPerPx == null) {
            return if (requested) "未偵測到硬幣，改為相對模式" else "相對模式（未校正）"
        }
        return String.format("校正模式：1 px ≈ %.2f um", umPerPx)
    }

    private object CoinCandidateColors {
        private val base = intArrayOf(
            color(0.95f, 0.25f, 0.22f),
            color(1.0f, 0.48f, 0.0f),
            color(0.75f, 0.35f, 0.95f),
            color(0.2f, 0.78f, 0.35f),
            color(0.0f, 0.78f, 0.75f),
            color(0.0f, 0.55f, 1.0f),
            color(0.25f, 0.35f, 0.95f),
            color(1.0f, 0.35f, 0.65f),
            color(0.55f, 0.35f, 0.2f),
            color(1.0f, 0.85f, 0.2f)
        )

        fun colorForRank(rank: Int, selected: Boolean): Int {
            val idx = (max(1, rank) - 1) % base.size
            val c = base[idx]
            val alpha = if (selected) 255 else (255 * 0.92).toInt()
            return (c and 0x00FFFFFF) or (alpha shl 24)
        }

        private fun color(r: Float, g: Float, b: Float): Int {
            val ri = (r * 255).toInt().coerceIn(0, 255)
            val gi = (g * 255).toInt().coerceIn(0, 255)
            val bi = (b * 255).toInt().coerceIn(0, 255)
            return 0xFF000000.toInt() or (ri shl 16) or (gi shl 8) or bi
        }
    }
}
