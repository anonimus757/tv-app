#!/bin/bash
set -e

echo "📁 Paso 14: Fix navegación + auto-retry..."

cat > app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.util.Log
import android.view.ViewGroup
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.platform.LocalContext
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
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.M3u8Extractor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "PlayerLive"
private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
private const val MAX_REINTENTOS = 6

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
    setInterval(function() {
        if (window.Hls && window.Hls.prototype && !window.Hls.__hooked) {
            window.Hls.__hooked = true;
            var _load = window.Hls.prototype.loadSource;
            window.Hls.prototype.loadSource = function(url) { send(url); return _load.apply(this, arguments); };
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

@SuppressLint("SetJavaScriptEnabled", "UnsafeOptInUsageError")
@Composable
fun PlayerScreen(
    evento: Evento,
    embedInicial: Embed,
    todosEventos: List<Evento>,
    onBack: () -> Unit,
    onEventoChange: (Evento) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var embedActual by remember { mutableStateOf(embedInicial) }
    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Analizando embed...") }
    var exoError by remember { mutableStateOf<String?>(null) }
    var usarWebView by remember { mutableStateOf(false) }
    var logs by remember { mutableStateOf(listOf<String>()) }
    var cookies by remember { mutableStateOf<String?>(null) }

    var reintentos by remember { mutableIntStateOf(0) }
    var reloadTrigger by remember { mutableIntStateOf(0) }

    var panelAbierto by remember { mutableStateOf(false) }
    var mostrarInfo by remember { mutableStateOf(true) }

    val playerFocus = remember { FocusRequester() }

    val addLog: (String) -> Unit = { msg ->
        Log.d(TAG, msg)
        logs = (logs + msg).takeLast(30)
    }

    val exoPlayer = remember {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 20000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        val trackSelector = DefaultTrackSelector(context).apply {
            setParameters(
                buildUponParameters()
                    .setMaxVideoSizeSd()
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
                addListener(object : Player.Listener {
                    override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        exoError = "$code: ${e.message?.take(160)}"
                        addLog("❌ $code")

                        if (reintentos >= MAX_REINTENTOS) {
                            addLog("❌ Máximo de reintentos alcanzado")
                            return
                        }
                        reintentos++

                        scope.launch {
                            if (reintentos <= 3) {
                                // Recargar MISMA URL (fallo típico de red inicial)
                                addLog("🔄 Recargando misma URL... #$reintentos")
                                delay(1000L * reintentos)
                                exoError = null
                                reloadTrigger++
                            } else {
                                // URL fresca (token caducó)
                                addLog("🔄 Extrayendo URL fresca... #$reintentos")
                                delay(1500L)
                                val fresh = try {
                                    M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                                } catch (ex: Exception) { null }
                                if (fresh != null) {
                                    cookies = M3u8Extractor.cookieString()
                                    exoError = null
                                    m3u8Url = fresh
                                } else {
                                    addLog("❌ No se pudo refrescar")
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
                                reintentos = 0
                            }
                            Player.STATE_BUFFERING -> addLog("⏳ Buffering...")
                        }
                    }
                })
            }
    }

    DisposableEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        onDispose { exoPlayer.release() }
    }

    // Extracción al cambiar embed
    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        addLog("🔍 Analizando ${embedActual.nombre}...")

        try {
            val url = M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
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

    // Cargar en ExoPlayer (se re-ejecuta con reloadTrigger)
    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            try {
                exoPlayer.stop()
                exoPlayer.clearMediaItems()
            } catch (_: Exception) {}

            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to embedActual.referer,
                "Origin" to embedActual.referer.trimEnd('/')
            )
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }

            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(20000)
                .setReadTimeoutMs(20000)

            val src = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(false)
                .setUseSessionKeys(false)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            exoPlayer.setMediaSource(src)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            exoError = "Init: ${e.message}"
        }
    }

    // Auto-hide info
    LaunchedEffect(mostrarInfo, panelAbierto) {
        if (mostrarInfo && !panelAbierto) {
            delay(4000)
            mostrarInfo = false
        }
    }

    // Foco inicial
    LaunchedEffect(Unit) {
        delay(400)
        try { playerFocus.requestFocus() } catch (_: Exception) {}
    }

    // Al cerrar el panel, devolver foco al video
    LaunchedEffect(panelAbierto) {
        if (!panelAbierto) {
            delay(150)
            try { playerFocus.requestFocus() } catch (_: Exception) {}
        }
    }

    BackHandler {
        if (panelAbierto) panelAbierto = false
        else onBack()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(playerFocus)
            .focusable()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.key) {
                    Key.DirectionLeft -> {
                        if (!panelAbierto) { panelAbierto = true; true } else false
                    }
                    Key.DirectionRight -> {
                        if (panelAbierto) { panelAbierto = false; true } else false
                    }
                    Key.DirectionCenter, Key.Enter -> {
                        if (!panelAbierto) { mostrarInfo = !mostrarInfo; true } else false
                    }
                    else -> false
                }
            }
    ) {
        // Video fullscreen (SIN controles, SIN foco)
        if (m3u8Url != null && exoError == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        // Info overlay
        AnimatedVisibility(
            visible = mostrarInfo && !panelAbierto,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopStart)
        ) {
            Column(
                Modifier
                    .background(Color(0x99000000))
                    .padding(horizontal = 28.dp, vertical = 20.dp)
            ) {
                Text(evento.descripcion, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                Spacer(Modifier.height(4.dp))
                Text("${embedActual.nombre} · ${evento.hora} · ${evento.fuente}", color = Color(0xFFCCCCCC), fontSize = 14.sp)
                if (reintentos > 0) {
                    Spacer(Modifier.height(4.dp))
                    Text("🔄 Reintentos: $reintentos", color = Color(0xFFFACC15), fontSize = 12.sp)
                }
            }
        }

        // Cargando / error
        if (m3u8Url == null || exoError != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(30.dp)) {
                    if (exoError == null) {
                        CircularProgressIndicator(color = Color(0xFF38BDF8))
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = Color(0xFFCCCCCC), fontSize = 16.sp)
                    } else {
                        if (reintentos < MAX_REINTENTOS) {
                            CircularProgressIndicator(color = Color(0xFFFACC15))
                            Spacer(Modifier.height(16.dp))
                            Text("🔄 Recuperando... ($reintentos/$MAX_REINTENTOS)", color = Color(0xFFFACC15), fontSize = 16.sp)
                            Spacer(Modifier.height(6.dp))
                            Text(exoError, color = Color(0xFF94A3B8), fontSize = 11.sp, maxLines = 3)
                        } else {
                            Text("⚠️ $exoError", color = Color(0xFFEF4444), fontSize = 15.sp, maxLines = 4)
                            Spacer(Modifier.height(8.dp))
                            Text("← panel · atrás para volver", color = Color(0xFF94A3B8), fontSize = 13.sp)
                        }
                    }
                }
            }
        }

        // Panel lateral
        AnimatedVisibility(
            visible = panelAbierto,
            enter = slideInHorizontally(initialOffsetX = { -it }) + fadeIn(),
            exit = slideOutHorizontally(targetOffsetX = { -it }) + fadeOut(),
            modifier = Modifier.align(Alignment.CenterStart)
        ) {
            PanelLateral(
                evento = evento,
                embedActual = embedActual,
                todosEventos = todosEventos,
                onCanalClick = { nuevo -> embedActual = nuevo; panelAbierto = false },
                onEventoClick = { nuevo -> panelAbierto = false; onEventoChange(nuevo) }
            )
        }

        // WebView fallback
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
                        loadUrl(embedActual.url, mapOf("Referer" to embedActual.referer))
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }
}

