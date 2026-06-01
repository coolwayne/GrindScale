package com.grindscale.android.analysis

internal object AnalyzerConstants {
    const val MIN_AREA = 8
    const val MAX_AREA = 160_000
    const val COIN_DIAMETER_SCALE = 1.035
}

data class GrayImage(val width: Int, val height: Int, val pixels: UByteArray) {
    val pixelCount: Int get() = width * height

    operator fun component1() = width
    operator fun component2() = height
    operator fun component3() = pixels
}

internal fun UInt(px: Int): UByte {
    require(px in 0..255)
    return px.toUByte()
}

internal inline fun GrayImage.pix(i: Int): Int = pixels[i].toInt() and 0xFF

/** Pixel-space rectangle (analyzer coordinates match bitmap after scale). */
data class PixelRect(val left: Double, val top: Double, val width: Double, val height: Double) {
    val right: Double get() = left + width
    val bottom: Double get() = top + height

    fun contains(x: Double, y: Double): Boolean =
        x >= left && x <= right && y >= top && y <= bottom
}

/**
 * Normalized ROI matching Swift ROIImageEditor output: origin (nx, ny) and size (nw, nh) in 0…1 relative
 * to the displayed image bitmap (same as UIImage analysis space).
 */
data class NormalizedRoi(val nx: Float, val ny: Float, val nw: Float, val nh: Float)

internal fun normalizedRoiToPixelRect(roi: NormalizedRoi, width: Int, height: Int): PixelRect {
    val x0 = roi.nx.coerceIn(0f, 1f).toDouble()
    val y0 = roi.ny.coerceIn(0f, 1f).toDouble()
    val x1 = (roi.nx + roi.nw).coerceIn(0f, 1f).toDouble()
    val y1 = (roi.ny + roi.nh).coerceIn(0f, 1f).toDouble()
    val minX = minOf(x0, x1) * width
    val minY = minOf(y0, y1) * height
    val maxX = maxOf(x0, x1) * width
    val maxY = maxOf(y0, y1) * height
    val w = kotlin.math.max(1.0, maxX - minX)
    val h = kotlin.math.max(1.0, maxY - minY)
    return PixelRect(minX, minY, w, h)
}
