package com.anonimus757.tvapp.data

import com.anonimus757.tvapp.BuildConfig

/**
 * Compara la versión actual de la app con la versión publicada en Firestore.
 * Si hay una nueva → el usuario recibe un cartel para actualizar.
 */
object VersionChecker {

    /**
     * Compara dos versiones tipo "2.0" o "2.1.3".
     * Devuelve:
     *   -1 → v1 < v2 (hay update)
     *    0 → v1 == v2 (igual)
     *    1 → v1 > v2 (la app es más nueva)
     */
    fun comparar(v1: String, v2: String): Int {
        val partes1 = v1.split(".").map { it.toIntOrNull() ?: 0 }
        val partes2 = v2.split(".").map { it.toIntOrNull() ?: 0 }
        val max = maxOf(partes1.size, partes2.size)

        for (i in 0 until max) {
            val a = partes1.getOrElse(i) { 0 }
            val b = partes2.getOrElse(i) { 0 }
            if (a < b) return -1
            if (a > b) return 1
        }
        return 0
    }

    /**
     * Devuelve true si hay una versión nueva disponible.
     */
    fun hayUpdate(config: AppConfig): Boolean {
        val versionLocal = BuildConfig.VERSION_NAME
        return comparar(versionLocal, config.versionActual) < 0
    }

    /**
     * Devuelve true si la versión local está por debajo de la mínima soportada.
     * En ese caso, el update es OBLIGATORIO.
     */
    fun updateObligatorio(config: AppConfig): Boolean {
        val versionLocal = BuildConfig.VERSION_NAME
        return comparar(versionLocal, config.versionMinima) < 0
    }

    /**
     * Devuelve la versión local de la app.
     */
    fun versionLocal(): String = BuildConfig.VERSION_NAME
}
