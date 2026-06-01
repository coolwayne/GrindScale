package com.grindscale.android.analysis

internal fun coinCandidateFromComponent(component: List<Int>, width: Int, height: Int): InternalCoinCandidate? {
    val area = component.size.toDouble()
    if (area <= 0) return null

    val areaDiameter = 2.0 * kotlin.math.sqrt(area / kotlin.math.PI)
    val minImageDim = kotlin.math.min(width, height).toDouble()
    if (areaDiameter < kotlin.math.max(20.0, minImageDim * 0.04)) return null
    if (areaDiameter > minImageDim * 0.92) return null

    val circ = circularity(component, width, height)
    val ratio = aspectRatioScore(component, width)
    val fill = boundingBoxFillRatio(component, width)
    if (circ < 0.25 || ratio < 0.50 || fill < 0.18) return null

    val contour = contourPointsForComponent(component, width, height)
    if (contour.size < 12) return null

    var sx = 0.0
    var sy = 0.0
    for (idx in component) {
        sx += (idx % width).toDouble()
        sy += (idx / width).toDouble()
    }
    val cx = sx / component.size.toDouble()
    val cy = sy / component.size.toDouble()

    val radii = DoubleArray(contour.size)
    var ri = 0
    for (p in contour) {
        val dx = p.first.toDouble() - cx
        val dy = p.second.toDouble() - cy
        radii[ri++] = kotlin.math.sqrt(dx * dx + dy * dy)
    }
    val meanR = radii.sum() / radii.size
    if (meanR < 6.0) return null
    val varR = radii.sumOf {
        val d = it - meanR
        d * d
    } / radii.size.toDouble()
    val stdR = kotlin.math.sqrt(varR)
    val radial = (1.0 - stdR / kotlin.math.max(meanR, 1e-6)).coerceIn(0.0, 1.0)
    if (radial < 0.30) return null

    val contourDiameter = meanR * 2.0
    val diameter = 0.65 * contourDiameter + 0.35 * areaDiameter
    val sizeScore = kotlin.math.min(1.0, diameter / (minImageDim * 0.28))
    val score = radial * 0.40 + circ * 0.26 + ratio * 0.16 + fill * 0.08 + sizeScore * 0.10
    return InternalCoinCandidate(diameter, score)
}

internal fun weightedMedianDiameter(candidates: List<InternalCoinCandidate>): Double? {
    if (candidates.isEmpty()) return null
    val top = candidates.sortedByDescending { it.score }.take(9)
    if (top.isEmpty()) return null
    val maxDiameter = top.maxOfOrNull { it.diameterPx } ?: 0.0
    val largeTop = top.filter { it.diameterPx >= kotlin.math.max(18.0, maxDiameter * 0.62) }
    val effective = if (largeTop.isEmpty()) top else largeTop

    val sortedByDiameter = effective.sortedBy { it.diameterPx }
    val totalWeight = sortedByDiameter.sumOf { kotlin.math.max(0.001, it.score) }
    var acc = 0.0
    for (c in sortedByDiameter) {
        acc += kotlin.math.max(0.001, c.score)
        if (acc >= totalWeight * 0.5) return c.diameterPx
    }
    return sortedByDiameter.lastOrNull()?.diameterPx
}

internal fun isValidUmPerPx(value: Double): Boolean =
    value in 1.0..450.0

internal fun detectCoinDiameterPxPermissive(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    objectMask: ByteArray
): Double? {
    val masks = ArrayList<ByteArray>()
    masks.add(objectMask)
    for (delta in listOf(5.0, 8.0, 12.0, 16.0, 22.0)) {
        val ti = kotlin.math.max(10, kotlin.math.min(245, (meanPaper - delta).toInt()))
        val mask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) mask[i] = if (gray.pix(i) < ti) 1 else 0
        }
        masks.add(mask)
    }

    val minArea = kotlin.math.max(120, (gray.pixels.size * 0.00035).toInt())
    val maxArea = (gray.pixels.size * 0.55).toInt()
    val candidates = ArrayList<InternalCoinCandidate>()
    for (mask in masks) {
        val components = connectedComponents(mask, gray.width, gray.height, minArea, maxArea)
        for (component in components) {
            val cand = coinCandidateFromComponent(component, gray.width, gray.height) ?: continue
            candidates.add(cand)
        }
    }
    return weightedMedianDiameter(candidates)
}

