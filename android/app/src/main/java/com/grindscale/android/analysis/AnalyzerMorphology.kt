package com.grindscale.android.analysis

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

internal fun mergeMasks(a: ByteArray, b: ByteArray): ByteArray {
    val out = a.copyOf()
    for (i in out.indices) {
        out[i] = if ((a[i] == 1.toByte()) || (b[i] == 1.toByte())) 1 else 0
    }
    return out
}

internal fun erode(mask: ByteArray, width: Int, height: Int, minNeighbors: Int): ByteArray {
    val out = ByteArray(mask.size)
    for (y in 0 until height) {
        for (x in 0 until width) {
            val idx = y * width + x
            if (mask[idx] == 0.toByte()) continue
            var neighbors = 0
            for (dy in -1..1) {
                for (dx in -1..1) {
                    if (dx == 0 && dy == 0) continue
                    val ny = y + dy
                    val nx = x + dx
                    if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue
                    val ni = ny * width + nx
                    if (mask[ni] == 1.toByte()) neighbors++
                }
            }
            out[idx] = if (neighbors >= minNeighbors) 1 else 0
        }
    }
    return out
}

internal fun dilate(mask: ByteArray, width: Int, height: Int, minNeighbors: Int): ByteArray {
    val out = mask.copyOf()
    for (y in 0 until height) {
        for (x in 0 until width) {
            val idx = y * width + x
            if (mask[idx] == 1.toByte()) continue
            var neighbors = 0
            for (dy in -1..1) {
                for (dx in -1..1) {
                    if (dx == 0 && dy == 0) continue
                    val ny = y + dy
                    val nx = x + dx
                    if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue
                    val ni = ny * width + nx
                    if (mask[ni] == 1.toByte()) neighbors++
                }
            }
            if (neighbors >= minNeighbors) out[idx] = 1
        }
    }
    return out
}

internal fun fillHoles(mask: ByteArray, width: Int, height: Int): ByteArray {
    if (width <= 0 || height <= 0) return mask
    val outside = ByteArray(mask.size)
    val queue = ArrayDeque<Int>()

    fun tryPush(idx: Int) {
        if (idx < 0 || idx >= mask.size) return
        if (mask[idx] == 0.toByte() && outside[idx] == 0.toByte()) {
            outside[idx] = 1
            queue.add(idx)
        }
    }

    for (x in 0 until width) {
        tryPush(x)
        tryPush((height - 1) * width + x)
    }
    for (y in 0 until height) {
        tryPush(y * width)
        tryPush(y * width + (width - 1))
    }

    val steps = listOf(Pair(-1, 0), Pair(1, 0), Pair(0, -1), Pair(0, 1))
    while (queue.isNotEmpty()) {
        val idx = queue.removeFirst()
        val yy = idx / width
        val xx = idx % width
        for ((dy, dx) in steps) {
            val ny = yy + dy
            val nx = xx + dx
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue
            val ni = ny * width + nx
            if (mask[ni] == 0.toByte() && outside[ni] == 0.toByte()) {
                outside[ni] = 1
                queue.add(ni)
            }
        }
    }

    val result = mask.copyOf()
    for (i in result.indices) {
        if (result[i] == 0.toByte() && outside[i] == 0.toByte()) result[i] = 1
    }
    return result
}

@Suppress("unused")
internal fun cleanupParticleMask(mask: ByteArray, width: Int, height: Int): ByteArray {
    val opened = erode(mask, width, height, minNeighbors = 2)
    val denoised = dilate(opened, width, height, minNeighbors = 4)
    val closed = dilate(denoised, width, height, minNeighbors = 5)
    return erode(closed, width, height, minNeighbors = 2)
}

internal fun suppressCircularRegion(
    mask: ByteArray,
    width: Int,
    height: Int,
    centerX: Double,
    centerY: Double,
    radius: Double
) {
    val r = max(1.0, radius)
    val r2 = r * r
    val minX = max(0, floor(centerX - r).toInt())
    val maxX = min(width - 1, ceil(centerX + r).toInt())
    val minY = max(0, floor(centerY - r).toInt())
    val maxY = min(height - 1, ceil(centerY + r).toInt())
    if (minX > maxX || minY > maxY) return
    for (y in minY..maxY) {
        for (x in minX..maxX) {
            val dx = x.toDouble() - centerX
            val dy = y.toDouble() - centerY
            if (dx * dx + dy * dy <= r2) {
                mask[y * width + x] = 0
            }
        }
    }
}
