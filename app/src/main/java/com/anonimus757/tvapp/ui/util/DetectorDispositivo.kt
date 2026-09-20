package com.anonimus757.tvapp.ui.util

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

/**
 * Detecta si el dispositivo es TV o Celu/Tablet.
 * Se usa para ajustar el tamaño de cards, animaciones y layouts.
 */
object DetectorDispositivo {

    /**
     * True si estamos en Android TV o TV Box.
     * Detecta por:
     *   1. Feature "android.software.leanback"
     *   2. Feature "android.hardware.touchscreen" (si NO tiene touch = TV)
     */
    fun esTV(context: Context): Boolean {
        val pm = context.packageManager
        val tieneLeanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val tieneTouch = pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        return tieneLeanback || !tieneTouch
    }

    /**
     * True si estamos en un celu o tablet.
     */
    fun esCelu(context: Context): Boolean = !esTV(context)
}

/**
 * Composable que recuerda si es TV o no durante toda la sesión.
 * Uso: val esTV = rememberEsTV()
 */
@Composable
fun rememberEsTV(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        DetectorDispositivo.esTV(context)
    }
}

/**
 * Busca la Activity desde un Context (puede estar envuelta en ContextWrapper).
 * Devuelve null si no encuentra.
 */
fun android.content.Context.findActivity(): android.app.Activity? {
    var ctx: android.content.Context? = this
    while (ctx is android.content.ContextWrapper) {
        if (ctx is android.app.Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
