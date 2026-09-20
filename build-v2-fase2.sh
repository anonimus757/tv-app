#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

echo "📝 Creando CanalCache.kt..."

cat > "$DATA_DIR/CanalCache.kt" << 'EOF'
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
EOF

echo "✅ CanalCache.kt creado"

# ═══════════════════════════════════════════════════════════
# 1) EventDetailScreen: precargar primeros 3 canales
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Precarga al entrar al evento (EventDetailScreen)..."

cp "$UI_DIR/EventDetailScreen.kt" "$UI_DIR/EventDetailScreen.kt.bak-fase2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Imports necesarios
if "import com.anonimus757.tvapp.data.M3u8Extractor" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.Evento",
        "import com.anonimus757.tvapp.data.CanalCache\nimport com.anonimus757.tvapp.data.Evento\nimport com.anonimus757.tvapp.data.M3u8Extractor"
    )
if "import androidx.compose.runtime.LaunchedEffect" not in content:
    # Ya está importado con runtime.*
    pass
if "import kotlinx.coroutines.Dispatchers" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.theme.AppIcons",
        "import com.anonimus757.tvapp.ui.theme.AppIcons\nimport kotlinx.coroutines.Dispatchers\nimport kotlinx.coroutines.launch"
    )

# 2) Agregar LaunchedEffect de precarga al inicio del composable EventDetailScreen
ancla = "    val color = AppColors.fuenteColor(evento.groupTitle)"

precarga_code = '''    val color = AppColors.fuenteColor(evento.groupTitle)
    val scope = rememberCoroutineScope()

    // ═══════════════════════════════════════════════════════════
    // 🆕 FASE 2: PRECARGA DE CANALES
    // Al entrar al evento, extrae en background los primeros 3 canales.
    // Cuando el usuario toca uno, arranca al instante.
    // ═══════════════════════════════════════════════════════════
    LaunchedEffect(evento.descripcion) {
        val canales = evento.embeds.take(3)
        canales.forEach { emb ->
            scope.launch(Dispatchers.IO) {
                if (CanalCache.get(emb.url) == null) {
                    try {
                        val m3u8 = M3u8Extractor.extraer(emb.url, emb.referer) { /* silencioso */ }
                        if (m3u8 != null) {
                            CanalCache.put(emb.url, m3u8)
                        }
                    } catch (_: Exception) {}
                }
            }
        }
    }'''

if ancla in content and "PRECARGA DE CANALES" not in content:
    content = content.replace(ancla, precarga_code, 1)
    print("✅ Precarga al entrar al evento")
else:
    print("⚠️  No encontré el ancla en EventDetailScreen")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2) PlayerScreen: usar cache + precargar siguiente
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Usar cache + precarga del siguiente (PlayerScreen)..."

cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-fase2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Import de CanalCache
if "import com.anonimus757.tvapp.data.CanalCache" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.AjustesStore",
        "import com.anonimus757.tvapp.data.AjustesStore\nimport com.anonimus757.tvapp.data.CanalCache"
    )

# 2) Modificar LaunchedEffect(embedActual) para usar cache primero
old_effect = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
        addLog("🔍 Analizando ${embedActual.nombre}...")

        // FIX: si es página dinámica (PHP, stream=, etc.) → WebView directo
        if (esPaginaDinamica(embedActual.url)) {
            addLog("⚡ Página dinámica → WebView directo")
            status = "Cargando reproductor..."
            usarWebView = true
            return@LaunchedEffect
        }

        try {
            // Timeout de 12 seg para el extractor estático
            val url = M3u8Extractor.extraerYTestear(
                embedActual.url, embedActual.referer, addLog
            )
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
            } else {
                addLog("⚠️ Extracto falló/timeout → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }
    }'''

new_effect = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
        addLog("🔍 Analizando ${embedActual.nombre}...")

        // ═══════════════════════════════════════════════════════
        // 🆕 FASE 2: PRECARGA — chequear cache primero
        // Si el canal ya fue precargado, arranca INSTANTÁNEO
        // ═══════════════════════════════════════════════════════
        val cacheado = CanalCache.get(embedActual.url)
        if (cacheado != null) {
            addLog("⚡ Canal precargado → arrancando al instante")
            status = "Cargando..."
            m3u8Url = cacheado
            // Precargar el siguiente en background
            scope.launch(Dispatchers.IO) {
                precargarSiguiente()
            }
            return@LaunchedEffect
        }

        // FIX: si es página dinámica (PHP, stream=, etc.) → WebView directo
        if (esPaginaDinamica(embedActual.url)) {
            addLog("⚡ Página dinámica → WebView directo")
            status = "Cargando reproductor..."
            usarWebView = true
            return@LaunchedEffect
        }

        try {
            // Timeout de 12 seg para el extractor estático
            val url = M3u8Extractor.extraerYTestear(
                embedActual.url, embedActual.referer, addLog
            )
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
                // Guardar en cache para próximas veces
                CanalCache.put(embedActual.url, url)
                // Precargar el siguiente en background
                scope.launch(Dispatchers.IO) {
                    precargarSiguiente()
                }
            } else {
                addLog("⚠️ Extracto falló/timeout → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }
    }'''

if old_effect in content:
    content = content.replace(old_effect, new_effect)
    print("✅ LaunchedEffect(embedActual) con cache")
else:
    print("⚠️  No encontré el LaunchedEffect(embedActual) exacto")

# 3) Agregar función precargarSiguiente antes del Box principal
funcion_precarga = '''
    /**
     * 🆕 FASE 2: Precarga el siguiente canal del evento en background.
     * El usuario está viendo uno → en paralelo se extrae el siguiente.
     */
    suspend fun precargarSiguiente() {
        try {
            val siguiente = evento.embeds.firstOrNull {
                it.url != embedActual.url && CanalCache.get(it.url) == null
            } ?: return

            addLog("🔒 Precargando ${siguiente.nombre}...")
            val m3u8 = M3u8Extractor.extraer(siguiente.url, siguiente.referer) { /* silencioso */ }
            if (m3u8 != null) {
                CanalCache.put(siguiente.url, m3u8)
                addLog("✅ ${siguiente.nombre} precargado")
            }
        } catch (_: Exception) {}
    }

'''

ancla_funcion = '''    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(playerFocus)'''

if ancla_funcion in content and "suspend fun precargarSiguiente" not in content:
    content = content.replace(ancla_funcion, funcion_precarga + ancla_funcion, 1)
    print("✅ Función precargarSiguiente agregada")

# 4) Import de Dispatchers
if "import kotlinx.coroutines.Dispatchers" not in content:
    content = content.replace(
        "import kotlinx.coroutines.delay",
        "import kotlinx.coroutines.Dispatchers\nimport kotlinx.coroutines.delay"
    )
    print("✅ Import Dispatchers")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$DATA_DIR/CanalCache.kt" ] && echo "  ✓ CanalCache.kt"
grep -q "PRECARGA DE CANALES" "$UI_DIR/EventDetailScreen.kt" && echo "  ✓ Precarga al entrar al evento"
grep -q "precargarSiguiente" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Precarga del siguiente canal"
grep -q "CanalCache.get" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Uso del cache"

echo ""
echo "✅✅✅ FASE 2 completo — Precarga de canales"
echo ""
echo "📌 Qué hace:"
echo "   1. Al entrar al evento → precarga 3 canales en background"
echo "   2. Al tocar un canal precargado → arranca en <1 seg"
echo "   3. Mientras ves un canal → precarga el siguiente"
echo "   4. Cache dura 5 min (luego se re-extrae)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"