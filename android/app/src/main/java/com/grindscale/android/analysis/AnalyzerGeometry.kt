package com.grindscale.android.analysis

import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

internal fun localContrastNormalize(
    gray: GrayImage,
    backgroundRadius: Int,
    gain: Double
): GrayImage {
    val bg = ImageProcessing.boxBlur(gray, radius = backgroundRadius)
    val out = gray.pixels.copyOf()
    for (i in out.indices) {
        val v = (gray.pixels[i].toInt() and 0xFF).toDouble()
        val b = (bg.pixels[i].toInt() and 0xFF).toDouble()
        val corrected = 128.0 + (v - b) * gain
        val c = corrected.roundToIntBounded()
        out[i] = c.toUByte()
    }
    return GrayImage(gray.width, gray.height, out)
}

private fun Double.roundToIntBounded(): Int =
    coerceIn(0.0, 255.0).let { kotlin.math.round(it).toInt() }

internal fun gradientMagnitude(gray: GrayImage): DoubleArray {
    val w = gray.width
    val h = gray.height
    val out = DoubleArray(gray.pixels.size)
    if (w < 3 || h < 3) return out
    for (y in 1 until h - 1) {
        for (x in 1 until w - 1) {
            val idx = y * w + x
            val gx = gray.pix(idx + 1) - gray.pix(idx - 1)
            val gy = gray.pix(idx + w) - gray.pix(idx - w)
            out[idx] = sqrt((gx * gx + gy * gy).toDouble())
        }
    }
    return out
}

internal fun boundingBoxExtent(component: List<Int>, width: Int): Pair<Int, Int> {
    val first = component.firstOrNull() ?: return Pair(1, 1)
    var minX = first % width
    var maxX = minX
    var minY = first / width
    var maxY = minY
    for (idx in component) {
        val x = idx % width
        val y = idx / width
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
    }
    return Pair(maxX - minX + 1, maxY - minY + 1)
}

internal fun meanIntensityForComponent(gray: GrayImage, component: List<Int>): Double {
    if (component.isEmpty()) return 255.0
    var sum = 0.0
    for (idx in component) sum += gray.pix(idx).toDouble()
    return sum / component.size.toDouble()
}

internal fun stdIntensityForComponent(gray: GrayImage, component: List<Int>): Double {
    if (component.size < 2) return 0.0
    val mean = meanIntensityForComponent(gray, component)
    var acc = 0.0
    for (idx in component) {
        val d = gray.pix(idx).toDouble() - mean
        acc += d * d
    }
    return sqrt(acc / component.size.toDouble())
}

internal fun circularity(component: List<Int>, width: Int, height: Int): Double {
    val area = component.size.toDouble()
    if (area <= 0) return 0.0
    val set = component.toHashSet()
    val offsets = listOf(Pair(-1, 0), Pair(1, 0), Pair(0, -1), Pair(0, 1))
    var perimeter = 0.0
    for (idx in component) {
        val y = idx / width
        val x = idx % width
        for ((dy, dx) in offsets) {
            val ny = y + dy
            val nx = x + dx
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) {
                perimeter += 1
                continue
            }
            val ni = ny * width + nx
            if (!set.contains(ni)) perimeter += 1
        }
    }
    if (perimeter <= 0) return 0.0
    return (4.0 * PI * area) / (perimeter * perimeter)
}

internal fun aspectRatioScore(component: List<Int>, width: Int): Double {
    val first = component.firstOrNull() ?: return 0.0
    var minX = first % width
    var maxX = minX
    var minY = first / width
    var maxY = minY
    for (idx in component) {
        val x = idx % width
        val y = idx / width
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
    }
    val w = max(1, maxX - minX + 1)
    val h = max(1, maxY - minY + 1)
    return min(w, h).toDouble() / max(w, h).toDouble()
}

internal fun boundingBoxFillRatio(component: List<Int>, width: Int): Double {
    val first = component.firstOrNull() ?: return 0.0
    var minX = first % width
    var maxX = minX
    var minY = first / width
    var maxY = minY
    for (idx in component) {
        val x = idx % width
        val y = idx / width
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
    }
    val bw = max(1, maxX - minX + 1)
    val bh = max(1, maxY - minY + 1)
    return component.size.toDouble() / (bw * bh).toDouble()
}

internal fun contourPointsForComponent(component: List<Int>, width: Int, height: Int): List<Pair<Float, Float>> {
    if (component.isEmpty()) return emptyList()
    val set = component.toHashSet()
    val neighbors = listOf(Pair(-1, 0), Pair(1, 0), Pair(0, -1), Pair(0, 1))
    val points = ArrayList<Pair<Float, Float>>(component.size / 3)
    for (idx in component) {
        val y = idx / width
        val x = idx % width
        var boundary = false
        for ((dy, dx) in neighbors) {
            val ny = y + dy
            val nx = x + dx
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) {
                boundary = true
                break
            }
            val ni = ny * width + nx
            if (!set.contains(ni)) {
                boundary = true
                break
            }
        }
        if (boundary) points.add(Pair(x.toFloat(), y.toFloat()))
    }
    return points
}

internal fun equivalentDiskDiameterPx(pixelCount: Int): Double {
    val area = max(1.0, pixelCount.toDouble())
    val d = 2.0 * sqrt(area / PI)
    return max(1.0, d * 0.4)
}

internal fun radialConsistency(
    component: List<Int>,
    width: Int,
    height: Int,
    centerX: Double,
    centerY: Double
): Double {
    val contour = contourPointsForComponent(component, width, height)
    if (contour.size < 12) return 0.0
    val radii = DoubleArray(contour.size)
    var i = 0
    for (p in contour) {
        val dx = p.first.toDouble() - centerX
        val dy = p.second.toDouble() - centerY
        radii[i++] = sqrt(dx * dx + dy * dy)
    }
    val meanR = radii.sum() / radii.size
    if (meanR <= 0) return 0.0
    var varAcc = 0.0
    for (r in radii) {
        val d = r - meanR
        varAcc += d * d
    }
    val stdR = sqrt(varAcc / radii.size)
    return (1.0 - stdR / meanR).coerceIn(0.0, 1.0)
}

internal fun sampleGray(gray: GrayImage, x: Double, y: Double): Double {
    val ix = x.roundToPxInt().coerceIn(0, gray.width - 1)
    val iy = y.roundToPxInt().coerceIn(0, gray.height - 1)
    return gray.pix(iy * gray.width + ix).toDouble()
}

internal fun meanGradientForComponent(gradient: DoubleArray, component: List<Int>): Double {
    if (component.isEmpty()) return 0.0
    var sum = 0.0
    for (idx in component) sum += gradient[idx]
    return sum / component.size.toDouble()
}

internal fun meanGradientOnContour(
    gradient: DoubleArray,
    component: List<Int>,
    width: Int,
    height: Int
): Double {
    val contour = contourPointsForComponent(component, width, height)
    if (contour.isEmpty()) return 0.0
    var sum = 0.0
    for (p in contour) {
        val ix = p.first.toInt().coerceIn(0, width - 1)
        val iy = p.second.toInt().coerceIn(0, height - 1)
        sum += gradient[iy * width + ix]
    }
    return sum / contour.size.toDouble()
}

private fun Double.roundToPxInt(): Int = kotlin.math.round(this).toInt()