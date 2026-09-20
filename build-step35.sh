#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

echo "📝 Reescribiendo PlayerScreen.kt con iconos Material..."
cp "$PKG_DIR/PlayerScreen.kt" "$PKG_DIR/PlayerScreen.kt.bak35" 2>/dev/null || true

cat > "$PKG_DIR/PlayerScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.util.Log
import android.view.ViewGroup
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.M3u8Extractor
import com.anonimus757.tvapp.data.SignalHealthMonitor
import com.anonimus757.tvapp.ui.theme.AppIcons
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TAG = "PlayerLive"
private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
private const val MAX_REINTENTOS_POR_CANAL = 3

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

private enum class ZonaUI { VIDEO, TOP, BOTTOM }

private fun formatoTiempo(segundos: Int): String {
    val h = segundos / 3600
    val m = (segundos % 3600) / 60
    val s = segundos % 60
    return "%02d:%02d:%02d".format(h, m, s)
}

private fun formatoBitrate(bps: Long): String = when {
    bps <= 0 -> "—"
    bps < 1_000_000 -> "${bps / 1000} kbps"
    else -> "%.1f Mbps".format(bps / 1_000_000.0)
}

private fun formatoResolucion(alto: Int): String = if (alto <= 0) "—" else "${alto}p"

private fun barraSalud(porcentaje: Int, bloques: Int = 10): String {
    val llenos = (porcentaje * bloques / 100).coerceIn(0, bloques)
    return "█".repeat(llenos) + "░".repeat(bloques - llenos)
}

