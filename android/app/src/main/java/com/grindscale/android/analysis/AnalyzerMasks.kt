package com.grindscale.android.analysis

internal fun detectPaperMask(gray: GrayImage): ByteArray {
    val otsu = ImageProcessing.otsuThreshold(gray).toInt() and 0xFF
    val threshold = maxOf(160, minOf(245, otsu + 18)).toUInt().toUByte()
    val brightMask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        brightMask[i] = if ((gray.pix(i)).toUInt() >= threshold.toUInt()) 1 else 0
    }
    val pixelCount = gray.pixelCount
    val components = connectedComponents(
        mask = brightMask,
        width = gray.width,
        height = gray.height,
        minArea = maxOf(1000, (pixelCount * 0.12).toInt()),
        maxArea = pixelCount
    )
    val paper = components.maxByOrNull { it.size }
        ?: return ByteArray(pixelCount) { 1 }

    val coverage = paper.size.toDouble() / pixelCount.toDouble()
    if (coverage < 0.15) return ByteArray(pixelCount) { 1 }

    val coarseMask = ByteArray(pixelCount)
    for (idx in paper) coarseMask[idx] = 1
    return fillHoles(coarseMask, gray.width, gray.height)
}

internal fun meanIntensity(gray: GrayImage, mask: ByteArray): Double {
    var sum = 0.0
    var count = 0
    for (i in gray.pixels.indices) {
        if (mask[i] != 0.toByte()) {
            sum += gray.pix(i).toDouble()
            count++
        }
    }
    return if (count > 0) sum / count else 200.0
}

internal fun stdIntensity(gray: GrayImage, mask: ByteArray, mean: Double): Double {
    var sum = 0.0
    var count = 0
    for (i in gray.pixels.indices) {
        if (mask[i] != 0.toByte()) {
            val diff = gray.pix(i).toDouble() - mean
            sum += diff * diff
            count++
        }
    }
    return if (count > 0) kotlin.math.sqrt(sum / count.toDouble()) else 0.0
}

internal fun makeObjectMask(gray: GrayImage, paperMask: ByteArray, meanPaper: Double): ByteArray {
    val t = maxOf(35, minOf(220, (meanPaper - 22).toInt()))
    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] != 0.toByte()) mask[i] = if (gray.pix(i) < t) 1 else 0
    }
    return mask
}

internal fun makeParticleMask(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    stdPaper: Double,
    otsuThreshold: UByte
): ByteArray {
    val delta = maxOf(7.0, minOf(40.0, stdPaper * 0.52))
    val adaptiveThreshold = maxOf(10, minOf(220, (meanPaper - delta).toInt()))
    val otsuSoft = maxOf(8, (otsuThreshold.toInt() and 0xFF) - 20)
    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        val px = gray.pix(i)
        mask[i] = if (px < adaptiveThreshold || px < otsuSoft) 1 else 0
    }
    return mask
}

internal fun makeParticleMaskFromNormalized(normalized: GrayImage, paperMask: ByteArray): ByteArray {
    val otsu = ImageProcessing.otsuThreshold(normalized).toInt() and 0xFF
    val threshold = maxOf(50, minOf(185, otsu - 12))
    val mask = ByteArray(normalized.pixels.size)
    for (i in normalized.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        mask[i] = if ((normalized.pix(i)) < threshold) 1 else 0
    }
    return mask
}

internal fun makeParticleMaskContrastLoose(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    stdPaper: Double
): ByteArray {
    val t = maxOf(5.0, minOf(29.0, 4.25 + stdPaper * 0.27))
    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        val contrast = meanPaper - gray.pix(i).toDouble()
        mask[i] = if (contrast >= t) 1 else 0
    }
    return mask
}

internal fun makeParticleMaskSupplemental(
    gray: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    stdPaper: Double
): ByteArray {
    val soft = maxOf(2.28, minOf(16.0, 1.58 + stdPaper * 0.16))
    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        val diff = meanPaper - gray.pix(i).toDouble()
        mask[i] = if (diff >= soft) 1 else 0
    }
    return mask
}

internal fun makeParticleMaskLooseOtsu(
    gray: GrayImage,
    paperMask: ByteArray,
    globalOtsu: UByte
): ByteArray {
    val thr = maxOf(6, minOf(235, (globalOtsu.toInt() and 0xFF) - 14))
    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        mask[i] = if (gray.pix(i) < thr) 1 else 0
    }
    return mask
}

internal fun buildParticleMaskRobust(
    gray: GrayImage,
    normalized: GrayImage,
    paperMask: ByteArray,
    meanPaper: Double,
    stdPaper: Double,
    globalOtsu: UByte
): ByteArray {
    val background = ImageProcessing.boxBlur(gray, radius = 8)
    val darknessPixels = UByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        val d = maxOf(0, background.pix(i) - gray.pix(i))
        darknessPixels[i] = minOf(255, d).toUInt().toUByte()
    }
    val darkness = GrayImage(gray.width, gray.height, darknessPixels)
    val darkOtsu = ImageProcessing.otsuThreshold(darkness).toInt() and 0xFF
    val darkThreshold = maxOf(2, minOf(90, ((darkOtsu * 0.53).toInt() + 1)))
    val contrastMin = maxOf(1.5, minOf(16.0, 1.78 + stdPaper * 0.16))
    val absoluteThreshold = maxOf(4, (globalOtsu.toInt() and 0xFF) - 22)

    val mask = ByteArray(gray.pixels.size)
    for (i in gray.pixels.indices) {
        if (paperMask[i] == 0.toByte()) continue
        val darkPass = (darknessPixels[i].toInt() and 0xFF) >= darkThreshold
        val diff = meanPaper - gray.pix(i).toDouble()
        val absPass = gray.pix(i) <= absoluteThreshold
        val darkContrast = darkPass && diff >= contrastMin
        mask[i] = if (darkContrast || absPass) 1 else 0
    }

    var merged = mergeMasks(
        mask,
        makeParticleMask(gray, paperMask, meanPaper, stdPaper, globalOtsu)
    )
    merged = mergeMasks(merged, makeParticleMaskSupplemental(gray, paperMask, meanPaper, stdPaper))
    merged = mergeMasks(merged, makeParticleMaskFromNormalized(normalized, paperMask))
    merged = mergeMasks(merged, makeParticleMaskContrastLoose(gray, paperMask, meanPaper, stdPaper))
    merged = mergeMasks(merged, makeParticleMaskLooseOtsu(gray, paperMask, globalOtsu))

    val opened = erode(merged, gray.width, gray.height, minNeighbors = 2)
    var recovered = dilate(opened, gray.width, gray.height, minNeighbors = 2)
    recovered = dilate(recovered, gray.width, gray.height, minNeighbors = 2)
    return recovered
}
