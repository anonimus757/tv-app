#!/bin/bash
set -e

echo "📁 Fix del PlayerScreen..."

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
        CookieManager.getInstance().setAcceptCookie(true)
        onDispose { exoPlayer.release() }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {

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

        Column(
            Modifier
                .fillMaxWidth()
                .background(Color(0xCC000000))
                .padding(20.dp)
                .align(Alignment.TopStart)
        ) {
            Text(evento.descripcion, color = Color(0xFFE2E8F0), fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("${embed.nombre} · ${evento.hora}", color = Color(0xFF94A3B8), fontSize = 13.sp)
        }

        if (m3u8Url == null || exoError != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(30.dp)
                ) {
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

        if (m3u8Url == null) {
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
                        settings.loadsImagesAutomatically = true
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                        settings.cacheMode = WebSettings.LOAD_NO_CACHE
                        setBackgroundColor(AndroidColor.TRANSPARENT)

                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                        val bridge = JsBridge { url ->
                            if (url.contains(".m3u8")) {
                                Log.d(TAG, "JS capturó: $url")
                                if (m3u8Url == null) {
                                    debugUrl = url
                                    cookies = CookieManager.getInstance().getCookie(url)
                                    m3u8Url = url
                                }
                            }
                        }
                        addJavascriptInterface(bridge, "AndroidBridge")

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

                            override fun shouldInterceptRequest(
                                view: WebView?,
                                request: WebResourceRequest?
                            ): WebResourceResponse? {
                                val u = request?.url?.toString()
                                if (u != null && u.contains(".m3u8", ignoreCase = true)) {
                                    Log.d(TAG, "Intercept: $u")
                                    if (m3u8Url == null) {
                                        debugUrl = u
                                        cookies = CookieManager.getInstance().getCookie(u)
                                        m3u8Url = u
                                    }
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
                            if (m3u8Url == null) {
                                error = "Timeout: no se detectó m3u8 en 25s"
                            }
                        }, 25000)
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }

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

            Log.d(TAG, "Headers: $headers")

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
echo "✅✅✅ Fix aplicado"