private fun colorSalud(porcentaje: Int): Color = when {
    porcentaje >= 70 -> Color(0xFF4ADE80)
    porcentaje >= 40 -> Color(0xFFFACC15)
    else -> Color(0xFFEF4444)
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
    var cookies by remember { mutableStateOf<String?>(null) }
    var reintentos by remember { mutableIntStateOf(0) }
    var reloadTrigger by remember { mutableIntStateOf(0) }

    var panelAbierto by remember { mutableStateOf(false) }
    var mostrarControles by remember { mutableStateOf(true) }
    var refrescando by remember { mutableStateOf(false) }
    var segundosActivo by remember { mutableIntStateOf(0) }
    var avisoCambio by remember { mutableStateOf<String?>(null) }
    var todosFallaron by remember { mutableStateOf(false) }
    var canalesIntentados by remember { mutableStateOf(emptySet<String>()) }

    var zona by remember { mutableStateOf(ZonaUI.VIDEO) }
    var idxBottom by remember { mutableIntStateOf(0) }
    var volumen by remember { mutableFloatStateOf(1f) }
    var reproduciendo by remember { mutableStateOf(false) }
    var calidadActual by remember { mutableStateOf(AjustesStore.obtenerCalidad(context)) }
    var toast by remember { mutableStateOf<String?>(null) }

    val playerFocus = remember { FocusRequester() }

    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }

    val exoPlayer = remember {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 20000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        val calidad = AjustesStore.obtenerCalidad(context)
        val trackSelector = DefaultTrackSelector(context).apply {
            val params = when (calidad) {
                "sd" -> buildUponParameters().setMaxVideoSizeSd()
                "hd" -> buildUponParameters().setMaxVideoSize(1920, 1080)
                else -> buildUponParameters()
            }
            params
                .setAllowVideoMixedMimeTypeAdaptiveness(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
            setParameters(params)
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
                        if (todosFallaron) return
                        scope.launch {
                            if (reintentos >= MAX_REINTENTOS_POR_CANAL) {
                                val siguiente = evento.embeds.firstOrNull {
                                    it.url != embedActual.url && it.url !in canalesIntentados
                                }
                                if (siguiente == null) {
                                    addLog("❌ Todos los canales fallaron")
                                    todosFallaron = true
                                    exoError = "Todos los canales fallaron. Probá más tarde."
                                    return@launch
                                }
                                canalesIntentados = canalesIntentados + embedActual.url
                                addLog("➡️  Cambiando a ${siguiente.nombre}")
                                avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                exoError = null
                                status = "Cambiando de canal..."
                                delay(2000)
                                avisoCambio = null
                                reintentos = 0
                                embedActual = siguiente
                            } else {
                                reintentos++
                                when (reintentos) {
                                    1, 2 -> {
                                        addLog("🔄 Reintento $reintentos/3 (misma URL)")
                                        delay(1000L * reintentos)
                                        exoError = null
                                        reloadTrigger++
                                    }
                                    3 -> {
                                        addLog("🔄 Reintento 3/3 (URL fresca)")
                                        delay(1500L)
                                        val fresh = try {
                                            M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                                        } catch (ex: Exception) { null }
                                        if (fresh != null) {
                                            cookies = M3u8Extractor.cookieString()
                                            exoError = null
                                            m3u8Url = fresh
                                        } else {
                                            addLog("❌ URL fresca falló, saltando canal...")
                                            reintentos = MAX_REINTENTOS_POR_CANAL
                                            val siguiente = evento.embeds.firstOrNull {
                                                it.url != embedActual.url && it.url !in canalesIntentados
                                            }
                                            if (siguiente == null) {
                                                todosFallaron = true
                                                exoError = "Todos los canales fallaron. Probá más tarde."
                                                return@launch
                                            }
                                            canalesIntentados = canalesIntentados + embedActual.url
                                            addLog("➡️  Cambiando a ${siguiente.nombre}")
                                            avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                            exoError = null
                                            status = "Cambiando de canal..."
                                            delay(2000)
                                            avisoCambio = null
                                            reintentos = 0
                                            embedActual = siguiente
                                        }
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
                                reintentos = 0
                                canalesIntentados = canalesIntentados - embedActual.url
                            }
                            Player.STATE_BUFFERING -> addLog("⏳ Buffering...")
                        }
                    }
                })
            }
    }

    val saludMonitor = remember { SignalHealthMonitor(exoPlayer) }
    val salud by saludMonitor.estado.collectAsState()

    DisposableEffect(exoPlayer) {
        val l = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { reproduciendo = isPlaying }
        }
        exoPlayer.addListener(l)
        onDispose { exoPlayer.removeListener(l) }
    }
    LaunchedEffect(volumen) { exoPlayer.volume = volumen }

    val view = androidx.compose.ui.platform.LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as? android.app.Activity)?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    DisposableEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        saludMonitor.iniciar(scope)
        onDispose {
            saludMonitor.detener()
            exoPlayer.release()
        }
    }

    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
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

    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
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

    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }

    LaunchedEffect(mostrarControles, panelAbierto, refrescando, zona, avisoCambio, toast) {
        if (mostrarControles && !panelAbierto && !refrescando && zona == ZonaUI.VIDEO && avisoCambio == null && toast == null) {
            delay(4500)
            mostrarControles = false
        }
    }

    LaunchedEffect(toast) {
        if (toast != null) { delay(1800); toast = null }
    }

    LaunchedEffect(Unit) {
        delay(400)
        try { playerFocus.requestFocus() } catch (_: Exception) {}
    }

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

    val refrescarSenal: () -> Unit = {
        if (!refrescando) {
            scope.launch {
                refrescando = true
                addLog("🔄 Refrescando señal (manual)...")
                try {
                    try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
                    m3u8Url = null
                    exoError = null
                    usarWebView = false
                    reintentos = 0
                    segundosActivo = 0
                    saludMonitor.reset()
                    todosFallaron = false
                    val fresh = try {
                        M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                    } catch (ex: Exception) { null }
                    if (fresh != null) {
                        cookies = M3u8Extractor.cookieString()
                        m3u8Url = fresh
                        addLog("✅ Señal refrescada")
                    } else {
                        addLog("⚠️ Static falló, WebView...")
                        usarWebView = true
                    }
                } finally { refrescando = false }
            }
        }
    }

    val togglePlay: () -> Unit = {
        if (exoPlayer.isPlaying) {
            exoPlayer.pause()
            toast = "Pausado"
        } else {
            exoPlayer.play()
            toast = "Reproduciendo"
        }
    }

    val subirVol: () -> Unit = {
        volumen = (volumen + 0.1f).coerceAtMost(1f)
        toast = "Volumen ${(volumen * 100).toInt()}%"
    }
    val bajarVol: () -> Unit = {
        volumen = (volumen - 0.1f).coerceAtLeast(0f)
        toast = "Volumen ${(volumen * 100).toInt()}%"
    }

    val ciclarCalidad: () -> Unit = {
        calidadActual = when (calidadActual) {
            "auto" -> "hd"
            "hd" -> "sd"
            else -> "auto"
        }
        AjustesStore.guardarCalidad(context, calidadActual)
        try {
            val params = exoPlayer.trackSelectionParameters
            val nuevo = when (calidadActual) {
                "sd" -> params.buildUpon().setMaxVideoSize(854, 480).build()
                "hd" -> params.buildUpon().setMaxVideoSize(1920, 1080).build()
                else -> params.buildUpon().setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE).build()
            }
            exoPlayer.trackSelectionParameters = nuevo
        } catch (_: Exception) {}
        toast = "Calidad: ${calidadActual.uppercase()}"
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(playerFocus)
            .focusable()
            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                if (panelAbierto) return@onKeyEvent false

                when (event.key) {
                    Key.DirectionLeft -> {
                        when (zona) {
                            ZonaUI.VIDEO -> { panelAbierto = true }
                            ZonaUI.TOP -> {}
                            ZonaUI.BOTTOM -> idxBottom = (idxBottom - 1 + 5) % 5
                        }
                        true
                    }
                    Key.DirectionRight -> {
                        when (zona) {
                            ZonaUI.VIDEO -> {}
                            ZonaUI.TOP -> {}
                            ZonaUI.BOTTOM -> idxBottom = (idxBottom + 1) % 5
                        }
                        true
                    }
                    Key.DirectionUp -> {
                        when (zona) {
                            ZonaUI.VIDEO -> { mostrarControles = true; zona = ZonaUI.TOP }
                            ZonaUI.BOTTOM -> zona = ZonaUI.TOP
                            ZonaUI.TOP -> {}
                        }
                        true
                    }
                    Key.DirectionDown -> {
                        when (zona) {
                            ZonaUI.VIDEO -> { mostrarControles = true; zona = ZonaUI.BOTTOM }
                            ZonaUI.TOP -> zona = ZonaUI.BOTTOM
                            ZonaUI.BOTTOM -> zona = ZonaUI.VIDEO
                        }
                        true
                    }
                    Key.DirectionCenter, Key.Enter -> {
                        when (zona) {
                            ZonaUI.VIDEO -> mostrarControles = !mostrarControles
                            ZonaUI.TOP -> refrescarSenal()
                            ZonaUI.BOTTOM -> when (idxBottom) {
                                0 -> togglePlay()
                                1 -> bajarVol()
                                2 -> subirVol()
                                3 -> ciclarCalidad()
                                4 -> panelAbierto = true
                            }
                        }
                        true
                    }
                    Key.Menu -> { refrescarSenal(); true }
                    else -> false
                }
            }
            .pointerInput(panelAbierto) {
                detectHorizontalDragGestures(
                    onDragEnd = {},
                    onHorizontalDrag = { change, dragAmount ->
                        change.consume()
                        if (dragAmount < -20 && !panelAbierto) panelAbierto = true
                        if (dragAmount > 20 && panelAbierto) panelAbierto = false
                    }
                )
            }
            .pointerInput(panelAbierto) {
                detectTapGestures(
                    onTap = {
                        if (!panelAbierto) {
                            mostrarControles = !mostrarControles
                            if (mostrarControles) zona = ZonaUI.VIDEO
                        }
                    },
                    onDoubleTap = { mostrarControles = true; zona = ZonaUI.VIDEO }
                )
            }
    ) {
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

        AnimatedVisibility(
            visible = mostrarControles && !panelAbierto,
            enter = fadeIn(tween(220)) + slideInVertically(tween(220), initialOffsetY = { -it / 3 }),
            exit = fadeOut(tween(180)) + slideOutVertically(tween(180), targetOffsetY = { -it / 3 }),
            modifier = Modifier.align(Alignment.TopStart).fillMaxWidth()
        ) {
            TopOverlay(
                evento = evento,
                embedActual = embedActual,
                segundosActivo = segundosActivo,
                salud = salud,
                reintentos = reintentos,
                maxReintentos = MAX_REINTENTOS_POR_CANAL,
                seleccionado = (zona == ZonaUI.TOP),
                onRefrescar = refrescarSenal,
                refrescando = refrescando
            )
        }

        AnimatedVisibility(
            visible = mostrarControles && !panelAbierto,
            enter = fadeIn(tween(220)) + slideInVertically(tween(220), initialOffsetY = { it / 3 }),
            exit = fadeOut(tween(180)) + slideOutVertically(tween(180), targetOffsetY = { it / 3 }),
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()
        ) {
            BottomControls(
                reproduciendo = reproduciendo,
                volumen = volumen,
                calidad = calidadActual,
                canalesCount = evento.embeds.size,
                seleccionado = (zona == ZonaUI.BOTTOM),
                idxBottom = idxBottom,
                onTogglePlay = togglePlay,
                onSubirVol = subirVol,
                onBajarVol = bajarVol,
                onCiclarCalidad = ciclarCalidad,
                onAbrirPanel = { panelAbierto = true }
            )
        }

        if ((m3u8Url == null || exoError != null) && !refrescando && avisoCambio == null) {
            EstadoOverlay(
                error = exoError,
                status = status,
                reintentos = reintentos,
                maxReintentos = MAX_REINTENTOS_POR_CANAL,
                todosFallaron = todosFallaron
            )
        }

        AnimatedVisibility(
            visible = refrescando,
            enter = fadeIn(), exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xE6000000))
                    .border(2.dp, Color(0x66D4AF37), RoundedCornerShape(20.dp))
                    .padding(horizontal = 40.dp, vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(color = Color(0xFFD4AF37), strokeWidth = 3.dp, modifier = Modifier.size(48.dp))
                Spacer(Modifier.height(16.dp))
                Text("Refrescando señal...", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(4.dp))
                Text("Buscando URL fresca del stream", color = Color(0xFF94A3B8), fontSize = 12.sp)
            }
        }

        AnimatedVisibility(
            visible = avisoCambio != null,
            enter = fadeIn(), exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFD4AF37), RoundedCornerShape(20.dp))
                    .padding(horizontal = 40.dp, vertical = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = AppIcons.senal,
                    contentDescription = null,
                    tint = Color(0xFFD4AF37),
                    modifier = Modifier.size(46.dp)
                )
                Spacer(Modifier.height(12.dp))
                Text(avisoCambio ?: "", color = Color(0xFFD4AF37), fontSize = 19.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text("Ese canal no respondió, probamos otro", color = Color(0xFF94A3B8), fontSize = 12.sp)
            }
        }

        AnimatedVisibility(
            visible = toast != null,
            enter = fadeIn(tween(150)), exit = fadeOut(tween(150)),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Box(
                Modifier
                    .clip(RoundedCornerShape(30.dp))
                    .background(Color(0xEE000000))
                    .border(1.dp, Color(0x66D4AF37), RoundedCornerShape(30.dp))
                    .padding(horizontal = 28.dp, vertical = 14.dp)
            ) {
                Text(toast ?: "", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        AnimatedVisibility(
            visible = panelAbierto,
            enter = slideInHorizontally(tween(220), initialOffsetX = { -it }) + fadeIn(tween(220)),
            exit = slideOutHorizontally(tween(200), targetOffsetX = { -it }) + fadeOut(tween(200)),
            modifier = Modifier.align(Alignment.CenterStart)
        ) {
            PanelLateral(
                evento = evento,
                embedActual = embedActual,
                todosEventos = todosEventos,
                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    embedActual = nuevo
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                },
                onEventoClick = { nuevo -> panelAbierto = false; onEventoChange(nuevo) }
            )
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
                        loadUrl(embedActual.url, mapOf("Referer" to embedActual.referer))
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// TOP OVERLAY
// ═══════════════════════════════════════════════════════════

@Composable
private fun TopOverlay(
    evento: Evento,
    embedActual: Embed,
    segundosActivo: Int,
    salud: SignalHealthMonitor.Salud,
    reintentos: Int,
    maxReintentos: Int,
    seleccionado: Boolean,
    refrescando: Boolean,
    onRefrescar: () -> Unit
) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Black.copy(alpha = 0.92f),
                        Color.Black.copy(alpha = 0.55f),
                        Color.Transparent
                    )
                )
            )
            .padding(horizontal = 32.dp, vertical = 22.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(
                    evento.descripcion,
                    color = Color.White,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = 30.sp
                )
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(embedActual.nombre, color = Color(0xFFFFD700), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("  ·  ", color = Color(0xFF64748B), fontSize = 14.sp)
                    Text(evento.hora, color = Color(0xFFCBD5E1), fontSize = 14.sp)
                    Text("  ·  ", color = Color(0xFF64748B), fontSize = 14.sp)
                    Text(evento.fuente, color = Color(0xFFCBD5E1), fontSize = 14.sp)
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Pill(icono = AppIcons.reloj, texto = formatoTiempo(segundosActivo), colorTexto = Color(0xFFFFD700))
                    PillSalud(salud)
                    Pill(icono = AppIcons.calidad, texto = formatoResolucion(salud.alto))
                    Pill(icono = AppIcons.wifi, texto = formatoBitrate(salud.bitrateBps))
                }
                if (reintentos > 0) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Reintentos: $reintentos/$maxReintentos",
                        color = Color(0xFFFACC15),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Spacer(Modifier.width(24.dp))

            BotonRefrescar(
                seleccionado = seleccionado,
                refrescando = refrescando,
                onClick = onRefrescar
            )
        }
    }
}

