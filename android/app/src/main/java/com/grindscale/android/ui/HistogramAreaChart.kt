package com.grindscale.android.ui

import android.graphics.Paint as AndroidPaint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.grindscale.android.domain.HistogramBin
import com.grindscale.android.ui.theme.CoffeeColors

private const val X_MAX = 1000f

/** Catmull–Rom style spline (uniform, via cubic Bézier), similar to Swift Charts interpolation. */
@Composable
fun HistogramAreaChart(bins: List<HistogramBin>, modifier: Modifier = Modifier) {
    if (bins.isEmpty()) return
    Canvas(modifier.then(Modifier.fillMaxWidth().height(220.dp))) {
        val padL = 4f
        val padR = 4f
        val padT = 12f
        val padB = 32f
        val bw = size.width - padL - padR
        val bh = size.height - padT - padB
        val baselineY = size.height - padB

        val maxC = bins.maxOf { it.count }.coerceAtLeast(1)

        fun xForBin(i: Int): Float {
            val centerUm = ((bins[i].start + bins[i].end) / 2).toFloat()
            return padL + (centerUm / X_MAX).coerceIn(0f, 1f) * bw
        }

        fun yForCount(count: Int): Float = padT + bh * (1f - count.toFloat() / maxC.toFloat())

        val pts =
            bins.indices.map { i ->
                Offset(xForBin(i), yForCount(bins[i].count))
            }

        drawLine(
            color = CoffeeColors.cardStroke.copy(alpha = 0.45f),
            start = Offset(padL, baselineY),
            end = Offset(size.width - padR, baselineY),
            strokeWidth = 1.dp.toPx()
        )

        val fillPath =
            Path().apply {
                if (pts.size == 1) {
                    val barHalf =
                        ((bw / bins.size.coerceAtLeast(1)) * 0.35f).coerceAtMost(28f)
                    moveTo(pts[0].x - barHalf, baselineY)
                    lineTo(pts[0].x - barHalf, pts[0].y)
                    lineTo(pts[0].x + barHalf, pts[0].y)
                    lineTo(pts[0].x + barHalf, baselineY)
                    close()
                } else {
                    moveTo(pts.first().x, baselineY)
                    lineTo(pts.first().x, pts.first().y)
                    appendCatmullRomSpline(pts, moveToFirst = false)
                    lineTo(pts.last().x, baselineY)
                    close()
                }
            }

        drawPath(fillPath, color = CoffeeColors.accent.copy(alpha = 0.22f))

        val linePath =
            Path().apply {
                if (pts.size == 1) {
                    moveTo(pts[0].x, baselineY)
                    lineTo(pts[0].x, pts[0].y)
                } else {
                    moveTo(pts.first().x, pts.first().y)
                    appendCatmullRomSpline(pts, moveToFirst = false)
                }
            }

        drawPath(
            linePath,
            color = CoffeeColors.amberChart,
            style =
                Stroke(
                    width = 2.5.dp.toPx(),
                    cap = StrokeCap.Round
                )
        )

        for (g in listOf(0.2f, 0.4f, 0.6f, 0.8f)) {
            val gx = padL + g * bw
            drawLine(
                color = CoffeeColors.chartGrid,
                start = Offset(gx, padT),
                end = Offset(gx, baselineY),
                strokeWidth = 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f))
            )
        }

        val axisLabelSize = 9.sp.toPx()
        val labelPaint =
            AndroidPaint(AndroidPaint.ANTI_ALIAS_FLAG).apply {
                textSize = axisLabelSize
                color = CoffeeColors.labelBlack.toArgb()
                textAlign = AndroidPaint.Align.CENTER
            }
        val nc = drawContext.canvas.nativeCanvas
        for (um in listOf(0, 200, 400, 600, 800, 1000)) {
            val fx = padL + (um / X_MAX).coerceIn(0f, 1f) * bw
            nc.drawText(um.toString(), fx, size.height - 6f, labelPaint)
        }
    }
}

private fun Offset.thirdTowardZero(): Offset = Offset(x / 3f, y / 3f)

/**
 * Opens a Catmull–Rom spline through [pts].
 * Caller must issue [moveTo] to pts[0] before calling with [moveToFirst] false.
 */
private fun Path.appendCatmullRomSpline(pts: List<Offset>, moveToFirst: Boolean) {
    if (pts.size < 2) return
    val ctrl = ArrayList<Offset>(pts.size + 2)
    ctrl.add(pts[0] + (pts[0] - pts[1]))
    ctrl.addAll(pts)
    ctrl.add(pts.last() + (pts.last() - pts[pts.size - 2]))

    if (moveToFirst) {
        moveTo(pts[0].x, pts[0].y)
    }

    for (k in 0 until pts.size - 1) {
        val p0 = ctrl[k]
        val p1 = ctrl[k + 1]
        val p2 = ctrl[k + 2]
        val p3 = ctrl[k + 3]
        val t1 = (p2 - p0) * 0.5f
        val t2 = (p3 - p1) * 0.5f
        val c1 = p1 + t1.thirdTowardZero()
        val c2 = p2 - t2.thirdTowardZero()
        cubicTo(c1.x, c1.y, c2.x, c2.y, p2.x, p2.y)
    }
}
