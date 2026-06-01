package com.grindscale.android.analysis

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

internal fun resemblesCoffeeGroundParticle(
    contrastBase: Double,
    stdBase: Double,
    edgeBase: Double,
    area: Int
): Boolean {
    if (contrastBase >= 40) return true
    if (contrastBase >= 28 && stdBase >= 4.8) return true
    if (contrastBase >= 24 && edgeBase >= 10.5) return true
    if (area >= 90 && contrastBase >= 26 && stdBase >= 4.5) return true
    if (area >= 140 && contrastBase >= 21 && stdBase >= 4.9) return true
    if (area >= 200 && contrastBase >= 17 && stdBase >= 4.0 && edgeBase >= 7.5) return true
    return false
}

internal fun plausibleCoarseCoffeeGround(
    contrastBase: Double,
    stdBase: Double,
    edgeBase: Double,
    area: Int,
    fill: Double
): Boolean {
    if (resemblesCoffeeGroundParticle(contrastBase, stdBase, edgeBase, area)) return true
    if (area >= 220 && contrastBase >= 15 && stdBase >= 3.8 && fill > 0.28) return true
    if (area >= 150 && contrastBase >= 18 && fill > 0.32) return true
    if (area >= 320 && contrastBase >= 13 && edgeBase >= 7.0) return true
    return false
}

internal fun isLikelyPaperFiberTexture(
    component: List<Int>,
    grayBase: GrayImage,
    gradientBase: DoubleArray,
    width: Int,
    height: Int,
    meanPaper: Double
): Boolean {
    val area = component.size
    if (area !in 8..520) return false

    val stdBase = stdIntensityForComponent(grayBase, component)
    val edgeBase = meanGradientForComponent(gradientBase, component)
    val meanObjBase = meanIntensityForComponent(grayBase, component)
    val contrastBase = max(0.0, meanPaper - meanObjBase)
    val fill = boundingBoxFillRatio(component, width)
    if (plausibleCoarseCoffeeGround(contrastBase, stdBase, edgeBase, area, fill)) return false

    val ar = aspectRatioScore(component, width)
    val circ = circularity(component, width, height)
    val (bw, bh) = boundingBoxExtent(component, width)
    val shortSide = minOf(bw, bh)
    val longSide = maxOf(bw, bh)
    val elongation = longSide.toDouble() / max(shortSide, 1).toDouble()

    if (shortSide <= 3 && longSide >= 7 && elongation >= 2.4 && area < 260 && stdBase < 6.5) {
        if (contrastBase < 42 && edgeBase < 14.0) return true
    }
    if (ar < 0.18 && area < 280 && circ < 0.14 && fill < 0.42 && stdBase < 6.5 && edgeBase < 13.5) {
        return true
    }
    if (ar < 0.24 && area < 200 && fill < 0.38 && circ < 0.16 && contrastBase < 36 && edgeBase < 12.0) {
        return true
    }
    if (area <= 48 && ar > 0.45 && circ > 0.30 && contrastBase < 22 && edgeBase < 10.0 && stdBase < 5.2) {
        return true
    }
    return false
}

internal data class GradientBorderInterior(
    val borderMean: Double,
    val interiorMean: Double,
    val interiorCount: Int
)

internal fun meanGradientBorderInterior(
    gradient: DoubleArray,
    component: List<Int>,
    width: Int,
    height: Int
): GradientBorderInterior {
    val set = component.toHashSet()
    val neighbors = listOf(Pair(-1, 0), Pair(1, 0), Pair(0, -1), Pair(0, 1))
    var borderSum = 0.0
    var borderCount = 0
    var interiorSum = 0.0
    var interiorCount = 0
    for (idx in component) {
        val y = idx / width
        val x = idx % width
        var isBorder = false
        for ((dy, dx) in neighbors) {
            val nx = x + dx
            val ny = y + dy
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) {
                isBorder = true
                break
            }
            val ni = ny * width + nx
            if (!set.contains(ni)) {
                isBorder = true
                break
            }
        }
        val g = gradient[idx]
        if (isBorder) {
            borderSum += g
            borderCount++
        } else {
            interiorSum += g
            interiorCount++
        }
    }
    val b = if (borderCount > 0) borderSum / borderCount else 0.0
    val iIn = if (interiorCount > 0) interiorSum / interiorCount else 0.0
    return GradientBorderInterior(b, iIn, interiorCount)
}

