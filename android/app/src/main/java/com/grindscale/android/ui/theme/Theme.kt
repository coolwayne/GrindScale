package com.grindscale.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val scheme = lightColorScheme(
    primary = CoffeeColors.amber,
    onPrimary = CoffeeColors.labelBlack,
    secondary = CoffeeColors.accent,
    onSecondary = CoffeeColors.labelBlack,
    background = CoffeeColors.background,
    surface = CoffeeColors.card,
    onBackground = CoffeeColors.labelBlack,
    onSurface = CoffeeColors.labelBlack
)

@Composable
fun GrindScaleTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, content = content)
}
