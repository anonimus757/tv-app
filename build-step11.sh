#!/bin/bash
set -e

echo "📁 Paso 11: Player Live optimizado + auto-recovery..."

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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.M3u8Extractor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "PlayerLive"
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
    XMLHttpRequest.prototype.open = function(method, url) { send(url); return _open.apply(this, arguments); };
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
    val scope = rememberCoroutineScope()

    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Analizando embed...") }
    var exoError by remember { mutableStateOf<String?>(null) }
    var usarWebView by remember { mutableStateOf(false) }
    var logs by remember { mutableStateOf(listOf<String>()) }
    var cookies by remember { mutableStateOf<String?>(null) }
    var reintentos by remember { mutableIntStateOf(0) }

    val addLog: (String) -> Unit = { msg ->
        Log.d(TAG, msg)
        logs = (logs + msg).takeLast(30)
    }

    // ===== ExoPlayer configurado para LIVE agresivo =====
    val exoPlayer = remember {
        // Buffer corto: arranca rápido, no acumula segmentos viejos
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                8000,   // minBufferMs (antes era 50s por defecto)
                20000,  // maxBufferMs
                1000,   // bufferForPlaybackMs (arranca rápido)
                2000    // bufferForPlaybackAfterRebufferMs
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false) // No guardar back buffer
            .build()

        // Track selector que prefiere calidad baja primero (arranca más rápido)
        val trackSelector = DefaultTrackSelector(context).apply {
            setParameters(
                buildUponParameters()
                    .setMaxVideoSizeSd() // Limitar a SD primero para arrancar rápido
                    .setAllowVideoMixedMimeTypeAdaptiveness(true)
                    .setAllowVideoNonSeamlessAdaptiveness(true)
            )
        }

        ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .setTrackSelector(trackSelector)
            .setRenderersFactory(
                DefaultRenderersFactory(context)
                    .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                    .setEnableDecoderFallback(true)
            )
            .build().apply {
                addAnalyticsListener(EventLogger())
                addListener(object : Player.Listener {
                    override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        exoError = "$code: ${e.message?.take(180)}"
                        addLog("❌ $code")

                        // Auto-recovery para errores de live window
                        if (code == "ERROR_CODE_BEHIND_LIVE_WINDOW" ||
                            code == "ERROR_CODE_IO_BAD_HTTP_STATUS" ||
                            code == "ERROR_CODE_IO_NETWORK_CONNECTION_FAILED" ||
                            code == "ERROR_CODE_UNSPECIFIED") {
                            if (reintentos < 3) {
                                reintentos++
                                addLog("🔄 Auto-recovery #$reintentos...")
                                scope.launch {
                                    delay(2000)
                                    // Re-extraer URL fresca
                                    val fresh = M3u8Extractor.extraer(embed.url, embed.referer, addLog)
                                    if (fresh != null) {
                                        addLog("🔁 Nueva URL capturada")
                                        cookies = M3u8Extractor.cookieString()
                                        exoError = null
                                        m3u8Url = fresh
                                    } else {
                                        addLog("❌ No se pudo refrescar")
                                    }
                                }
                            }
                        }
                    }
                    override fun onPlaybackStateChanged(state: Int) {
                        when (state) {
                            Player.STATE_READY -> {
                                exoError = null
                                status = "Reproduciendo"
                                addLog("✅ Reproduciendo")
                            }
                            Player.STATE_BUFFERING -> {
                                addLog("⏳ Buffering...")
                            }
                            Player.STATE_ENDED -> {
                                addLog("⏹ Stream terminó")
                            }
                        }
                    }
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        if (isPlaying) addLog("▶️ PLAY")
                    }
                })
            }
    }

    DisposableEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        onDispose { exoPlayer.release() }
    }

    // FASE 1: extractor estático
    LaunchedEffect(reintentos) {
        if (m3u8Url == null) {
            addLog("🔍 Extrayendo (static)...")
            try {
                val url = M3u8Extractor.extraer(embed.url, embed.referer, addLog)
                if (url != null) {
                    cookies = M3u8Extractor.cookieString()
                    m3u8Url = url
                } else {
                    addLog("⚠️ Static falló, WebView...")
                    usarWebView = true
                }
            } catch (e: Exception) {
                addLog("❌ ${e.message}")
                usarWebView = true
            }
        }
    }

    // FASE 3: cargar en ExoPlayer
    LaunchedEffect(m3u8Url) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."

            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to embed.referer,
                "Origin" to embed.referer.trimEnd('/')
            )
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }

            addLog("📡 ${headers.size} headers")

            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(15000)

            // HLS optimizado para LIVE
            val hlsFactory = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(false) // Modo estricto (compatibilidad)
                .setUseSessionKeys(false)

            val src = hlsFactory.createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            exoPlayer.setMediaSource(src)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
            exoPlayer.seekToDefaultPosition() // Se posiciona en el live edge por defecto
        } catch (e: Exception) {
            exoError = "Init: ${e.message}"
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
                        setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        Column(
            Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(16.dp)
        ) {
            Text(evento.descripcion, color = Color(0xFFE2E8F0), fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("${embed.nombre} · ${evento.hora} · reintentos: $reintentos", color = Color(0xFF94A3B8), fontSize = 12.sp)
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
                        if (reintentos < 3) {
                            Text("🔄 Reintentando...", color = Color(0xFFFACC15), fontSize = 13.sp)
                        } else {
                            Text("Atrás para volver", color = Color(0xFF94A3B8), fontSize = 12.sp)
                        }
                    }
                }
                Column(
                    Modifier.weight(1f).fillMaxHeight().background(Color(0x99000000)).padding(14.dp)
                ) {
                    Text("📋 Log", color = Color(0xFF38BDF8), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    LazyColumn {
                        items(logs) { l ->
                            Text(l, color = Color(0xFFA3E635), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
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
                            if (url.contains(".m3u8") && m3u8Url == null) {
                                addLog("🎯 JS: ${url.take(70)}")
                                cookies = CookieManager.getInstance().getCookie(url)
                                m3u8Url = url
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
                                if (u != null && u.contains(".m3u8", ignoreCase = true) && m3u8Url == null) {
                                    addLog("🎯 intercept: ${u.take(70)}")
                                    cookies = CookieManager.getInstance().getCookie(u)
                                    m3u8Url = u
                                }
                                return super.shouldInterceptRequest(view, request)
                            }
                        }

                        loadUrl(embed.url, mapOf("Referer" to embed.referer))
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 11 completo"