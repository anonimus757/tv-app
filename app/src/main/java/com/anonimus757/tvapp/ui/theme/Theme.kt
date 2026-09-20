package com.anonimus757.tvapp.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    // Fondos
    val Background = Color(0xFF050505)
    val BackgroundGradient = Color(0xFF0F0F0F)
    val Surface = Color(0xFF121212)
    val SurfaceLight = Color(0xFF1A1A1A)
    val SurfaceFocus = Color(0xFF2A2A2A)
    val Card = Color(0xFF111111)
    val CardFocus = Color(0xFF1C1C1C)

    // Dorados
    val Gold = Color(0xFFD4AF37)
    val GoldBright = Color(0xFFFFD700)
    val GoldDim = Color(0xFF8B6914)
    val GoldGlow = Color(0x33FFD700)

    // Acentos
    val AccentGreen = Color(0xFF4ADE80)
    val AccentRed = Color(0xFFEF4444)
    val AccentYellow = Color(0xFFFACC15)

    // Texto
    val TextPrimary = Color(0xFFF5F5F5)
    val TextSecondary = Color(0xFFA0A0A0)
    val TextMuted = Color(0xFF606060)

    fun fuenteColor(groupTitle: String): Color = when {
        groupTitle.contains("EVENTOS 2") -> Color(0xFFE8A020)
        groupTitle.contains("EVENTOS 3") -> Color(0xFFB8860B)
        else -> Gold
    }

    fun fuenteIcono(groupTitle: String): String = when {
        groupTitle.contains("EVENTOS 2") -> "⚽"
        groupTitle.contains("EVENTOS 3") -> "🏆"
        else -> "🎯"
    }
}
