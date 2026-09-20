#!/bin/bash
set -e

echo "📁 Paso 9: Player V2 con JS injection..."

# ========== PlayerScreen.kt (reescrito) ==========
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

private const val TAG = "PlayerV2"
private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

// JavaScript agresivo que captura TODO
private const val JS_HOOK = """
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

    // Hook XMLHttpRequest
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
        send(url);
        return _open.apply(this, arguments);
    };

    // Hook fetch
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

    // Hook setAttribute (para video.src)
    var _setAttr = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
        if (name === 'src' && typeof value === 'string') send(value);
        return _setAttr.apply(this, arguments);
    };

    // Hook HLS.js
    var hlsTimer = setInterval(function() {
        if (window.Hls && window.Hls.prototype && !window.Hls.__hooked) {
            window.Hls.__hooked = true;
            var _load = window.Hls.prototype.loadSource;
            window.Hls.prototype.loadSource = function(url) {
                send(url);
                return _load.apply(this, arguments);
            };
        }
    }, 200);

    // Escanear videos cada 500ms
    setInterval(function() {
        try {
            document.querySelectorAll('video, source').forEach(function(v) {
                if (v.src) send(v.src);
                if (v.currentSrc) send(v.currentSrc);
            });
        } catch(e) {}
    }, 500);
})();
""".trimIndent()

class JsBridge(private val onM3u8: (String) -> Unit) {
    @JavascriptInterface
    fun onM3u8(url: String) {
        onM3u8(url)
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PlayerScreen(evento: Evento, embed: Embed, onBack: () -> Unit) {
    val context = LocalContext.current
    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Cargando embed...") }
    var error by remember { mutableStateOf<String?>(null) }
    var debugUrl by remember { mutableStateOf<String?>(null) }
    var exoError by remember { mutableStateOf<String?>(null) }
    var cookies by remember { mutableStateOf<String?>(null) }

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
        onDispose { exoPlayer.release() }
    }

    // Cookie manager activo
    LaunchedEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(
            WebView(context), true
        )
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {

        // Reproductor
        if (m3u8Url != null) {
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

        // Info arriba
        Column(
            Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(20.dp)
        ) {
            Text(evento.descripcion, color = Color(0xFFE2E8F0), fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("${embed.nombre} · ${evento.hora}", color = Color(0xFF94A3B8), fontSize = 13.sp)
        }

        // Overlay de estado
        if (m3u8Url == null || exoError != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(30.dp)) {
                    if (error == null && exoError == null) {
                        CircularProgressIndicator(color = Color(0xFF38BDF8))
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = Color(0xFF94A3B8), fontSize = 16.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Espera hasta 25s...", color = Color(0xFF64748B), fontSize = 12.sp)
                    } else {
                        Text("⚠️ ${error ?: exoError}", color = Color(0xFFEF4444), fontSize = 16.sp, maxLines = 4)
                        Spacer(Modifier.height(16.dp))
                        debugUrl?.let {
                            Text("URL detectada:", color = Color(0xFF94A3B8), fontSize = 11.sp)
                            Text(it.take(300), color = Color(0xFF38BDF8), fontSize = 10.sp, maxLines = 6)
                        }
                    }
                }
            }
        }

        // WebView (1x1, invisible pero cargando todo)
        if (m3u8Url == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(1, 1)
                        settings.apply {
                            javaScriptEnabled = true
                            domStorageEnabled = true
                            databaseEnabled = true
                            userAgentString = USER_AGENT
                            mediaPlaybackRequiresUserGesture = false
                            allowFileAccess = true
                            loadsImagesAutomatically = true
                            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                            cacheMode = WebSettings.LOAD_NO_CACHE
                        }
                        setBackgroundColor(AndroidColor.TRANSPARENT)

                        var resolved = false

                        addJavascriptInterface(JsBridge { url ->
                            if (!resolved && url.contains(".m3u8")) {
                                resolved = true
                                Log.d(TAG, "JS capturó: $url")
                                debugUrl = url
                                // Guardar cookies antes de resolver
                                val ck = CookieManager.getInstance().getCookie(url)
                                cookies = ck
                                Log.d(TAG, "Cookies: $ck")
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
                                view?.evaluateJavascript(JS_HOOK, null)
                                // Inyectar varias veces para asegurar
                                view?.postDelayed({ view.evaluateJavascript(JS_HOOK, null) }, 800)
                                view?.postDelayed({ view.evaluateJavascript(JS_HOOK, null) }, 2000)
                            }

                            override fun shouldInterceptRequest(
                                view: WebView?,
                                request: WebResourceRequest?
                            ): WebResourceResponse? {
                                val url = request?.url?.toString()
                                if (!resolved && url != null && url.contains(".m3u8", ignoreCase = true)) {
                                    resolved = true
                                    Log.d(TAG, "Intercept capturó: $url")
                                    debugUrl = url
                                    val ck = CookieManager.getInstance().getCookie(url)
                                    cookies = ck
                                    m3u8Url = url
                                }
                                return super.shouldInterceptRequest(view, request)
                            }
                        }

                        webChromeClient = object : WebChromeClient() {
                            override fun onConsoleMessage(msg: ConsoleMessage?): Boolean {
                                msg?.let { Log.d(TAG, "JS: ${it.message()}") }
                                return true
                            }
                        }

                        loadUrl(embed.url, mapOf("Referer" to embed.referer))

                        postDelayed({
                            if (!resolved) {
                                error = "Timeout: no se detectó m3u8 en 25s"
                            }
                        }, 25000)
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }

    // Cargar m3u8 en ExoPlayer cuando esté listo
    LaunchedEffect(m3u8Url) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando reproductor..."

            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to embed.referer,
                "Origin" to embed.referer.trimEnd('/')
            )
            cookies?.let { headers["Cookie"] = it }

            Log.d(TAG, "Headers ExoPlayer: $headers")

            val dsFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(20000)
                .setReadTimeoutMs(20000)

            val mediaSource = HlsMediaSource.Factory(dsFactory)
                .setAllowChunklessPreparation(true)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            exoPlayer.setMediaSource(mediaSource)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            exoError = "ExoPlayer init: ${e.message}"
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 9 completo"
ls -la app/src/main/java/com/anonimus757/tvapp/ui/