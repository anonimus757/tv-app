package com.anonimus757.tvapp.ui.animations

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Fondo con gradiente dorado que se mueve lentamente.
 * Muy sutil — da sensación de "vida" sin distraer.
 */
@Composable
fun AnimatedGoldBackground(
    modifier: Modifier = Modifier,
    baseColor: Color = Color(0xFF050505),
    accentColor: Color = Color(0xFFD4AF37),
    durationMs: Int = 8000
) {
    val transition = rememberInfiniteTransition(label = "bg")
    val offsetX by transition.animateFloat(
        initialValue = -1000f,
        targetValue = 2500f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bgOffsetX"
    )
    val offsetY by transition.animateFloat(
        initialValue = 500f,
        targetValue = -1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs + 3000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bgOffsetY"
    )

    Box(
        modifier
            .fillMaxSize()
            .background(baseColor)
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        accentColor.copy(alpha = 0.06f),
                        accentColor.copy(alpha = 0.02f),
                        Color.Transparent
                    ),
                    center = Offset(offsetX, offsetY),
                    radius = 1800f
                )
            )
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        accentColor.copy(alpha = 0.04f),
                        Color.Transparent
                    ),
                    center = Offset(2500f - offsetX, -offsetY + 800f),
                    radius = 1500f
                )
            )
    )
}
