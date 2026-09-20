#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

echo "💾 Backups..."
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-fase1"
cp "$DATA_DIR/SignalHealthMonitor.kt" "$DATA_DIR/SignalHealthMonitor.kt.bak-fase1"
echo "   ✅ Backups creados"

# ═══════════════════════════════════════════════════════════
# 1) M3u8Extractor con todas las mejoras
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Reescribiendo M3u8Extractor.kt..."

cat > "$DATA_DIR/M3u8Extractor.kt" << 'EOF'
package com.anonimus757.tvapp.data

import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URL
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object M3u8Extractor {

    private const val TAG = "M3u8Extractor"
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
    private const val MAX_PROF = 5

    // ═══════════════════════════════════════════════════════════
    // CACHE DE DOMINIOS CAÍDOS
    // Cuando un subdominio falla varias veces, lo bloqueamos por
    // 5 minutos. Evita reintentar hosts muertos (fubo18 tiene muchos).
    // ═══════════════════════════════════════════════════════════
    private const val TIEMPO_BLOQUEO_MS = 5 * 60 * 1000L
    private data class DominioMuerto(val fallas: Int, val ultimaFalla: Long)
    private val dominiosCaidos = ConcurrentHashMap<String, DominioMuerto>()

    /**
     * Registra una falla de un dominio. Si acumula 2 fallas, se bloquea por 5 min.
     */
    private fun registrarFalla(host: String) {
        val anterior = dominiosCaidos[host]
        val fallas = (anterior?.fallas ?: 0) + 1
        dominiosCaidos[host] = DominioMuerto(fallas, System.currentTimeMillis())
    }

    /**
     * Devuelve true si el dominio está bloqueado (muchas fallas recientes).
     */
    private fun estaBloqueado(url: String): Boolean {
        return try {
            val host = URL(url).host
            val info = dominiosCaidos[host] ?: return false
            val tiempoDesdeFalla = System.currentTimeMillis() - info.ultimaFalla
            if (tiempoDesdeFalla > TIEMPO_BLOQUEO_MS) {
                dominiosCaidos.remove(host)
                false
            } else {
                info.fallas >= 2
            }
        } catch (_: Exception) { false }
    }

    /**
     * Limpia dominios caídos viejos (más de 5 min sin fallas).
     */
    fun limpiarCacheDominios() {
        val ahora = System.currentTimeMillis()
        dominiosCaidos.entries.removeIf { (_, info) ->
            (ahora - info.ultimaFalla) > TIEMPO_BLOQUEO_MS
        }
    }

    private val client: OkHttpClient by lazy {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(c: Array<X509Certificate>, a: String) {}
            override fun checkServerTrusted(c: Array<X509Certificate>, a: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val ssl = SSLContext.getInstance("TLS").apply { init(null, trustAll, java.security.SecureRandom()) }
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .sslSocketFactory(ssl.socketFactory, trustAll[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    private val cookies = mutableMapOf<String, String>()

    suspend fun extraer(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
        }

        val visitadas = mutableSetOf<String>()
        val encontradas = buscarRecursivo(urlReal, referer, 0, visitadas, onLog)

        if (encontradas.isEmpty()) {
            onLog("❌ No se encontró m3u8 en el HTML")
            return@withContext null
        }

        onLog("✅ Encontrado: ${encontradas[0].take(90)}")

        val mejor = elegirVariante(encontradas[0], urlReal, onLog) ?: encontradas[0]
        val finalLimpio = limpiarUrlFinal(mejor)
        onLog("🎯 Final: ${finalLimpio.take(90)}")
        finalLimpio
    }

    /**
     * Extrae N URLs candidatas del mismo embed para sistema de respaldo.
     * Devuelve la lista ordenada (principal primero).
     */
    suspend fun extraerConCandidatos(
        urlEmbed: String,
        referer: String,
        cantidad: Int,
        onLog: (String) -> Unit
    ): List<String> = withContext(Dispatchers.IO) {
        val resultados = mutableListOf<String>()

        try {
            val principal = extraer(urlEmbed, referer, onLog)
            if (principal != null) {
                resultados.add(principal)
            }
        } catch (_: Exception) {}

        // Extraer variantes alternativas del mismo m3u8 (diferentes subdominios)
        try {
            val urlReal = decodificarR(urlEmbed) ?: urlEmbed
            val visitadas = mutableSetOf<String>()
            val todas = buscarRecursivo(urlReal, referer, 0, visitadas, onLog)

            for (url in todas) {
                if (resultados.size >= cantidad) break
                val limpia = limpiarUrlFinal(elegirVariante(url, urlReal, {}) ?: url)
                if (limpia !in resultados) {
                    resultados.add(limpia)
                }
            }
        } catch (_: Exception) {}

        onLog("🎯 ${resultados.size} URLs listas")
        resultados
    }

    fun cookieString(): String? = if (cookies.isEmpty()) null else cookies.values.joinToString("; ")

    private fun decodificarR(url: String): String? {
        try {
            val q = url.indexOf("?")
            if (q < 0) return null
            val query = url.substring(q + 1).split("#")[0]
            var r: String? = null
            for (p in query.split("&")) {
                val parts = p.split("=", limit = 2)
                if (parts.size == 2 && parts[0] == "r") {
                    r = parts[1]; break
                }
            }
            if (r == null) return null
            val decoded = String(Base64.decode(r, Base64.DEFAULT), Charsets.UTF_8)
            if (decoded.startsWith("http")) return decoded
        } catch (e: Exception) {
            Log.d(TAG, "decodificarR fail: ${e.message}")
        }
        return null
    }

    private fun buscarRecursivo(
        url: String,
        referer: String?,
        prof: Int,
        visitadas: MutableSet<String>,
        onLog: (String) -> Unit
    ): List<String> {
        if (prof > MAX_PROF) return emptyList()
        if (url in visitadas) return emptyList()
        visitadas.add(url)

        // Si el dominio está bloqueado, saltar rápido
        if (estaBloqueado(url)) {
            onLog("⛔ [${prof}] Dominio bloqueado: ${url.take(60)}")
            return emptyList()
        }

        onLog("→ [${prof}] ${url.take(80)}")

        val html = httpGet(url, referer) ?: run {
            onLog("  ✗ no cargó")
            try { registrarFalla(URL(url).host) } catch (_: Exception) {}
            return emptyList()
        }
        onLog("  ✓ ${html.length} bytes")

        val directos = buscarM3u8EnHtml(html, url)
        if (directos.isNotEmpty()) {
            onLog("  🎯 m3u8 directo")
            return directos
        }

        if (prof < MAX_PROF) {
            val iframes = buscarIframes(html, url).filter { !esAnuncio(it) && it !in visitadas }
            if (iframes.isNotEmpty()) onLog("  ↗ ${iframes.size} iframes")

            for (ifr in iframes) {
                val sub = buscarRecursivo(ifr, url, prof + 1, visitadas, onLog)
                if (sub.isNotEmpty()) return sub
            }
        }
        return emptyList()
    }

    private fun httpGet(url: String, referer: String?): String? {
        return try {
            val b = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .header("Accept-Language", "es-ES,es;q=0.9,en;q=0.8")
            if (!referer.isNullOrBlank()) b.header("Referer", referer)
            if (cookies.isNotEmpty()) b.header("Cookie", cookies.values.joinToString("; "))

            val resp = client.newCall(b.build()).execute()
            resp.headers("Set-Cookie").forEach { c ->
                val nv = c.split(";").firstOrNull()?.trim() ?: return@forEach
                val k = nv.split("=").firstOrNull()?.trim() ?: return@forEach
                cookies[k] = nv
            }
            resp.body?.string()
        } catch (e: Exception) {
            Log.d(TAG, "GET fail: $url -> ${e.message}")
            null
        }
    }

    private val PATRONES = listOf(
        Regex("""["']((?:https?:)?//[^"'\s<>]+\.m3u8[^"'\s<>]*)["']"""),
        Regex("""["'](/[^"'\s<>]+\.m3u8[^"'\s<>]*)["']"""),
        Regex("""["']([^"'\s<>]+\.m3u8[^"'\s<>]*)["']"""),
        Regex("""file\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""source\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""loadSource\s*\(\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""src\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""url\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""playbackURL\s*[:=]\s*["']([^"']+)["']"""),
        Regex("""data-src\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""hls\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""manifest\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""videoUrl\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']"""),
        Regex("""streamUrl\s*[:=]\s*["']([^"']+\.m3u8[^"']*)["']""")
    )

    private fun buscarM3u8EnHtml(texto: String, baseUrl: String): List<String> {
        val limpio = texto.replace("\\/", "/").replace("\\u0026", "&")
        val out = mutableListOf<String>()
        for (p in PATRONES) {
            for (m in p.findAll(limpio)) {
                var u = m.groupValues[1].trim().replace("\\/", "/").replace("\\u0026", "&")
                if (!(u.startsWith("http://") || u.startsWith("https://") ||
                            u.startsWith("//") || u.startsWith("/"))) continue
                if (u.any { it in " \n\t<>\\" }) continue
                u = adaptarUrl(u, baseUrl) ?: continue
                if (!u.startsWith("http") || !u.contains(".m3u8")) continue
                val low = u.lowercase()
                if (listOf("ejemplo","example","test","dummy",".js",".css",".png",".jpg",".gif",".svg")
                        .any { low.contains(it) }) continue
                if (u !in out) out.add(u)
            }
        }
        return out
    }

    private val PATRONES_IFRAME = listOf(
        Regex("""<iframe[^>]+?src\s*=\s*["']([^"']+)["']""", RegexOption.IGNORE_CASE),
        Regex("""iframe\.src\s*=\s*["']([^"']+)["']""", RegexOption.IGNORE_CASE),
        Regex("""(?:player|embed|frame|video)\w*\.src\s*=\s*["']([^"']+)["']""", RegexOption.IGNORE_CASE),
        Regex("""<iframe[^>]+?data-src\s*=\s*["']([^"']+)["']""", RegexOption.IGNORE_CASE)
    )

    private fun buscarIframes(texto: String, baseUrl: String): List<String> {
        val out = mutableListOf<String>()
        for (p in PATRONES_IFRAME) {
            for (m in p.findAll(texto)) {
                val u = adaptarUrl(m.groupValues[1], baseUrl) ?: continue
                if (u !in out) out.add(u)
            }
        }
        return out
    }

    private fun esAnuncio(url: String): Boolean {
        val l = url.lowercase()
        return listOf("doubleclick","googleads","googlesyndication","popads","acscdn",
            "trkr.ppof","facebook","twitter","googletagmanager","google-analytics")
            .any { l.contains(it) }
    }

    private fun testearUrl(url: String, referer: String?): Boolean {
        if (estaBloqueado(url)) return false
        return try {
            val b = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "*/*")
            if (!referer.isNullOrBlank()) b.header("Referer", referer)
            if (cookies.isNotEmpty()) b.header("Cookie", cookies.values.joinToString("; "))

            val clienteRapido = client.newBuilder()
                .connectTimeout(3, TimeUnit.SECONDS)
                .readTimeout(3, TimeUnit.SECONDS)
                .build()

            val resp = clienteRapido.newCall(b.build()).execute()
            if (resp.code != 200) {
                resp.close()
                try { registrarFalla(URL(url).host) } catch (_: Exception) {}
                return false
            }
            val body = resp.body?.string()?.take(200) ?: ""
            resp.close()
            body.contains("#EXTM3U")
        } catch (e: Exception) {
            try { registrarFalla(URL(url).host) } catch (_: Exception) {}
            false
        }
    }

    suspend fun extraerYTestear(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        val inicio = System.currentTimeMillis()

        for (intento in 1..3) {
            if (System.currentTimeMillis() - inicio > 12000) {
                onLog("⏰ Timeout total alcanzado")
                break
            }

            if (intento > 1) {
                onLog("🔍 Reintento $intento/3...")
            }

            val url = try {
                withTimeoutOrNull(5000L) {
                    extraer(urlEmbed, referer, onLog)
                }
            } catch (_: Exception) { null }

            if (url == null) {
                onLog("⚠️ No se pudo extraer (intento $intento)")
                continue
            }

            onLog("🧪 Testeando URL...")
            val ok = testearUrl(url, referer)
            if (ok) {
                onLog("✅ URL verificada OK")
                return@withContext url
            } else {
                onLog("❌ URL muerta, buscando otra...")
            }
        }

        onLog("❌ No se encontró URL funcional")
        null
    }

    private fun adaptarUrl(url: String, base: String): String? = try {
        when {
            url.startsWith("//") -> "https:$url"
            url.startsWith("http") -> url
            else -> URL(URL(base), url).toString()
        }
    } catch (e: Exception) { null }

    /**
     * Limpia una URL final antes de pasarla a ExoPlayer.
     *
     * ⚠️ SOLO quita el puerto :443/:80 cuando aparece DESPUÉS del host.
     * NUNCA toca el resto de la URL (tokens pueden contener ":80" o ":443").
     *
     * Ej: https://host.com:443/path?token=abc  →  https://host.com/path?token=abc
     *     https://host.com/path?token=abc:80xyz  →  SIN CAMBIOS
     */
    private fun limpiarUrlFinal(url: String): String {
        return try {
            // Regex: captura (esquema+host) + :puerto + (resto opcional que empieza con / o ?)
            val regex = Regex("""^(https?://[^/:?]+):(443|80)([/?].*)?$""")
            val match = regex.find(url)
            if (match != null) {
                val host = match.groupValues[1]
                val resto = match.groupValues[3]
                host + resto
            } else {
                url
            }
        } catch (_: Exception) { url }
    }

    private fun elegirVariante(urlM3u8: String, referer: String?, onLog: (String) -> Unit): String? {
        try {
            val txt = httpGet(urlM3u8, referer) ?: return urlM3u8
            if (!txt.contains("#EXT-X-STREAM-INF")) return urlM3u8
            val lineas = txt.split("\n")
            data class V(val bw: Int, val h: Int, val url: String)
            val vars = mutableListOf<V>()
            for (i in lineas.indices) {
                val l = lineas[i]
                if (l.startsWith("#EXT-X-STREAM-INF")) {
                    val bw = Regex("""BANDWIDTH=(\d+)""").find(l)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                    val h = Regex("""RESOLUTION=\d+x(\d+)""").find(l)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                    for (j in i + 1 until lineas.size) {
                        val n = lineas[j].trim()
                        if (n.isNotEmpty() && !n.startsWith("#")) {
                            val u = adaptarUrl(n, urlM3u8) ?: break
                            vars.add(V(bw, h, u)); break
                        }
                    }
                }
            }
            if (vars.isEmpty()) return urlM3u8
            vars.sortWith(compareByDescending<V> { it.h }.thenByDescending { it.bw })
            onLog("  📊 variante ${vars[0].h}p elegida")
            return vars[0].url
        } catch (e: Exception) {
            return urlM3u8
        }
    }
}
EOF

# ═══════════════════════════════════════════════════════════
# 2) SignalHealthMonitor con más datos
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Reescribiendo SignalHealthMonitor.kt..."

cat > "$DATA_DIR/SignalHealthMonitor.kt" << 'EOF'
package com.anonimus757.tvapp.data

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@OptIn(UnstableApi::class)
class SignalHealthMonitor(private val player: ExoPlayer) {

    data class Salud(
        val porcentaje: Int = 0,
        val bitrateBps: Long = 0L,
        val ancho: Int = 0,
        val alto: Int = 0,
        val fps: Float = 0f,
        val bufferingRecientes: Int = 0,
        val droppedFramesTotal: Long = 0L,
        // 🆕 NUEVOS CAMPOS para Fase 1
        val velocidadRedBps: Long = 0L,       // Velocidad medida
        val bufferRecomendadoMs: Int = 45000, // Buffer ideal según red
        val saludRed: String = "OK"           // "EXCELENTE" | "OK" | "LENTA" | "MUY_LENTA"
    )

    private val _estado = MutableStateFlow(Salud())
    val estado: StateFlow<Salud> = _estado.asStateFlow()

    private val bufferingTimestamps = ArrayDeque<Long>()
    private var droppedFramesTotal = 0L
    private var job: Job? = null

    // Para medir velocidad de red
    private val muestrasBitrate = ArrayDeque<Long>()
    private var velocidadEstimada: Long = 0L

    private val analyticsListener = object : AnalyticsListener {
        override fun onDroppedVideoFrames(
            eventTime: AnalyticsListener.EventTime,
            droppedFrames: Int,
            elapsedMs: Long
        ) {
            droppedFramesTotal += droppedFrames
        }
    }

    private val playerListener = object : androidx.media3.common.Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            if (state == androidx.media3.common.Player.STATE_BUFFERING) {
                bufferingTimestamps.addLast(System.currentTimeMillis())
                val corte = System.currentTimeMillis() - 30_000L
                while (bufferingTimestamps.isNotEmpty() && bufferingTimestamps.first() < corte) {
                    bufferingTimestamps.removeFirst()
                }
            }
        }
    }

    fun iniciar(scope: CoroutineScope) {
        player.addAnalyticsListener(analyticsListener)
        player.addListener(playerListener)
        job?.cancel()
        job = scope.launch {
            while (true) {
                delay(1000)
                actualizar()
            }
        }
    }

    fun detener() {
        job?.cancel()
        job = null
        try { player.removeAnalyticsListener(analyticsListener) } catch (_: Exception) {}
        try { player.removeListener(playerListener) } catch (_: Exception) {}
    }

    fun reset() {
        droppedFramesTotal = 0L
        bufferingTimestamps.clear()
        muestrasBitrate.clear()
        velocidadEstimada = 0L
        _estado.value = Salud()
    }

    private fun actualizar() {
        try {
            val formato = player.videoFormat
            val bitrate = formato?.bitrate?.toLong()?.takeIf { it > 0 } ?: 0L
            val ancho = formato?.width ?: 0
            val alto = formato?.height ?: 0
            val fps = formato?.frameRate ?: 0f

            val corte = System.currentTimeMillis() - 30_000L
            while (bufferingTimestamps.isNotEmpty() && bufferingTimestamps.first() < corte) {
                bufferingTimestamps.removeFirst()
            }
            val bufferingRecientes = bufferingTimestamps.size

            // ═══════════════════════════════════════════════════
            // Estimar velocidad de red midiendo el bitrate real
            // Promediamos las últimas 10 muestras
            // ═══════════════════════════════════════════════════
            if (bitrate > 0) {
                muestrasBitrate.addLast(bitrate)
                while (muestrasBitrate.size > 10) muestrasBitrate.removeFirst()
            }

            velocidadEstimada = if (muestrasBitrate.isNotEmpty()) {
                muestrasBitrate.average().toLong()
            } else 0L

            // Calcular buffer recomendado y estado de red
            val (bufferRec, saludRed) = calcularBufferRecomendado(
                velocidad = velocidadEstimada,
                buffering = bufferingRecientes,
                drops = droppedFramesTotal
            )

            val salud = calcularSalud(
                bufferingRecientes = bufferingRecientes,
                droppedFramesTotal = droppedFramesTotal,
                bitrate = bitrate,
                ancho = ancho,
                alto = alto
            )

            _estado.value = Salud(
                porcentaje = salud,
                bitrateBps = bitrate,
                ancho = ancho,
                alto = alto,
                fps = fps,
                bufferingRecientes = bufferingRecientes,
                droppedFramesTotal = droppedFramesTotal,
                velocidadRedBps = velocidadEstimada,
                bufferRecomendadoMs = bufferRec,
                saludRed = saludRed
            )
        } catch (e: Exception) {
            Log.d("SignalHealth", "actualizar fail: ${e.message}")
        }
    }

    /**
     * Calcula el buffer ideal según la red:
     * - Red muy rápida (>4Mbps): 8-25s (arranca rápido)
     * - Red rápida (>2Mbps): 10-35s
     * - Red normal (>1Mbps): 15-45s
     * - Red lenta (<1Mbps): 20-60s (aguanta cortes)
     */
    private fun calcularBufferRecomendado(
        velocidad: Long,
        buffering: Int,
        drops: Long
    ): Pair<Int, String> {
        return when {
            velocidad == 0L && buffering == 0 && drops == 0L -> 45000 to "OK"
            velocidad > 4_000_000 -> 25000 to "EXCELENTE"
            velocidad > 2_000_000 -> 35000 to "OK"
            velocidad > 1_000_000 -> 45000 to "OK"
            velocidad > 500_000 -> 55000 to "LENTA"
            else -> 60000 to "MUY_LENTA"
        }
    }

    private fun calcularSalud(
        bufferingRecientes: Int,
        droppedFramesTotal: Long,
        bitrate: Long,
        ancho: Int,
        alto: Int
    ): Int {
        var s = 100
        s -= (bufferingRecientes * 15).coerceAtMost(60)
        if (droppedFramesTotal > 30) s -= 20
        else if (droppedFramesTotal > 10) s -= 10
        if (bitrate in 1..500_000) s -= 10
        if (alto in 1..479) s -= 10
        return s.coerceIn(0, 100)
    }

    companion object {
        private const val TAG = "SignalHealthMonitor"
    }
}
EOF

# ═══════════════════════════════════════════════════════════
# 3) Verificación
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔎 Verificando:"
grep -q "limpiarUrlFinal" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ limpiarUrlFinal con regex"
grep -q "estaBloqueado" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Sistema de dominios caídos"
grep -q "extraerConCandidatos" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ extraerConCandidatos()"
grep -q "velocidadRedBps" "$DATA_DIR/SignalHealthMonitor.kt" && echo "  ✓ Velocidad de red en Salud"
grep -q "bufferRecomendadoMs" "$DATA_DIR/SignalHealthMonitor.kt" && echo "  ✓ Buffer recomendado"

echo ""
echo "✅✅✅ FASE 1a completo — Base de datos mejorada"
echo ""
echo "📌 Qué mejoró:"
echo "   • limpiarUrlFinal con regex (no rompe tokens)"
echo "   • Cache de dominios caídos (5 min)"
echo "   • extraerConCandidatos() para precarga (Fase 2)"
echo "   • SignalHealthMonitor mide velocidad de red"
echo "   • Buffer recomendado automático según velocidad"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"