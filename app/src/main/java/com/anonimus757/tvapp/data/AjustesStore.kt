package com.anonimus757.tvapp.data

import android.content.Context

/**
 * Preferencias locales del usuario (por dispositivo).
 * NO van a Firestore: cada celu/TV tiene las suyas.
 */
object AjustesStore {

    private const val PREFS = "futtv_ajustes"
    private const val KEY_CALIDAD = "calidad"
    private const val KEY_AUTOREFRESH = "autorefresh"

    /** auto | sd | hd */
    fun obtenerCalidad(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_CALIDAD, "auto") ?: "auto"

    fun guardarCalidad(context: Context, calidad: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_CALIDAD, calidad).apply()
    }

    /** Si está activado el auto-refresh local (además del global de Firestore). */
    fun obtenerAutoRefresh(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTOREFRESH, true)

    fun guardarAutoRefresh(context: Context, activo: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_AUTOREFRESH, activo).apply()
    }

    private const val KEY_ORIENTACION = "orientacion"

    /** auto | vertical | horizontal */
    fun obtenerOrientacion(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ORIENTACION, "auto") ?: "auto"

    fun guardarOrientacion(context: Context, o: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_ORIENTACION, o).apply()
    }
}
