package com.anonimus757.tvapp

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache

/**
 * Application class para configurar Coil (carga de imágenes).
 *
 * Coil se usa para todos los logos e imágenes de eventos.
 * Configurado con cache de memoria y disco optimizados.
 */
class FutTVApp : Application(), ImageLoaderFactory {

    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.20)  // 20% de la RAM para cache
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache"))
                    .maxSizeBytes(50 * 1024 * 1024)  // 50 MB en disco
                    .build()
            }
            .crossfade(true)  // Transición suave al cargar
            .crossfade(200)   // 200ms
            .respectCacheHeaders(false)  // Siempre respetar cache
            .build()
    }
}
