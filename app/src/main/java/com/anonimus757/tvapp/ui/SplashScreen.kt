package com.anonimus757.tvapp.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.ui.theme.AppColors
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(onTerminado: () -> Unit) {
    var visible by remember { mutableStateOf(false) }
    var saliendo by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        delay(100)
        visible = true
        delay(1400)
        saliendo = true
        delay(400)
        onTerminado()
    }

    val alpha by animateFloatAsState(
        targetValue = if (saliendo) 0f else if (visible) 1f else 0f,
        animationSpec = tween(if (saliendo) 400 else 600),
        label = "splashAlpha"
    )
    val scale by animateFloatAsState(
        targetValue = if (visible && !saliendo) 1f else 0.85f,
        animationSpec = tween(700),
        label = "splashScale"
    )

    // Glow pulsante en el logo
    val transition = rememberInfiniteTransition(label = "glow")
    val glow by transition.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "glowPulse"
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, Color(0xFF0A0A0A), AppColors.Background)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.alpha(alpha).scale(scale)
        ) {
            // Logo (pelota emoji como marca de FutTV)
            Text(
                "⚽",
                fontSize = 90.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(16.dp))
            Text(
                "FutTV",
                color = AppColors.GoldBright,
                fontSize = 56.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 6.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "EN VIVO · IPTV PREMIUM",
                color = AppColors.TextSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 3.sp
            )
            Spacer(Modifier.height(40.dp))
            // Línea dorada decorativa (reemplaza el Box con Brush)
            Box(
                Modifier
                    .width(90.dp)
                    .height(2.dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(
                        Brush.horizontalGradient(
                            listOf(Color.Transparent, AppColors.Gold, Color.Transparent)
                        )
                    )
            )
        }
    }
}
