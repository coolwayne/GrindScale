package com.grindscale.android.analysis

import com.grindscale.android.domain.CoinCandidateDebug
import com.grindscale.android.domain.CoinCandidateOverlay

internal data class InternalCoinCandidate(val diameterPx: Double, val score: Double)

internal data class CoinSelectionResult(
    val component: List<Int>?,
    val diagnostics: List<CoinCandidateDebug>,
    val overlays: List<CoinCandidateOverlay>
)

internal data class CoinComponentFeature(
    val component: List<Int>,
    val centerX: Double,
    val centerY: Double,
    val diameter: Double,
    val circularity: Double,
    val ratio: Double,
    val fill: Double,
    val radial: Double,
    val contrastToPaper: Double
)

internal fun coinFeature(
    component: List<Int>,
    width: Int,
    height: Int,
    gray: GrayImage,
    meanPaper: Double
): CoinComponentFeature {
    var sx = 0.0
    var sy = 0.0
    for (idx in component) {
        sx += (idx % width).toDouble()
        sy += (idx / width).toDouble()
    }
    val cx = sx / component.size.toDouble()
    val cy = sy / component.size.toDouble()
    val area = component.size.toDouble()
    val diameter = 2.0 * kotlin.math.sqrt(area / kotlin.math.PI)
    val circ = circularity(component, width, height)
    val ratio = aspectRatioScore(component, width)
    val fill = boundingBoxFillRatio(component, width)
    val rad = radialConsistency(component, width, height, cx, cy)
    val contrastToPaper = maxOf(0.0, meanPaper - meanIntensityForComponent(gray, component))
    return CoinComponentFeature(
        component = component,
        centerX = cx,
        centerY = cy,
        diameter = diameter,
        circularity = circ,
        ratio = ratio,
        fill = fill,
        radial = rad,
        contrastToPaper = contrastToPaper
    )
}

internal fun coinSupportScore(target: CoinComponentFeature, all: List<CoinComponentFeature>): Double {
    if (all.isEmpty()) return 0.0
    val distTol = kotlin.math.max(8.0, target.diameter * 0.22)
    var support = 0
    for (candidate in all) {
        val dx = candidate.centerX - target.centerX
        val dy = candidate.centerY - target.centerY
        val distance = kotlin.math.sqrt(dx * dx + dy * dy)
        val diameterRatio = candidate.diameter / kotlin.math.max(target.diameter, 1.0)
        if (distance <= distTol && diameterRatio >= 0.62 && diameterRatio <= 1.60) support++
    }
    return kotlin.math.min(1.0, support.toDouble() / kotlin.math.max(1, all.size).toDouble())
}

internal fun percentileSorted(sorted: List<Double>, p: Double): Double {
    if (sorted.isEmpty()) return 0.0
    val index =
        kotlin.math.min(sorted.size - 1, kotlin.math.max(0, kotlin.math.round((sorted.size - 1) * p).toInt()))
    return sorted[index]
}

