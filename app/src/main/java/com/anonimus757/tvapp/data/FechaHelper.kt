package com.anonimus757.tvapp.data

import java.util.Calendar

/**
 * Helper para manejo de fechas en formato "YYYY-MM-DD".
 * Usa Calendar porque minSdk=23 (java.time requiere 26+).
 */
object FechaHelper {

    private val DIAS_SEMANA = arrayOf("DOM", "LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB")

    /** Fecha actual en formato YYYY-MM-DD. */
    fun hoy(): String = formatear(Calendar.getInstance())

    /** Fecha de hoy + N días en formato YYYY-MM-DD. */
    fun hoyMasDias(dias: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, dias)
        return formatear(cal)
    }

    /** Convierte Calendar a "YYYY-MM-DD". */
    private fun formatear(cal: Calendar): String {
        val y = cal.get(Calendar.YEAR)
        val m = cal.get(Calendar.MONTH) + 1
        val d = cal.get(Calendar.DAY_OF_MONTH)
        return "%04d-%02d-%02d".format(y, m, d)
    }

    /** Parsea "YYYY-MM-DD" a Calendar. Devuelve null si no puede. */
    fun parsear(fecha: String): Calendar? {
        return try {
            val parts = fecha.split("-")
            if (parts.size != 3) return null
            val cal = Calendar.getInstance()
            cal.set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt(), 0, 0, 0)
            cal.set(Calendar.MILLISECOND, 0)
            cal
        } catch (_: Exception) { null }
    }

    /** Nombre corto del día: "LUN", "MAR", etc. */
    fun nombreDia(fecha: String): String {
        val cal = parsear(fecha) ?: return ""
        return DIAS_SEMANA[cal.get(Calendar.DAY_OF_WEEK) - 1]
    }

    /** Día del mes: "16", "20", etc. */
    fun diaDelMes(fecha: String): Int {
        val cal = parsear(fecha) ?: return 0
        return cal.get(Calendar.DAY_OF_MONTH)
    }

    /**
     * Etiqueta corta: "VIE 20" o "HOY" / "MAÑANA" / "PASADO".
     * @param offset 0=hoy, 1=mañana, 2=pasado
     */
    fun etiquetaCorta(fecha: String, offset: Int): String {
        return when (offset) {
            0 -> "HOY"
            1 -> "MAÑANA"
            2 -> "PASADO"
            else -> "${nombreDia(fecha)} ${diaDelMes(fecha)}"
        }
    }

    /** Badge completo: "VIE 20 · 21:00" para la card. */
    fun badgeCard(fecha: String, hora: String): String {
        if (fecha.isEmpty()) return hora
        val hoy = hoy()
        return if (fecha == hoy) hora
        else "${nombreDia(fecha)} ${diaDelMes(fecha)} · $hora"
    }

    /** True si la fecha es HOY. */
    fun esHoy(fecha: String): Boolean = fecha == hoy()
}