@Composable
private fun PanelLateral(
    evento: Evento,
    embedActual: Embed,
    todosEventos: List<Evento>,
    onCanalClick: (Embed) -> Unit,
    onEventoClick: (Evento) -> Unit
) {
    val primerItemFocus = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        delay(250)
        try { primerItemFocus.requestFocus() } catch (_: Exception) {}
    }

    Column(
        Modifier
            .width(420.dp)
            .fillMaxHeight()
            .background(Color(0xE6000000))
            .padding(horizontal = 20.dp, vertical = 28.dp)
    ) {
        Text("📺 ${evento.descripcion}", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2)
        Spacer(Modifier.height(4.dp))
        Text("${evento.hora} · ${evento.fuente}", color = Color(0xFF94A3B8), fontSize = 13.sp)

        Spacer(Modifier.height(20.dp))

        val otros = todosEventos.filter { it.descripcion != evento.descripcion || it.fuente != evento.fuente }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item(key = "canales_header") {
                Text("🎬 Canales (${evento.embeds.size})", color = Color(0xFF38BDF8), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
            items(evento.embeds, key = { "emb_" + it.url }) { emb ->
                val isFirst = evento.embeds.isNotEmpty() && emb.url == evento.embeds.first().url
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    onClick = { onCanalClick(emb) }
                )
            }

            if (otros.isNotEmpty()) {
                item(key = "otros_header") {
                    Spacer(Modifier.height(20.dp))
                    Text("📅 Otros eventos", color = Color(0xFF38BDF8), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
                items(otros.take(30), key = { "ev_" + it.descripcion + it.fuente + it.hora }) { ev ->
                    PanelItem(
                        titulo = ev.descripcion,
                        subtitulo = "${ev.hora} · ${ev.fuente}",
                        seleccionado = false,
                        onClick = { onEventoClick(ev) }
                    )
                }
            }
        }
    }
}

@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    Row(
        modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .clip(RoundedCornerShape(8.dp))
            .background(
                when {
                    focused -> Color(0xFF334155)
                    seleccionado -> Color(0xFF1E3A8A66)
                    else -> Color(0x33FFFFFF)
                }
            )
            .clickable { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(8.dp).clip(CircleShape).background(
                when {
                    seleccionado -> Color(0xFF4ADE80)
                    focused -> Color(0xFF38BDF8)
                    else -> Color(0xFF64748B)
                }
            )
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(titulo, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 2)
            subtitulo?.let {
                Text(it, color = Color(0xFF94A3B8), fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 14 completo"