internal fun detectCoinFromAllCandidates(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    objectMask: ByteArray,
    width: Int,
    height: Int
): CoinSelectionResult {
    val allComponents = collectCoinCandidateComponents(
        gray, paperMask, meanPaper, objectMask, width, height
    )
    if (allComponents.isEmpty()) {
        return CoinSelectionResult(null, emptyList(), emptyList())
    }
    val features = allComponents.map { coinFeature(it, width, height, gray, meanPaper) }
    val areasSorted = features.map { it.component.size.toDouble() }.sorted()
    val medianArea = percentileSorted(areasSorted, 0.50)
    val p90Area = percentileSorted(areasSorted, 0.90)
    var minCoinArea = maxOf(320.0, medianArea * 4.2, p90Area * 1.45)
    var filtered = features.filter { it.component.size.toDouble() >= minCoinArea }
    if (filtered.isEmpty()) {
        filtered = features.sortedByDescending { it.component.size }.take(3)
    }
    var best: CoinComponentFeature? = null
    var bestScore = -1.0
    val scoredRows = ArrayList<Triple<CoinComponentFeature, Double, Double>>()
    val maxArea = filtered.maxOfOrNull { it.component.size.toDouble() } ?: minCoinArea
    for (feature in filtered) {
        val support = coinSupportScore(feature, filtered)
        val areaScore =
            kotlin.math.min(1.0, feature.component.size.toDouble() / kotlin.math.max(maxArea, 1.0))
        val shapeScore = feature.circularity * 0.37 + feature.ratio * 0.18 +
            feature.fill * 0.08 + feature.radial * 0.22 +
            kotlin.math.min(1.0, feature.contrastToPaper / 28.0) * 0.15
        val passesShape = feature.circularity >= 0.18 && feature.ratio >= 0.30 &&
            feature.radial >= 0.16 && feature.contrastToPaper >= 6.0
        val score = (support * 0.42 + areaScore * 0.38 + shapeScore * 0.20) * if (passesShape) 1.0 else 0.35
        scoredRows.add(Triple(feature, support, score))
        if (passesShape && score > bestScore) {
            bestScore = score
            best = feature
        }
    }
    val selected = best ?: scoredRows.maxByOrNull { it.third }?.first
    val topRows = scoredRows.sortedByDescending { it.third }
    val diagnostics = topRows.take(20).mapIndexed { idx, row ->
        val isSel = selected?.let { s ->
            val dx = row.first.centerX - s.centerX
            val dy = row.first.centerY - s.centerY
            kotlin.math.sqrt(dx * dx + dy * dy) < 2 &&
                kotlin.math.abs(row.first.diameter - s.diameter) < 2
        } ?: false
        CoinCandidateDebug(
            rank = idx + 1,
            area = row.first.component.size.toDouble(),
            circularity = row.first.circularity,
            support = row.second,
            score = row.third,
            selected = isSel
        )
    }
    val overlays = topRows.take(20).mapIndexed { idx, row ->
        val isSel = selected?.let { s ->
            val dx = row.first.centerX - s.centerX
            val dy = row.first.centerY - s.centerY
            kotlin.math.sqrt(dx * dx + dy * dy) < 2 &&
                kotlin.math.abs(row.first.diameter - s.diameter) < 2
        } ?: false
        CoinCandidateOverlay(
            rank = idx + 1,
            centerX = row.first.centerX,
            centerY = row.first.centerY,
            radiusPx = (row.first.diameter * 0.5).toFloat(),
            selected = isSel
        )
    }
    return CoinSelectionResult(selected?.component, diagnostics, overlays)
}

internal fun collectCoinCandidateComponents(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    objectMask: ByteArray,
    width: Int,
    height: Int
): List<List<Int>> {
    val masks = ArrayList<ByteArray>()
    masks.add(objectMask)
    val deltas = listOf(2.0, 4.0, 6.0, 10.0, 16.0, 24.0, 36.0)
    for (delta in deltas) {
        val ti = kotlin.math.max(6, kotlin.math.min(245, (meanPaper - delta).toInt()))
        var darkMask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) darkMask[i] = if (gray.pix(i) < ti) 1 else 0
        }
        masks.add(darkMask)
        var deviationMask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) {
                val dev = kotlin.math.abs(gray.pix(i).toDouble() - meanPaper)
                deviationMask[i] = if (dev >= delta) 1 else 0
            }
        }
        masks.add(deviationMask)
    }

    val grad = gradientMagnitude(gray)
    val gradVals = ArrayList<Double>()
    for (i in grad.indices) {
        if (paperMask[i] != 0.toByte()) gradVals.add(grad[i])
    }
    if (gradVals.isNotEmpty()) {
        val meanG = gradVals.sum() / gradVals.size.toDouble()
        val varG = gradVals.sumOf {
            val d = it - meanG
            d * d
        } / gradVals.size.toDouble()
        val stdG = kotlin.math.sqrt(varG)
        val edgeThreshold = kotlin.math.max(5.0, meanG + stdG * 0.85)
        var edgeMask = ByteArray(gray.pixels.size)
        for (i in grad.indices) {
            if (paperMask[i] != 0.toByte()) edgeMask[i] = if (grad[i] >= edgeThreshold) 1 else 0
        }
        edgeMask = dilate(edgeMask, width, height, minNeighbors = 1)
        edgeMask = dilate(edgeMask, width, height, minNeighbors = 1)
        var edgeFilled = fillHoles(edgeMask, width, height)
        for (x in 0 until width) {
            edgeFilled[x] = 0
            edgeFilled[(height - 1) * width + x] = 0
        }
        for (y in 0 until height) {
            edgeFilled[y * width] = 0
            edgeFilled[y * width + (width - 1)] = 0
        }
        for (i in edgeFilled.indices) {
            if (paperMask[i] == 0.toByte()) edgeFilled[i] = 0
        }
        masks.add(edgeFilled)
    }

    val minArea = kotlin.math.max(80, (gray.pixels.size * 0.00015).toInt())
    val maxArea = (gray.pixels.size * 0.85).toInt()
    val allComponents = ArrayList<List<Int>>(120)
    for (mask in masks) {
        allComponents.addAll(
            connectedComponents(mask, width, height, minArea = minArea, maxArea = maxArea)
        )
    }
    return allComponents
}