internal fun isLikelyPaperShadow(
    component: List<Int>,
    grayBase: GrayImage,
    gradientBase: DoubleArray,
    width: Int,
    height: Int,
    meanPaper: Double
): Boolean {
    val area = component.size
    if (area < 55) return false

    val stdBase = stdIntensityForComponent(grayBase, component)
    val circ = circularity(component, width, height)
    val fill = boundingBoxFillRatio(component, width)
    val gMean = meanGradientForComponent(gradientBase, component)
    val meanObjBase = meanIntensityForComponent(grayBase, component)
    val contrastBase = max(0.0, meanPaper - meanObjBase)
    if (plausibleCoarseCoffeeGround(contrastBase, stdBase, gMean, area, fill)) return false

    val ar = aspectRatioScore(component, width)
    val gbi = meanGradientBorderInterior(gradientBase, component, width, height)
    val borderG = gbi.borderMean
    val interiorG = gbi.interiorMean
    val interiorCount = gbi.interiorCount

    if (area >= 85 && interiorCount >= 5 && interiorG < 4.6 && borderG > 6.2 &&
        borderG > interiorG * 1.62 && stdBase < 6.4
    ) {
        return true
    }
    if (area >= 160 && ar < 0.30 && stdBase < 6.5 && fill < 0.48 && gMean < 15.5 && circ < 0.23) {
        return true
    }
    if (area >= 260 && stdBase < 5.5 && circ < 0.17 && fill < 0.48) return true
    if (area >= 360 && stdBase < 5.3 && circ < 0.168 && fill < 0.47) return true
    if (area >= 400 && ar < 0.26 && stdBase < 5.8 && fill < 0.44 && gMean < 14.5) return true
    if (area >= 160 && interiorCount >= 10 && interiorG < 4.3 && borderG > 6.8 &&
        borderG > interiorG * 1.88 + 0.35
    ) {
        return true
    }
    if (area >= 900 && stdBase < 6.8 && fill < 0.44 && contrastBase < 56 && gMean < 11.0) return true
    if (area >= 1500 && stdBase < 7.0 && fill < 0.50 && contrastBase < 54 && gMean < 13.0) return true
    return false
}

internal fun isLikelyImagingNoise(
    component: List<Int>,
    grayBase: GrayImage,
    meanPaper: Double,
    width: Int,
    height: Int
): Boolean {
    val area = component.size
    if (area > 28) return false
    val meanObjBase = meanIntensityForComponent(grayBase, component)
    val contrastBase = max(0.0, meanPaper - meanObjBase)
    val stdBase = stdIntensityForComponent(grayBase, component)
    val circ = circularity(component, width, height)
    if (area <= 4) return contrastBase < 10.0
    if (area <= 18 && contrastBase < 9.5 && stdBase < 2.2) return true
    if (area <= 26 && contrastBase < 11.0 && stdBase < 2.0 && circ < 0.42) return true
    return false
}

internal fun isLikelyAgglomeratedFineCluster(
    circularityVal: Double,
    bboxFill: Double,
    aspectRatio: Double
): Boolean {
    if (circularityVal < 0.36 && bboxFill < 0.34) return true
    if (circularityVal < 0.30 && bboxFill < 0.42) return true
    if (circularityVal < 0.42 && bboxFill < 0.26) return true
    if (aspectRatio < 0.34 && circularityVal < 0.22 && bboxFill < 0.40) return true
    return false
}

internal fun isLikelyParticle(
    component: List<Int>,
    gray: GrayImage,
    gradient: DoubleArray,
    width: Int,
    height: Int,
    meanPaper: Double,
    grayBase: GrayImage,
    gradientBase: DoubleArray
): Boolean {
    if (isLikelyImagingNoise(component, grayBase, meanPaper, width, height)) return false
    if (isLikelyPaperFiberTexture(component, grayBase, gradientBase, width, height, meanPaper)) {
        return false
    }
    if (isLikelyPaperShadow(component, grayBase, gradientBase, width, height, meanPaper)) {
        return false
    }

    val area = component.size
    if (area < AnalyzerConstants.MIN_AREA || area > AnalyzerConstants.MAX_AREA) return false

    val circ = circularity(component, width, height)
    val ratio = aspectRatioScore(component, width)
    val meanObj = meanIntensityForComponent(gray, component)
    val contrast = max(0.0, meanPaper - meanObj)
    val edge = meanGradientForComponent(gradient, component)

    val meanObjBase = meanIntensityForComponent(grayBase, component)
    val contrastBase = max(0.0, meanPaper - meanObjBase)
    val stdBase = stdIntensityForComponent(grayBase, component)
    val edgeBase = meanGradientForComponent(gradientBase, component)
    val fillParticle = boundingBoxFillRatio(component, width)
    val qi = meanGradientBorderInterior(gradientBase, component, width, height)
    val bGrad = qi.borderMean
    val iGrad = qi.interiorMean
    val iCount = qi.interiorCount

    if (area >= 140 && contrastBase >= 6.0 && contrastBase < 44 && stdBase < 5.6 &&
        edgeBase < 11.2 && circ < 0.21
    ) {
        if (edgeBase < 8.5 || (iCount >= 6 && iGrad < 4.8 && bGrad > iGrad * 1.4)) {
            if (!plausibleCoarseCoffeeGround(contrastBase, stdBase, edgeBase, area, fillParticle)) {
                return false
            }
        }
    }

    var score = 0.09
    score += minOf(1.0, contrast / 26.0) * 0.58
    score += minOf(1.0, edge / 28.0) * 0.30
    score += minOf(1.0, max(0.0, circ) / 0.42) * 0.09
    score += minOf(1.0, ratio / 0.62) * 0.05
    if (area >= 190) score += 0.035
    if (area >= 380) score += 0.025

    if (contrast < 1.0 && edge < 1.75) return false
    if (area > 580 && ratio < 0.045 && circ < 0.022) return false

    val passThreshold = if (area >= 200) 0.068 else 0.075
    return score >= passThreshold
}
