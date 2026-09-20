#!/bin/bash
set -e

echo "📁 Paso 10: Extractor estático + cleartext + WebView fallback..."

# ========== AndroidManifest.xml (con usesCleartextTraffic) ==========
cat > app/src/main/AndroidManifest.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <uses-feature android:name="android.software.leanback" android:required="false" />
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:banner="@drawable/app_banner"
        android:usesCleartextTraffic="true"
        android:supportsRtl="true"
        android:theme="@style/Theme.TVApp">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:theme="@style/Theme.TVApp">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
XMLEOF

# ========== M3u8Extractor.kt (port del Python) ==========
cat > app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt << 'KTEOF'
package com.anonimus757.tvapp.data

import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URL
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object M3u8Extractor {

    private const val TAG = "M3u8Extractor"
    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
    private const val MAX_PROF = 8

    private val client: OkHttpClient by lazy {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(c: Array<X509Certificate>, a: String) {}
            override fun checkServerTrusted(c: Array<X509Certificate>, a: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val ssl = SSLContext.getInstance("TLS").apply { init(null, trustAll, java.security.SecureRandom()) }
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
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

        // 1) Decodificar ?r=base64 si existe
        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
        }

        // 2) Buscar recursivamente
        val visitadas = mutableSetOf<String>()
        val encontradas = buscarRecursivo(urlReal, referer, 0, visitadas, onLog)

        if (encontradas.isEmpty()) {
            onLog("❌ No se encontró m3u8 en el HTML")
            return@withContext null
        }

        onLog("✅ Encontrado: ${encontradas[0].take(90)}")

        // 3) Elegir mejor variante
        val mejor = elegirVariante(encontradas[0], urlReal, onLog) ?: encontradas[0]
        onLog("🎯 Final: ${mejor.take(90)}")
        mejor
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

        onLog("→ [${prof}] ${url.take(80)}")

        val html = httpGet(url, referer) ?: run {
            onLog("  ✗ no cargó")
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
        Regex("""playbackURL\s*[:=]\s*["']([^"']+)["']""")
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

    private fun adaptarUrl(url: String, base: String): String? = try {
        when {
            url.startsWith("//") -> "https:$url"
            url.startsWith("http") -> url
            else -> URL(URL(base), url).toString()
        }
    } catch (e: Exception) { null }

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
KTEOF

# ========== PlayerScreen.kt (con logs + static primero + WebView fallback) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.util.Log
import android.view.ViewGroup
import android.webkit.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.M3u8Extractor

private const val TAG = "PlayerV2"
private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

private val JS_HOOK = """
(function() {
    if (window.__hooked) return;
    window.__hooked = true;
    function send(url) {
        try {
            if (url && typeof url === 'string' && url.indexOf('.m3u8') !== -1) {
                if (window.AndroidBridge && window.AndroidBridge.onM3u8) {
                    window.AndroidBridge.onM3u8(url);
                }
            }
        } catch(e) {}
    }
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        send(url);
        return _open.apply(this, arguments);
    };
    if (window.fetch) {
        var _fetch = window.fetch;
        window.fetch = function() {
            try {
                var u = arguments[0];
                if (typeof u === 'string') send(u);
                else if (u && u.url) send(u.url);
            } catch(e) {}
            return _fetch.apply(this, arguments);
        };
    }
    var _setAttr = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
        if (name === 'src' && typeof value === 'string') send(value);
        return _setAttr.apply(this, arguments);
    };
    setInterval(function() {
        if (window.Hls && window.Hls.prototype && !window.Hls.__hooked) {
            window.Hls.__hooked = true;
            var _load = window.Hls.prototype.loadSource;
            window.Hls.prototype.loadSource = function(url) {
                send(url);
                return _load.apply(this, arguments);
            };
        }
    }, 200);
    setInterval(function() {
        try {
            var vids = document.querySelectorAll('video, source');
            for (var i = 0; i < vids.length; i++) {
                if (vids[i].src) send(vids[i].src);
                if (vids[i].currentSrc) send(vids[i].currentSrc);
            }
        } catch(e) {}
    }, 500);
})();
""".trimIndent()

class JsBridge(private val onM3u8: (String) -> Unit) {
    @JavascriptInterface
    fun onM3u8(url: String) { onM3u8(url) }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PlayerScreen(evento: Evento, embed: Embed, onBack: () -> Unit) {
    val context = LocalContext.current
    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Analizando embed...") }
    var exoError by remember { mutableStateOf<String?>(null) }
    var usarWebView by remember { mutableStateOf(false) }
    var logs by remember { mutableStateOf(listOf<String>()) }
    var cookies by remember { mutableStateOf<String?>(null) }

    val addLog: (String) -> Unit = { msg ->
        Log.d(TAG, msg)
        logs = (logs + msg).takeLast(25)
    }

    val exoPlayer = remember {
        ExoPlayer.Builder(context).build().apply {
            addListener(object : Player.Listener {
                override fun onPlayerError(e: PlaybackException) {
                    exoError = "${e.errorCodeName}: ${e.message?.take(200)}"
                }
                override fun onPlaybackStateChanged(state: Int) {
                    if (state == Player.STATE_READY) exoError = null
                }
            })
        }
    }

    DisposableEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        onDispose { exoPlayer.release() }
    }

    // FASE 1: static fetch (como el Python)
    LaunchedEffect(Unit) {
        addLog("🔍 Analizando embed (static)...")
        try {
            val url = M3u8Extractor.extraer(embed.url, embed.referer, addLog)
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
                status = "Cargando reproductor..."
            } else {
                addLog("⚠️ Static falló, activando WebView...")
                usarWebView = true
                status = "Cargando WebView..."
            }
        } catch (e: Exception) {
            addLog("❌ Error static: ${e.message}")
            usarWebView = true
            status = "Cargando WebView..."
        }
    }

    // FASE 3: cargar en ExoPlayer
    LaunchedEffect(m3u8Url) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to embed.referer,
                "Origin" to embed.referer.trimEnd('/')
            )
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }

            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(20000)
                .setReadTimeoutMs(20000)

            val src = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(true)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            exoPlayer.setMediaSource(src)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            exoError = "ExoPlayer: ${e.message}"
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {

        if (m3u8Url != null && exoError == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = true
                        setShowNextButton(false)
                        setShowPreviousButton(false)
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        Column(
            Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(16.dp)
        ) {
            Text(evento.descripcion, color = Color(0xFFE2E8F0), fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("${embed.nombre} · ${evento.hora}", color = Color(0xFF94A3B8), fontSize = 12.sp)
        }

        if (m3u8Url == null || exoError != null) {
            Row(Modifier.fillMaxSize().padding(top = 80.dp)) {
                Column(
                    Modifier.weight(1f).padding(24.dp).verticalScroll(rememberScrollState())
                ) {
                    if (exoError == null) {
                        CircularProgressIndicator(color = Color(0xFF38BDF8))
                        Spacer(Modifier.height(12.dp))
                        Text(status, color = Color(0xFF94A3B8), fontSize = 15.sp)
                    } else {
                        Text("⚠️ $exoError", color = Color(0xFFEF4444), fontSize = 15.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Atrás para volver", color = Color(0xFF94A3B8), fontSize = 12.sp)
                    }
                }
                Column(
                    Modifier.weight(1f).fillMaxHeight().background(Color(0x99000000)).padding(14.dp)
                ) {
                    Text("📋 Log", color = Color(0xFF38BDF8), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    LazyColumn {
                        items(logs) { l ->
                            Text(l, color = Color(0xFFA3E635), fontSize = 10.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                        }
                    }
                }
            }
        }

        if (usarWebView && m3u8Url == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(1, 1)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.databaseEnabled = true
                        settings.userAgentString = USER_AGENT
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.allowFileAccess = true
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                        settings.cacheMode = WebSettings.LOAD_NO_CACHE
                        setBackgroundColor(AndroidColor.TRANSPARENT)

                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                        addJavascriptInterface(JsBridge { url ->
                            if (url.contains(".m3u8")) {
                                if (m3u8Url == null) {
                                    addLog("🎯 WebView JS: ${url.take(80)}")
                                    cookies = CookieManager.getInstance().getCookie(url)
                                    m3u8Url = url
                                }
                            }
                        }, "AndroidBridge")

                        webViewClient = object : WebViewClient() {
                            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                                super.onPageStarted(view, url, favicon)
                                view?.evaluateJavascript(JS_HOOK, null)
                            }
                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                val v = view ?: return
                                v.evaluateJavascript(JS_HOOK, null)
                                v.postDelayed({ v.evaluateJavascript(JS_HOOK, null) }, 800)
                                v.postDelayed({ v.evaluateJavascript(JS_HOOK, null) }, 2000)
                            }
                            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                                val u = request?.url?.toString()
                                if (u != null && u.contains(".m3u8", ignoreCase = true)) {
                                    if (m3u8Url == null) {
                                        addLog("🎯 WebView intercept: ${u.take(80)}")
                                        cookies = CookieManager.getInstance().getCookie(u)
                                        m3u8Url = u
                                    }
                                }
                                return super.shouldInterceptRequest(view, request)
                            }
                        }

                        loadUrl(embed.url, mapOf("Referer" to embed.referer))

                        postDelayed({
                            if (m3u8Url == null) {
                                addLog("⏱ Timeout WebView 25s")
                            }
                        }, 25000)
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 10 completo"
find app/src/main/java -type f