internal fun detectCoinInROI(
    gray: GrayImage,
    meanPaper: Double,
    width: Int,
    height: Int,
    roi: PixelRect
): CoinSelectionResult {
    val minX = maxOf(0, minOf(width - 1, kotlin.math.floor(roi.left).toInt()))
    val maxX = maxOf(minX, minOf(width - 1, kotlin.math.ceil(roi.right).toInt() - 1))
    val minY = maxOf(0, minOf(height - 1, kotlin.math.floor(roi.top).toInt()))
    val maxY = maxOf(minY, minOf(height - 1, kotlin.math.ceil(roi.bottom).toInt() - 1))
    if (minX > maxX || minY > maxY) {
        return CoinSelectionResult(null, emptyList(), emptyList())
    }
    val bw = maxX - minX + 1
    val bh = maxY - minY + 1

    val deltas = listOf(4.0, 9.0, 16.0, 24.0, 33.0, 45.0, 60.0, 78.0, 105.0, 140.0)
    val results = ArrayList<Triple<Double, Int, List<Int>>>()

    for (delta in deltas) {
        val t = kotlin.math.max(4.0, meanPaper - delta)
        val localMask = ByteArray(bw * bh)
        for (y in minY..maxY) {
            for (x in minX..maxX) {
                if (gray.pix(y * width + x).toDouble() <= t) {
                    localMask[(y - minY) * bw + (x - minX)] = 1
                }
            }
        }
        val comps = connectedComponents(localMask, bw, bh, minArea = 30, maxArea = bw * bh)
        val largest = comps.maxByOrNull { it.size } ?: continue
        val globalPixels = largest.map { lx ->
            val x = lx % bw + minX
            val y = lx / bw + minY
            y * width + x
        }
        results.add(Triple(delta, largest.size, globalPixels))
    }
    if (results.isEmpty()) {
        return CoinSelectionResult(null, emptyList(), emptyList())
    }

    val gradient = gradientMagnitude(gray)
    val selectionScores = DoubleArray(results.size)
    results.forEachIndexed { idx, r ->
        val comp = r.third
        val feat = coinFeature(comp, width, height, gray, meanPaper)
        val edgeC = meanGradientOnContour(gradient, comp, width, height)
        selectionScores[idx] = scoreRoiCoinThresholdCandidate(feat, edgeC, idx, results)
    }

    var autoSelectedIndex = selectionScores.indices.maxByOrNull { selectionScores[it] }
        ?: (results.size - 1)

    if (selectionScores.maxOrNull()?.let { it < 0.28 } == true && results.size >= 2) {
        var fallback = results.size - 1
        for (i in 1 until results.size) {
            val prevArea = results[i - 1].second.toDouble()
            val currArea = results[i].second.toDouble()
            val growthRatio = if (prevArea > 0) (currArea - prevArea) / prevArea else 10.0
            if (growthRatio > 0.40 && prevArea >= 36) {
                fallback = i - 1
                break
            }
        }
        autoSelectedIndex = fallback
    }

    val diagnostics = ArrayList<CoinCandidateDebug>()
    val overlays = ArrayList<CoinCandidateOverlay>()
    results.take(10).forEachIndexed { idx, result ->
        val comp = result.third
        var sx = 0.0
        var sy = 0.0
        for (px in comp) {
            sx += (px % width).toDouble()
            sy += (px / width).toDouble()
        }
        val cx = sx / comp.size.toDouble()
        val cy = sy / comp.size.toDouble()
        val areaDiam = 2.0 * kotlin.math.sqrt(comp.size.toDouble() / kotlin.math.PI)
        var cMinX = width
        var cMaxX = 0
        var cMinY = height
        var cMaxY = 0
        for (px in comp) {
            val xPx = px % width
            val yPx = px / width
            if (xPx < cMinX) cMinX = xPx
            if (xPx > cMaxX) cMaxX = xPx
            if (yPx < cMinY) cMinY = yPx
            if (yPx > cMaxY) cMaxY = yPx
        }
        val spanDiam = ((cMaxX - cMinX + 1) + (cMaxY - cMinY + 1)).toDouble() * 0.5
        val diam = areaDiam * 0.65 + spanDiam * 0.35
        val isSel = idx == autoSelectedIndex
        val rankScore = if (idx < selectionScores.size) selectionScores[idx] else 0.0
        diagnostics.add(
            CoinCandidateDebug(
                rank = idx + 1,
                area = comp.size.toDouble(),
                circularity = result.first,
                support = diam,
                score = rankScore,
                selected = isSel
            )
        )
        overlays.add(
            CoinCandidateOverlay(
                rank = idx + 1,
                centerX = cx,
                centerY = cy,
                radiusPx = (diam * 0.5).toFloat(),
                selected = isSel
            )
        )
    }

    val selectedComp = results[autoSelectedIndex.coerceAtMost(results.size - 1)].third
    return CoinSelectionResult(selectedComp, diagnostics, overlays)
}