@Composable
private fun Pill(
    icono: ImageVector,
    texto: String,
    colorTexto: Color = Color.White,
    colorFondo: Color = Color(0x40000000)
) {
    Row(
        Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(colorFondo)
            .border(1.dp, Color(0x33FFFFFF), RoundedCornerShape(20.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(imageVector = icono, contentDescription = null, tint = colorTexto, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text(texto, color = colorTexto, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun PillSalud(salud: SignalHealthMonitor.Salud) {
    val color = colorSalud(salud.porcentaje)
    Row(
        Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(color.copy(alpha = 0.15f))
            .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(imageVector = AppIcons.senal, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text(
            barraSalud(salud.porcentaje, bloques = 5),
            color = color,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.sp
        )
        Spacer(Modifier.width(6.dp))
        Text("${salud.porcentaje}%", color = color, fontSize = 13.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun BotonRefrescar(
    seleccionado: Boolean,
    refrescando: Boolean,
    onClick: () -> Unit
) {
    val scale by animateFloatAsState(if (seleccionado) 1.05f else 1f, tween(180), label = "rScale")

    Row(
        Modifier
            .scale(scale)
            .clickable(enabled = !refrescando) { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(
                when {
                    refrescando -> Color(0x33FFFFFF)
                    seleccionado -> Color(0xFFFFD700)
                    else -> Color(0x44000000)
                }
            )
            .border(
                width = if (seleccionado) 2.dp else 1.dp,
                color = if (seleccionado) Color(0xFFFFD700) else Color(0x66D4AF37),
                shape = RoundedCornerShape(12.dp)
            )
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (refrescando) {
            CircularProgressIndicator(color = Color(0xFFD4AF37), strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        } else {
            Icon(
                imageVector = AppIcons.refrescar,
                contentDescription = "Refrescar",
                tint = if (seleccionado) Color.Black else Color(0xFFFFD700),
                modifier = Modifier.size(18.dp)
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(
            if (refrescando) "Refrescando..." else "Refrescar señal",
            color = if (seleccionado) Color.Black else Color(0xFFFFD700),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// ═══════════════════════════════════════════════════════════
// BOTTOM CONTROLS
// ═══════════════════════════════════════════════════════════

@Composable
private fun BottomControls(
    reproduciendo: Boolean,
    volumen: Float,
    calidad: String,
    canalesCount: Int,
    seleccionado: Boolean,
    idxBottom: Int,
    onTogglePlay: () -> Unit,
    onSubirVol: () -> Unit,
    onBajarVol: () -> Unit,
    onCiclarCalidad: () -> Unit,
    onAbrirPanel: () -> Unit
) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.75f),
                        Color.Black.copy(alpha = 0.92f)
                    )
                )
            )
            .padding(horizontal = 32.dp, vertical = 24.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            BarButton(
                icono = if (reproduciendo) AppIcons.pausa else AppIcons.play,
                label = null,
                seleccionado = seleccionado && idxBottom == 0,
                grande = true,
                onClick = onTogglePlay
            )
            Spacer(Modifier.width(12.dp))
            BarButton(
                icono = AppIcons.volumenBajo,
                label = null,
                seleccionado = seleccionado && idxBottom == 1,
                onClick = onBajarVol
            )
            Spacer(Modifier.width(8.dp))
            BarButton(
                icono = AppIcons.volumen,
                label = "${(volumen * 100).toInt()}%",
                seleccionado = seleccionado && idxBottom == 2,
                onClick = onSubirVol
            )
            Spacer(Modifier.width(12.dp))
            BarButton(
                icono = AppIcons.calidad,
                label = calidad.uppercase(),
                seleccionado = seleccionado && idxBottom == 3,
                onClick = onCiclarCalidad
            )
            Spacer(Modifier.width(12.dp))
            BarButton(
                icono = AppIcons.canales,
                label = "$canalesCount canales",
                seleccionado = seleccionado && idxBottom == 4,
                onClick = onAbrirPanel
            )
        }
    }
}

@Composable
private fun BarButton(
    icono: ImageVector,
    label: String?,
    seleccionado: Boolean,
    grande: Boolean = false,
    onClick: () -> Unit
) {
    val scale by animateFloatAsState(if (seleccionado) 1.08f else 1f, tween(150), label = "bScale")
    val bg by animateColorAsState(
        if (seleccionado) Color(0xFFFFD700) else Color(0x55000000),
        tween(150), label = "bBg"
    )
    val border by animateColorAsState(
        if (seleccionado) Color(0xFFFFD700) else Color(0x55FFFFFF),
        tween(150), label = "bBd"
    )

    Column(
        Modifier
            .scale(scale)
            .height(if (grande) 64.dp else 54.dp)
            .widthIn(min = if (grande) 64.dp else 54.dp)
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(if (seleccionado) 2.dp else 1.dp, border, RoundedCornerShape(14.dp))
            .padding(horizontal = if (grande) 0.dp else 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = icono,
            contentDescription = label,
            tint = if (seleccionado) Color.Black else Color.White,
            modifier = Modifier.size(if (grande) 28.dp else 22.dp)
        )
        if (label != null) {
            Spacer(Modifier.height(2.dp))
            Text(
                label,
                color = if (seleccionado) Color.Black else Color.White,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// ESTADO (LOADING / ERROR)
// ═══════════════════════════════════════════════════════════

@Composable
private fun EstadoOverlay(
    error: String?,
    status: String,
    reintentos: Int,
    maxReintentos: Int,
    todosFallaron: Boolean
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xCC000000))
                .border(1.dp, Color(0x33FFFFFF), RoundedCornerShape(20.dp))
                .padding(horizontal = 36.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (error == null) {
                CircularProgressIndicator(color = Color(0xFF38BDF8), strokeWidth = 3.dp, modifier = Modifier.size(46.dp))
                Spacer(Modifier.height(18.dp))
                Text(status, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            } else {
                if (!todosFallaron) {
                    CircularProgressIndicator(color = Color(0xFFFACC15), strokeWidth = 3.dp, modifier = Modifier.size(46.dp))
                    Spacer(Modifier.height(18.dp))
                    Text(
                        "Recuperando... ($reintentos/$maxReintentos)",
                        color = Color(0xFFFACC15), fontSize = 16.sp, fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(error, color = Color(0xFF94A3B8), fontSize = 11.sp, maxLines = 3)
                } else {
                    Icon(
                        imageVector = AppIcons.advertencia,
                        contentDescription = null,
                        tint = Color(0xFFEF4444),
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(error, color = Color(0xFFEF4444), fontSize = 15.sp, maxLines = 4, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(10.dp))
                    Text("Desliza ← panel · Atrás para volver", color = Color(0xFF94A3B8), fontSize = 12.sp)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// PANEL LATERAL
// ═══════════════════════════════════════════════════════════

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
            .width(440.dp)
            .fillMaxHeight()
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color(0xF0000000),
                        Color(0xE0000000),
                        Color(0xB0000000)
                    )
                )
            )
            .padding(horizontal = 24.dp, vertical = 32.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(6.dp).clip(CircleShape).background(Color(0xFFFFD700))
            )
            Spacer(Modifier.width(10.dp))
            Text(
                "CANALES DISPONIBLES",
                color = Color(0xFFFFD700),
                fontSize = 12.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 2.sp
            )
        }
        Spacer(Modifier.height(10.dp))
        Text(
            evento.descripcion,
            color = Color.White,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            lineHeight = 24.sp
        )
        Spacer(Modifier.height(4.dp))
        Text("${evento.hora} · ${evento.fuente}", color = Color(0xFF94A3B8), fontSize = 13.sp)

        Spacer(Modifier.height(24.dp))

        val otros = todosEventos.filter {
            it.descripcion != evento.descripcion || it.fuente != evento.fuente
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item(key = "canales_header") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = AppIcons.canales,
                        contentDescription = null,
                        tint = Color(0xFF38BDF8),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Este evento (${evento.embeds.size})",
                        color = Color(0xFF38BDF8),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                }
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
                    Spacer(Modifier.height(24.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.calendario,
                            contentDescription = null,
                            tint = Color(0xFF38BDF8),
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "Otros eventos",
                            color = Color(0xFF38BDF8),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                    }
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
    val bg by animateColorAsState(
        when {
            focused -> Color(0x55D4AF37)
            seleccionado -> Color(0x331E3A8A)
            else -> Color(0x22FFFFFF)
        },
        tween(150), label = "piBg"
    )
    val border by animateColorAsState(
        when {
            focused -> Color(0xFFFFD700)
            seleccionado -> Color(0x884ADE80)
            else -> Color.Transparent
        },
        tween(150), label = "piBd"
    )

    Row(
        modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (focused) 2.dp else 0.dp, border, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(10.dp).clip(CircleShape).background(
                when {
                    seleccionado -> Color(0xFF4ADE80)
                    focused -> Color(0xFFFFD700)
                    else -> Color(0xFF64748B)
                }
            )
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium,
                maxLines = 2
            )
            subtitulo?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, color = Color(0xFFFFD700), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (focused) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color(0xFFFFD700),
                modifier = Modifier.size(18.dp)
            )
        }
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -q "import com.anonimus757.tvapp.ui.theme.AppIcons" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ Import de AppIcons"
grep -q "imageVector = AppIcons.refrescar" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ Botón refrescar con icono"
grep -q "imageVector = AppIcons.canales" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ BottomControls con iconos"
grep -q "imageVector = AppIcons.advertencia" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ Estado error con icono"

echo ""
echo "✅✅✅ Paso 35 completo — PlayerScreen con iconos Material"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"