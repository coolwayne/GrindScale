package com.grindscale.android.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.grindscale.android.analysis.NormalizedRoi
import kotlin.math.max
import kotlin.math.min

@Composable
fun RoiImageEditor(
    bitmap: Bitmap,
    roi: NormalizedRoi?,
    onRoiChange: (NormalizedRoi?) -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val boxW = maxWidth.value
        val boxH = maxHeight.value
        if (boxW <= 0f || boxH <= 0f) return@BoxWithConstraints

        val bmpW = bitmap.width.toFloat().coerceAtLeast(1f)
        val bmpH = bitmap.height.toFloat().coerceAtLeast(1f)
        val imageAspect = bmpW / bmpH
        val canvasAspect = boxW / max(boxH, 0.0001f)

        val fitted: Rect =
            remember(boxW, boxH, bmpW, bmpH) {
                if (imageAspect > canvasAspect) {
                    val w = boxW
                    val h = w / imageAspect
                    Rect(offset = Offset(0f, (boxH - h) / 2f), size = Size(w, h))
                } else {
                    val h = boxH
                    val w = h * imageAspect
                    Rect(offset = Offset((boxW - w) / 2f, 0f), size = Size(w, h))
                }
            }

        var dragStartPx by remember(fitted) { mutableStateOf<Offset?>(null) }

        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Fit
        )

        Canvas(
            Modifier
                .fillMaxSize()
                .pointerInput(fitted) {
                    detectDragGestures(
                        onDragStart = { dragStartPx = clampToRect(it, fitted) },
                        onDragCancel = {
                            dragStartPx = null
                        },
                        onDragEnd = {
                            dragStartPx = null
                        },
                        onDrag = { change, _ ->
                            val s = dragStartPx ?: return@detectDragGestures
                            val p = clampToRect(change.position, fitted)
                            val r = rectFromCorners(s, p)
                            if (r.width > 6f && r.height > 6f) {
                                onRoiChange(normalizedRoiFromRect(r, fitted))
                            }
                        }
                    )
                }
        ) {
            roi?.let {
                val r = pixelRectFromNormalizedRoi(it, fitted)
                drawRect(
                    color = Color.Yellow.copy(alpha = 0.08f),
                    topLeft = r.topLeft,
                    size = r.size
                )
                drawRect(
                    color = Color.Yellow,
                    topLeft = r.topLeft,
                    size = r.size,
                    style = Stroke(width = 2.5.dp.toPx())
                )
            }
        }
    }
}

private fun clampToRect(p: Offset, rect: Rect): Offset =
    Offset(
        p.x.coerceIn(rect.left, rect.right),
        p.y.coerceIn(rect.top, rect.bottom)
    )

private fun rectFromCorners(a: Offset, b: Offset): Rect {
    val left = min(a.x, b.x)
    val top = min(a.y, b.y)
    val right = max(a.x, b.x)
    val bottom = max(a.y, b.y)
    return Rect(offset = Offset(left, top), size = Size(right - left, bottom - top))
}

private fun normalizedRoiFromRect(draw: Rect, imageRect: Rect): NormalizedRoi {
    val w = imageRect.width.coerceAtLeast(1e-6f)
    val h = imageRect.height.coerceAtLeast(1e-6f)
    val nx = ((draw.left - imageRect.left) / w).coerceIn(0f, 1f)
    val ny = ((draw.top - imageRect.top) / h).coerceIn(0f, 1f)
    val nw = (draw.width / w).coerceIn(0.01f, 1f)
    val nh = (draw.height / h).coerceIn(0.01f, 1f)
    return NormalizedRoi(nx, ny, nw, nh)
}

private fun pixelRectFromNormalizedRoi(roi: NormalizedRoi, imageRect: Rect): Rect {
    val left = imageRect.left + roi.nx.coerceIn(0f, 1f) * imageRect.width
    val top = imageRect.top + roi.ny.coerceIn(0f, 1f) * imageRect.height
    val w = roi.nw.coerceIn(0.01f, 1f) * imageRect.width
    val h = roi.nh.coerceIn(0.01f, 1f) * imageRect.height
    return Rect(offset = Offset(left, top), size = Size(w.coerceAtLeast(1f), h.coerceAtLeast(1f)))
}