internal fun scoreRoiCoinThresholdCandidate(
    feature: CoinComponentFeature,
    edgeContour: Double,
    index: Int,
    results: List<Triple<Double, Int, List<Int>>>
): Double {
    val circ = kotlin.math.min(1.0, feature.circularity / 0.38)
    val radial = feature.radial
    val edgeN = kotlin.math.min(1.0, edgeContour / 28.0)
    val contrast = kotlin.math.min(1.0, feature.contrastToPaper / 26.0)
    val fill = feature.fill
    val ratio = kotlin.math.min(1.0, feature.ratio)

    var mergePenalty = 0.0
    if (index > 0) {
        val prev = results[index - 1].second.toDouble()
        val curr = results[index].second.toDouble()
        val g = if (prev > 0) (curr - prev) / prev else 0.0
        when {
            g > 0.60 -> mergePenalty += 0.48
            g > 0.42 -> mergePenalty += 0.26
            g > 0.30 -> mergePenalty += 0.10
        }
    }

    var plateauBonus = 0.0
    if (index >= 2) {
        val a0 = results[index - 2].second.toDouble()
        val a1 = results[index - 1].second.toDouble()
        val a2 = results[index].second.toDouble()
        val g0 = if (a0 > 0) (a1 - a0) / a0 else 0.0
        val g1 = if (a1 > 0) (a2 - a1) / a1 else 0.0
        if (g1 < 0.16 && g0 > 0.04 && g1 < g0 * 0.70) plateauBonus = 0.08
    }

    val maxAreaInt = results.maxOfOrNull { it.second } ?: 1
    val areaRatio = results[index].second.toDouble() / kotlin.math.max(maxAreaInt.toDouble(), 1.0)
    val tinyPenalty = if (areaRatio < 0.11 && results[index].second < 220) 0.14 else 0.0

    val shape = circ * 0.24 + radial * 0.26 + ratio * 0.08 + fill * 0.06
    val photo = edgeN * 0.22 + contrast * 0.12
    return shape + photo + plateauBonus - mergePenalty - tinyPenalty
}

