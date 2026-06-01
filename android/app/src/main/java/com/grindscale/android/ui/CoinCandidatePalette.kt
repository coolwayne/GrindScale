package com.grindscale.android.ui

import androidx.compose.ui.graphics.Color

/**
 * Same palette as iOS [CoinCandidatePalette]: rank-colored debug chips + overlay strokes.
 */
object CoinCandidatePalette {
    fun color(rank: Int, selected: Boolean): Color {
        val idx = ((rank.coerceAtLeast(1) - 1) % BASE.size)
        val c = BASE[idx]
        return if (selected) c else c.copy(alpha = 0.92f)
    }

    private val BASE: List<Color> =
        listOf(
            Color(0.95f, 0.25f, 0.22f),
            Color(1f, 0.48f, 0f),
            Color(0.75f, 0.35f, 0.95f),
            Color(0.2f, 0.78f, 0.35f),
            Color(0f, 0.78f, 0.75f),
            Color(0f, 0.55f, 1f),
            Color(0.25f, 0.35f, 0.95f),
            Color(1f, 0.35f, 0.65f),
            Color(0.55f, 0.35f, 0.2f),
            Color(1f, 0.85f, 0.2f)
        )
}