internal fun detectCoinDiameterPxFromShadow(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double
): Double? {
    val deltas = listOf(6.0, 8.0, 10.0, 12.0, 15.0, 18.0, 22.0)
    val candidates = ArrayList<InternalCoinCandidate>()
    for (delta in deltas) {
        val ti = kotlin.math.max(12, kotlin.math.min(245, (meanPaper - delta).toInt()))
        val shadowMask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) shadowMask[i] = if (gray.pix(i) < ti) 1 else 0
        }
        val minArea = kotlin.math.max(180, (gray.pixels.size * 0.0006).toInt())
        val maxArea = (gray.pixels.size * 0.45).toInt()
        val components = connectedComponents(shadowMask, gray.width, gray.height, minArea, maxArea)
        for (component in components) {
            val base = coinCandidateFromComponent(component, gray.width, gray.height) ?: continue
            val meanObject = meanIntensityForComponent(gray, component)
            val contrast = maxOf(0.0, meanPaper - meanObject)
            val contrastScore = kotlin.math.min(1.0, contrast / 38.0)
            val score = base.score * 0.82 + contrastScore * 0.18
            candidates.add(InternalCoinCandidate(base.diameterPx, score))
        }
    }
    return weightedMedianDiameter(candidates)
}

internal fun detectCoinDiameterPxByLargestObject(
    objectMask: ByteArray,
    width: Int,
    height: Int
): Double? {
    val minArea = kotlin.math.max(100, (objectMask.size * 0.00025).toInt())
    val maxArea = (objectMask.size * 0.70).toInt()
    val components = connectedComponents(objectMask, width, height, minArea, maxArea)
    if (components.isEmpty()) return null

    var maxDiameter = 0.0
    for (comp in components) {
        val d = 2.0 * kotlin.math.sqrt(comp.size.toDouble() / kotlin.math.PI)
        if (d > maxDiameter) maxDiameter = d
    }
    val minCoinDiameter = kotlin.math.max(18.0, maxDiameter * 0.60)

    var bestDiameter: Double? = null
    var bestScore = -1.0
    for (comp in components) {
        val area = comp.size.toDouble()
        val diameter = 2.0 * kotlin.math.sqrt(area / kotlin.math.PI)
        if (diameter < minCoinDiameter) continue
        val circ = circularity(comp, width, height)
        val ratio = aspectRatioScore(comp, width)
        if (circ < 0.20 || ratio < 0.45) continue
        val fill = boundingBoxFillRatio(comp, width)
        val sizeDominance =
            if (maxDiameter > 0) kotlin.math.min(1.0, diameter / maxDiameter) else 0.0
        val score = sizeDominance * 0.55 + kotlin.math.max(0.0, circ) * 0.24 + ratio * 0.15 + fill * 0.06
        if (score > bestScore) {
            bestScore = score
            bestDiameter = diameter
        }
    }
    return bestDiameter
}

internal fun detectCoinDiameterPxUltimate(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double
): Double? {
    val candidates = ArrayList<InternalCoinCandidate>()
    val deltas = mutableListOf(4, 6, 8, 10, 12, 15, 18, 22, 28, 36, 44)
    val otsu = ImageProcessing.otsuThreshold(gray).toInt() and 0xFF
    deltas.add(kotlin.math.max(2, meanPaper.toInt() - otsu))

    val minArea = kotlin.math.max(80, (gray.pixels.size * 0.00018).toInt())
    val maxArea = (gray.pixels.size * 0.78).toInt()
    for (delta in deltas) {
        val t = kotlin.math.max(6, kotlin.math.min(245, meanPaper.toInt() - delta))
        val mask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) mask[i] = if (gray.pix(i) < t) 1 else 0
        }
        val components = connectedComponents(mask, gray.width, gray.height, minArea, maxArea)
        for (comp in components) {
            val cand = coinCandidateFromComponent(comp, gray.width, gray.height) ?: continue
            candidates.add(cand)
        }
    }
    weightedMedianDiameter(candidates)?.let { return it }

    val looseT = kotlin.math.max(6, kotlin.math.min(245, meanPaper.toInt() - 6))
    val looseMask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] != 0.toByte()) looseMask[i] = if (gray.pix(i) < looseT) 1 else 0
    }
    val looseComponents =
        connectedComponents(looseMask, gray.width, gray.height, minArea, maxArea)
    val largest = looseComponents.maxByOrNull { it.size } ?: return null
    val diameter = 2.0 * kotlin.math.sqrt(largest.size.toDouble() / kotlin.math.PI)
    return if (diameter > 8) diameter else null
}

