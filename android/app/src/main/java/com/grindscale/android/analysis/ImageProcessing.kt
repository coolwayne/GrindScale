package com.grindscale.android.analysis

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import java.io.InputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object ImageProcessing {

    fun grayscale(bitmap: Bitmap, maxDimension: Int = 1024): GrayImage? {
        val scaled = scaleToMaxDimension(bitmap, maxDimension) ?: return null
        val w = scaled.width
        val h = scaled.height
        val out = UByteArray(w * h)
        val argb = IntArray(w * h)
        scaled.getPixels(argb, 0, w, 0, 0, w, h)
        var i = 0
        while (i < argb.size) {
            val p = argb[i]
            val r = (p shr 16) and 0xff
            val g = (p shr 8) and 0xff
            val b = p and 0xff
            val y = ((0.299 * r + 0.587 * g + 0.114 * b).roundToInt()).coerceIn(0, 255)
            out[i] = y.toUByte()
            i++
        }
        return GrayImage(w, h, out)
    }

    fun boxBlur(image: GrayImage, radius: Int = 1): GrayImage {
        if (radius <= 0) return GrayImage(image.width, image.height, image.pixels.copyOf())
        val w = image.width
        val h = image.height
        val src = image.pixels
        val out = UByteArray(src.size)
        val window = (radius * 2 + 1) * (radius * 2 + 1)
        for (y in 0 until h) {
            for (x in 0 until w) {
                var sum = 0
                for (ky in -radius..radius) {
                    for (kx in -radius..radius) {
                        val nx = (x + kx).coerceIn(0, w - 1)
                        val ny = (y + ky).coerceIn(0, h - 1)
                        sum += src[ny * w + nx].toInt() and 0xFF
                    }
                }
                out[y * w + x] = (sum / window).toUInt().toUByte()
            }
        }
        return GrayImage(w, h, out)
    }

    fun otsuThreshold(image: GrayImage): UByte {
        val hist = IntArray(256)
        for (i in image.pixels.indices) {
            hist[image.pix(i)]++
        }
        val total = image.width * image.height
        var sum = 0.0
        for (i in 0..255) sum += i * hist[i]

        var sumB = 0.0
        var wB = 0
        var maxVariance = 0.0
        var threshold = 127

        for (i in 0..255) {
            wB += hist[i]
            if (wB == 0) continue
            val wF = total - wB
            if (wF == 0) break
            sumB += i * hist[i]
            val mB = sumB / wB
            val mF = (sum - sumB) / wF
            val variance = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF)
            if (variance > maxVariance) {
                maxVariance = variance
                threshold = i
            }
        }
        return threshold.toUInt().toUByte()
    }

    fun binaryMask(image: GrayImage, threshold: UByte): ByteArray {
        val t = threshold.toInt()
        val out = ByteArray(image.pixels.size)
        var i = 0
        while (i < out.size) {
            out[i] = if ((image.pixels[i].toInt() and 0xFF) < t) 1 else 0
            i++
        }
        return out
    }
}

internal fun scaleToMaxDimension(bitmap: Bitmap, maxDimension: Int): Bitmap {
    val sw = bitmap.width
    val sh = bitmap.height
    val scale = min(1.0, maxDimension.toDouble() / max(sw, sh))
    if (scale >= 1.0) return bitmap.copy(Bitmap.Config.ARGB_8888, true)
    val tw = max(1, (sw * scale).roundToInt())
    val th = max(1, (sh * scale).roundToInt())
    return Bitmap.createScaledBitmap(bitmap, tw, th, true)
}

/** Apply EXIF orientation so image is upright (matches iOS normalizedImage intent). */
fun Bitmap.withExifOrientation(streamProvider: () -> InputStream?): Bitmap {
    val stream = streamProvider() ?: return this
    stream.use { ins ->
        val exif = ExifInterface(ins)
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )
        val matrix = android.graphics.Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.preScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.preScale(-1f, 1f)
            }
            else -> return this
        }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }
}

/** Desaturate using ColorMatrix (fallback when we already have display bitmap). */
fun Bitmap.toGrayscaleBitmap(): Bitmap {
    val bmp = copy(Bitmap.Config.ARGB_8888, true)
    val canvas = Canvas(bmp)
    val paint = Paint()
    val cm = ColorMatrix().apply { setSaturation(0f) }
    paint.colorFilter = ColorMatrixColorFilter(cm)
    canvas.drawBitmap(this, 0f, 0f, paint)
    return bmp
}
