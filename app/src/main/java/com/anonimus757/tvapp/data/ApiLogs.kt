package com.anonimus757.tvapp.data

import androidx.compose.runtime.mutableStateListOf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Recolector de logs SOLO para el ApiSportsRepository.
 * El botón 🐛 del EventDetailScreen muestra estos logs.
 */
object ApiLogs {
    private const val MAX_LOGS = 100
    val logs = mutableStateListOf<String>()

    private val horaFmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    fun add(mensaje: String) {
        val hora = horaFmt.format(Date())
        logs.add("[$hora] $mensaje")
        if (logs.size > MAX_LOGS) {
            logs.removeAt(0)
        }
        // También mandamos al DebugLog general
        try { DebugLog.log(mensaje) } catch (_: Exception) {}
    }

    fun clear() {
        logs.clear()
    }
}