internal fun detectCoinDiameterPxByPaperDeviation(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double
): Double? {
    val minArea = kotlin.math.max(80, (gray.pixels.size * 0.00015).toInt())
    val maxArea = (gray.pixels.size * 0.85).toInt()
    var bestDiameter: Double? = null
    var bestScore = -1.0

    for (delta in listOf(5.0, 8.0, 12.0, 16.0, 22.0, 30.0, 40.0)) {
        val mask = ByteArray(gray.pixels.size)
        for (i in gray.pixels.indices) {
            if (paperMask[i] != 0.toByte()) {
                val dev = kotlin.math.abs(gray.pix(i).toDouble() - meanPaper)
                mask[i] = if (dev >= delta) 1 else 0
            }
        }
        val components = connectedComponents(mask, gray.width, gray.height, minArea, maxArea)
        var maxD = 0.0
        for (comp in components) {
            val d = 2.0 * kotlin.math.sqrt(comp.size.toDouble() / kotlin.math.PI)
            if (d > maxD) maxD = d
        }
        val minCoinD = kotlin.math.max(18.0, maxD * 0.60)
        for (comp in components) {
            val area = comp.size.toDouble()
            val diameter = 2.0 * kotlin.math.sqrt(area / kotlin.math.PI)
            if (diameter < minCoinD) continue
            val circ = circularity(comp, gray.width, gray.height)
            val ratio = aspectRatioScore(comp, gray.width)
            val fill = boundingBoxFillRatio(comp, gray.width)
            val sizeDom = if (maxD > 0) kotlin.math.min(1.0, diameter / maxD) else 0.0
            val score = sizeDom * 0.55 + kotlin.math.max(0.0, circ) * 0.25 + ratio * 0.14 + fill * 0.06
            if (score > bestScore) {
                bestScore = score
                bestDiameter = diameter
            }
        }
    }
    return bestDiameter
}

internal fun estimateUmPerPx(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    objectMask: ByteArray,
    referenceDiameterMM: Double?,
    coinRoiPixel: PixelRect?
): Double? {
    val refMm = referenceDiameterMM ?: return null
    if (refMm <= 0) return null

    if (coinRoiPixel != null) {
        val roiResult = detectCoinInROI(gray, meanPaper, gray.width, gray.height, coinRoiPixel)
        val comp = roiResult.component ?: return null
        val geometry = coinGeometryFromComponent(
            comp, gray, paperMask, meanPaper, gray.width, gray.height, coinRoiPixel
        )
        val diameterPx = effectiveCoinDiameterPx(
            diameterPx = geometry.diameterPx,
            seedDiameter = geometry.seedDiameter,
            capFactor = 1.20
        )
        val umPerPx = refMm * 1000.0 / kotlin.math.max(1.0, diameterPx)
        return umPerPx.takeIf { isValidUmPerPx(it) }
    }

    detectCoinComponentForSuppression(
        gray, paperMask, meanPaper, objectMask, gray.width, gray.height, null
    ).component?.let { coinComp ->
        val geometry =
            coinGeometryFromComponent(coinComp, gray, paperMask, meanPaper, gray.width, gray.height, null)
        val diameterPx = effectiveCoinDiameterPx(
            diameterPx = geometry.diameterPx,
            seedDiameter = geometry.seedDiameter,
            capFactor = 1.25
        )
        val umPerPx = refMm * 1000.0 / kotlin.math.max(1.0, diameterPx)
        if (isValidUmPerPx(umPerPx)) return umPerPx
    }

    detectCoinDiameterPxPermissive(gray, paperMask, meanPaper, objectMask)?.let { px ->
        val u = refMm * 1000.0 / px
        if (isValidUmPerPx(u)) return u
    }
    detectCoinDiameterPxFromShadow(gray, paperMask, meanPaper)?.let { px ->
        val u = refMm * 1000.0 / px
        if (isValidUmPerPx(u)) return u
    }

    val components = connectedComponents(
        objectMask,
        gray.width,
        gray.height,
        minArea = 500,
        maxArea = (gray.pixelCount * 0.35).toInt()
    )
    if (components.isEmpty()) return null

    var bestDiameterPx: Double? = null
    var bestScore = 0.0
    for (component in components) {
        val cand = coinCandidateFromComponent(component, gray.width, gray.height) ?: continue
        if (cand.score <= bestScore) continue
        bestScore = cand.score
        bestDiameterPx = cand.diameterPx
    }
    val bd = bestDiameterPx
    if (bd == null || bd <= 0) return null
    val umFromCand = refMm * 1000.0 / bd
    if (isValidUmPerPx(umFromCand)) return umFromCand

    detectCoinDiameterPxByLargestObject(objectMask, gray.width, gray.height)?.let { px ->
        val u = refMm * 1000.0 / px
        if (isValidUmPerPx(u)) return u
    }
    detectCoinDiameterPxUltimate(gray, paperMask, meanPaper)?.let { px ->
        val u = refMm * 1000.0 / px
        if (u > 0.2 && u < 1000) return u
    }
    detectCoinDiameterPxByPaperDeviation(gray, paperMask, meanPaper)?.let { px ->
        val u = refMm * 1000.0 / px
        if (u > 0.1 && u < 1500) return u
    }
    return null
}
