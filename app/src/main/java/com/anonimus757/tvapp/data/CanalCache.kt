package com.anonimus757.tvapp.data

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Cache en memoria de m3u8 extraídos.
 *
 * Cuando un canal se reproduce, guardamos la URL final del m3u8.
 * Si el usuario vuelve a ese canal, arranca INSTANTÁNEO (sin re-extraer).
 *
 * También permite PRECARGA: mientras el usuario ve un canal, la app extrae
 * los m3u8 de los siguientes canales del evento en background.
 *
 * El cache vive solo en memoria de la app (se borra al cerrar la app).
 */
object CanalCache {

    private const val TAG = "CanalCache"

    // embedUrl → m3u8Url (URL final ya limpia)
    private val cache = ConcurrentHashMap<String, String>()

    // Tiempo de vida del cache: 5 minutos (los m3u8 expiran)
    private const val TTL_MS = 5 * 60 * 1000L

    // embedUrl → timestamp cuando se guardó
    private val timestamps = ConcurrentHashMap<String, Long>()

    /**
     * Obtiene un m3u8 del cache. Devuelve null si no está o expiró.
     */
    fun get(embedUrl: String): String? {
        val url = cache[embedUrl] ?: return null
        val ts = timestamps[embedUrl] ?: return null

        // Verificar TTL
        if (System.currentTimeMillis() - ts > TTL_MS) {
            cache.remove(embedUrl)
            timestamps.remove(embedUrl)
            return null
        }

        Log.d(TAG, "🎯 Cache HIT: ${embedUrl.take(50)}")
        return url
    }

    /**
     * Guarda un m3u8 en el cache.
     */
    fun put(embedUrl: String, m3u8Url: String) {
        cache[embedUrl] = m3u8Url
        timestamps[embedUrl] = System.currentTimeMillis()
        Log.d(TAG, "💾 Cache PUT: ${embedUrl.take(50)}")
    }

    /**
     * Chequea si un canal ya está cacheado y vigente.
     */
    fun estaCacheado(embedUrl: String): Boolean {
        return get(embedUrl) != null
    }

    /**
     * Limpia todo el cache.
     */
    fun limpiar() {
        cache.clear()
        timestamps.clear()
    }

    /**
     * Limpia entradas expiradas.
     */
    fun limpiarExpirados() {
        val ahora = System.currentTimeMillis()
        val expirados = timestamps.filter { (_, ts) -> ahora - ts > TTL_MS }.keys
        expirados.forEach { key ->
            cache.remove(key)
            timestamps.remove(key)
        }
    }

    /**
     * Cantidad de canales cacheados.
     */
    fun cantidad(): Int = cache.size
}
