package com.anonimus757.tvapp.ui.animations

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Fade-in + slide-up al aparecer. Ideal para listas y cards.
 * Uso: Modifier.fadeInOnLoad(delayMs = 50 * index)
 */
fun Modifier.fadeInOnLoad(
    durationMs: Int = 400,
    delayMs: Int = 0,
    slideFromDp: Float = 24f
): Modifier = composed {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (delayMs > 0) delay(delayMs.toLong())
        visible = true
    }
    val alpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMs, easing = FastOutSlowInEasing),
        label = "fadeIn"
    )
    val offsetY by animateFloatAsState(
        targetValue = if (visible) 0f else slideFromDp,
        animationSpec = tween(durationMs, easing = FastOutSlowInEasing),
        label = "slideIn"
    )
    this.alpha(alpha).offset(y = offsetY.dp)
}

/**
 * Escala suave al enfocar (D-pad en TV o focus en general).
 * Uso: Modifier.scaleOnFocus(isFocused = focused)
 */
fun Modifier.scaleOnFocus(
    isFocused: Boolean,
    focusedScale: Float = 1.05f,
    animationMs: Int = 180
): Modifier = composed {
    val scale by animateFloatAsState(
        targetValue = if (isFocused) focusedScale else 1f,
        animationSpec = tween(animationMs, easing = FastOutSlowInEasing),
        label = "focusScale"
    )
    this.scale(scale)
}

/**
 * Brush shimmer animado para skeletons de carga.
 */
@Composable
fun shimmerBrush(
    baseColor: Color = Color(0xFF141414),
    highlightColor: Color = Color(0xFF2A2A2A),
    widthPx: Float = 900f,
    durationMs: Int = 1200
): Brush {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val translate by transition.animateFloat(
        initialValue = -widthPx,
        targetValue = widthPx * 2f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "shimmerX"
    )
    return Brush.linearGradient(
        colors = listOf(baseColor, highlightColor, baseColor),
        start = Offset(translate, 0f),
        end = Offset(translate + widthPx, 0f)
    )
}

/**
 * Modifier para aplicar shimmer como fondo (skeleton).
 * Uso: Box(Modifier.size(260.dp, 240.dp).shimmer())
 */
fun Modifier.shimmer(
    shape: Shape = RoundedCornerShape(12.dp)
): Modifier = composed {
    this.background(shimmerBrush(), shape)
}

/**
 * Alpha pulsante infinito, para el badge "● EN VIVO".
 * Uso: val a = rememberPulseAlpha(); Text("● EN VIVO", Modifier.alpha(a))
 */
@Composable
fun rememberPulseAlpha(
    min: Float = 0.35f,
    max: Float = 1f,
    durationMs: Int = 900
): Float {
    val transition = rememberInfiniteTransition(label = "pulse")
    val alpha by transition.animateFloat(
        initialValue = min,
        targetValue = max,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )
    return alpha
}