internal fun detectCoinComponentForSuppression(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    objectMask: ByteArray,
    width: Int,
    height: Int,
    coinROI: PixelRect?
): CoinSelectionResult {
    if (coinROI != null) {
        return detectCoinInROI(gray, meanPaper, width, height, coinROI)
    }
    return detectCoinFromAllCandidates(
        gray, paperMask, meanPaper, objectMask, width, height
    )
}

internal fun effectiveCoinDiameterPx(diameterPx: Double, seedDiameter: Double, capFactor: Double): Double =
    kotlin.math.min(diameterPx, seedDiameter * capFactor) * AnalyzerConstants.COIN_DIAMETER_SCALE

internal fun refineCoinDiameterByRadialScan(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    centerX: Double,
    centerY: Double,
    seedDiameter: Double,
    width: Int,
    height: Int,
    coinROI: PixelRect?
): Double {
    val seedRadius = kotlin.math.max(4.0, seedDiameter * 0.5)
    val rMin = kotlin.math.max(8.0, seedRadius * 0.65)
    val rMax = kotlin.math.min(
        kotlin.math.min(width, height).toDouble() * 0.48,
        seedRadius * 3.2
    )
    if (rMax <= rMin + 2) return seedDiameter

    val radii = ArrayList<Double>()
    val angleCount = 72
    repeat(angleCount) { i ->
        val theta = 2.0 * kotlin.math.PI * i.toDouble() / angleCount.toDouble()
        val ux = kotlin.math.cos(theta)
        val uy = kotlin.math.sin(theta)
        var bestR = 0.0
        var bestScore = 0.0

        var prevR = rMin
        var prevI = sampleGray(gray, centerX + ux * prevR, centerY + uy * prevR)
        var prevDev = kotlin.math.abs(prevI - meanPaper)
        var r = rMin + 1.0
        while (r <= rMax) {
            val xx = centerX + ux * r
            val yy = centerY + uy * r
            if (xx < 1 || yy < 1 || xx >= width - 1 || yy >= height - 1) break
            if (coinROI != null && !coinROI.contains(xx, yy)) break
            val idx = yy.toInt() * width + xx.toInt()
            if (paperMask[idx] == 0.toByte()) break

            val currI = sampleGray(gray, xx, yy)
            val currDev = kotlin.math.abs(currI - meanPaper)
            val drop = maxOf(0.0, prevDev - currDev)
            val edge = kotlin.math.abs(currI - prevI)
            val score = drop * 0.72 + edge * 0.28
            if (score > bestScore) {
                bestScore = score
                bestR = r
            }
            prevR = r
            prevI = currI
            prevDev = currDev
            r += 1.0
        }
        if (bestR > 0 && bestScore >= 2.0) radii.add(bestR)
    }

    if (radii.size >= 18) {
        val sorted = radii.sorted()
        val median = sorted[sorted.size / 2]
        val refined = median * 2.0
        return kotlin.math.max(seedDiameter * 0.85, kotlin.math.min(seedDiameter * 1.75, refined))
    }
    return seedDiameter
}

internal fun coinGeometryFromComponent(
    component: List<Int>,
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    width: Int,
    height: Int,
    coinROI: PixelRect?
): CoinGeometry {
    var sx = 0.0
    var sy = 0.0
    for (idx in component) {
        sx += (idx % width).toDouble()
        sy += (idx / width).toDouble()
    }
    val cx = sx / component.size.toDouble()
    val cy = sy / component.size.toDouble()
    val seedDiameter = 2.0 * kotlin.math.sqrt(component.size.toDouble() / kotlin.math.PI)
    val refinedDiameter = refineCoinDiameterByRadialScan(
        gray, paperMask, meanPaper, cx, cy, seedDiameter, width, height, coinROI
    )
    return CoinGeometry(cx, cy, refinedDiameter, seedDiameter)
}

internal data class CoinGeometry(
    val centerX: Double,
    val centerY: Double,
    val diameterPx: Double,
    val seedDiameter: Double
)
