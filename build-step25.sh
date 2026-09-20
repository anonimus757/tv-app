#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
mkdir -p "$PKG_DIR/data"
mkdir -p "$PKG_DIR/ui"

# ─────────────────────────────────────────────────────────────
# 1) SignalHealthMonitor.kt (sin cambios respecto a 25a)
# ─────────────────────────────────────────────────────────────
echo "📝 Creando SignalHealthMonitor.kt..."

cat > "$PKG_DIR/data/SignalHealthMonitor.kt" << 'EOF'
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
        val droppedFramesTotal: Long = 0L
    )

    private val _estado = MutableStateFlow(Salud())
    val estado: StateFlow<Salud> = _estado.asStateFlow()

    private val bufferingTimestamps = ArrayDeque<Long>()
    private var droppedFramesTotal = 0L
    private var job: Job? = null

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
                droppedFramesTotal = droppedFramesTotal
            )
        } catch (e: Exception) {
            Log.d("SignalHealth", "actualizar fail: ${e.message}")
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

# ─────────────────────────────────────────────────────────────
# 2) PlayerScreen.kt con salud + auto-cambio de canal
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo PlayerScreen.kt con salud + auto-cambio de canal..."

cat > "$PKG_DIR/ui/PlayerScreen.kt" << 'EOF'
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
import androidx.compose.ui.input.pointer.pointerInput
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
import com.anonimus757.tvapp.data.SignalHealthMonitor
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
    var logs by remember { mutableStateOf(listOf<String>()) }
    var cookies by remember { mutableStateOf<String?>(null) }

    var reintentos by remember { mutableIntStateOf(0) }
    var reloadTrigger by remember { mutableIntStateOf(0) }

    var panelAbierto by remember { mutableStateOf(false) }
    var mostrarInfo by remember { mutableStateOf(true) }

    var refrescando by remember { mutableStateOf(false) }
    var segundosActivo by remember { mutableIntStateOf(0) }
    var botonRefreshFocused by remember { mutableStateOf(false) }

    // ── Auto-cambio de canal ────────────────────────────────
    // Canales ya probados en esta sesión (no se reintentan)
    var canalesIntentados by remember { mutableStateOf(emptySet<String>()) }
    // Toast "📡 Cambiando a ..."
    var avisoCambio by remember { mutableStateOf<String?>(null) }
    // Todos fallaron
    var todosFallaron by remember { mutableStateOf(false) }

    val playerFocus = remember { FocusRequester() }
    val botonRefreshFocus = remember { FocusRequester() }

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

                        // Si ya agotamos TODOS los canales, no hacemos nada más
                        if (todosFallaron) return

                        scope.launch {
                            if (reintentos >= MAX_REINTENTOS_POR_CANAL) {
                                // 4° error en este canal → saltar al siguiente
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
                                avisoCambio = "📡 Cambiando a ${siguiente.nombre}..."
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
                                            // Forzar salto: agotar el contador
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
                                            avisoCambio = "📡 Cambiando a ${siguiente.nombre}..."
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
                                // Canal actual anduvo: lo saco de "intentados" por si
                                // el usuario quiere volver a él más tarde
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
        if (m3u8Url == null) {
            segundosActivo = 0
            return@LaunchedEffect
        }
        segundosActivo = 0
        while (true) {
            delay(1000)
            segundosActivo++
        }
    }

    LaunchedEffect(mostrarInfo, panelAbierto, refrescando, botonRefreshFocused, avisoCambio) {
        if (mostrarInfo && !panelAbierto && !refrescando && !botonRefreshFocused && avisoCambio == null) {
            delay(4000)
            mostrarInfo = false
        }
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
                    } catch (ex: Exception) {
                        addLog("❌ ${ex.message}")
                        null
                    }

                    if (fresh != null) {
                        cookies = M3u8Extractor.cookieString()
                        m3u8Url = fresh
                        addLog("✅ Señal refrescada")
                    } else {
                        addLog("⚠️ Static falló, WebView...")
                        usarWebView = true
                    }
                } finally {
                    refrescando = false
                }
            }
        }
    }

    val requestBotonFocus: () -> Unit = {
        scope.launch {
            for (i in 1..10) {
                delay(50)
                try {
                    botonRefreshFocus.requestFocus()
                    break
                } catch (_: Exception) {}
            }
        }
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
                    Key.DirectionUp -> {
                        if (!panelAbierto) {
                            if (!mostrarInfo) mostrarInfo = true
                            requestBotonFocus()
                            true
                        } else false
                    }
                    Key.DirectionCenter, Key.Enter -> {
                        if (!panelAbierto) { mostrarInfo = !mostrarInfo; true } else false
                    }
                    Key.Menu -> {
                        if (!panelAbierto) { refrescarSenal(); true } else false
                    }
                    else -> false
                }
            }
            .pointerInput(panelAbierto) {
                detectHorizontalDragGestures(
                    onDragEnd = {},
                    onHorizontalDrag = { change, dragAmount ->
                        change.consume()
                        if (dragAmount < -20 && !panelAbierto) {
                            panelAbierto = true
                        }
                        if (dragAmount > 20 && panelAbierto) {
                            panelAbierto = false
                        }
                    }
                )
            }
            .pointerInput(panelAbierto) {
                detectTapGestures(
                    onTap = {
                        if (!panelAbierto) {
                            mostrarInfo = !mostrarInfo
                        }
                    },
                    onDoubleTap = { mostrarInfo = true }
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
            visible = mostrarInfo && !panelAbierto,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopStart).fillMaxWidth()
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(Color(0x99000000))
                    .padding(horizontal = 28.dp, vertical = 20.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        evento.descripcion,
                        color = Color.White,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${embedActual.nombre} · ${evento.hora} · ${evento.fuente}",
                        color = Color(0xFFCCCCCC),
                        fontSize = 14.sp
                    )
                    if (reintentos > 0) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "🔄 Reintentos: $reintentos/$MAX_REINTENTOS_POR_CANAL",
                            color = Color(0xFFFACC15),
                            fontSize = 12.sp
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "← panel · ↑ refrescar · OK info · MENU atajo",
                        color = Color(0xFF94A3B8),
                        fontSize = 11.sp
                    )
                }

                Spacer(Modifier.width(20.dp))

                Column(horizontalAlignment = Alignment.End) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("⏱", fontSize = 18.sp)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            formatoTiempo(segundosActivo),
                            color = Color(0xFFD4AF37),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Spacer(Modifier.height(6.dp))
                    FilaSalud(salud)
                    Spacer(Modifier.height(10.dp))
                    BotonRefrescar(
                        refrescando = refrescando,
                        focusRequester = botonRefreshFocus,
                        onFocusChanged = { botonRefreshFocused = it },
                        onClick = { refrescarSenal() },
                        onDown = {
                            try { playerFocus.requestFocus() } catch (_: Exception) {}
                        }
                    )
                }
            }
        }

        if ((m3u8Url == null || exoError != null) && !refrescando && avisoCambio == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(30.dp)
                ) {
                    if (exoError == null) {
                        CircularProgressIndicator(color = Color(0xFF38BDF8))
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = Color(0xFFCCCCCC), fontSize = 16.sp)
                    } else {
                        val errorMsg = exoError ?: ""
                        if (!todosFallaron) {
                            CircularProgressIndicator(color = Color(0xFFFACC15))
                            Spacer(Modifier.height(16.dp))
                            Text(
                                "🔄 Recuperando... ($reintentos/$MAX_REINTENTOS_POR_CANAL)",
                                color = Color(0xFFFACC15),
                                fontSize = 16.sp
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(errorMsg, color = Color(0xFF94A3B8), fontSize = 11.sp, maxLines = 3)
                        } else {
                            Text("⚠️ $errorMsg", color = Color(0xFFEF4444), fontSize = 15.sp, maxLines = 4)
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "Desliza ← panel · Atrás para volver",
                                color = Color(0xFF94A3B8),
                                fontSize = 13.sp
                            )
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = refrescando,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xCC000000))
                    .padding(horizontal = 32.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(
                    color = Color(0xFFD4AF37),
                    strokeWidth = 3.dp,
                    modifier = Modifier.size(46.dp)
                )
                Spacer(Modifier.height(14.dp))
                Text(
                    "Refrescando señal...",
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Buscando URL fresca del stream",
                    color = Color(0xFF94A3B8),
                    fontSize = 12.sp
                )
            }
        }

        // ── Toast "📡 Cambiando a ..." ─────────────────────
        AnimatedVisibility(
            visible = avisoCambio != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xE6000000))
                    .border(2.dp, Color(0xFFD4AF37), RoundedCornerShape(16.dp))
                    .padding(horizontal = 36.dp, vertical = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("📡", fontSize = 38.sp)
                Spacer(Modifier.height(10.dp))
                Text(
                    avisoCambio ?: "",
                    color = Color(0xFFD4AF37),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Ese canal no respondió, probamos otro",
                    color = Color(0xFF94A3B8),
                    fontSize = 12.sp
                )
            }
        }

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
                onCanalClick = { nuevo ->
                    // Cambio manual: resetear flags para permitir auto-switch futuro
                    reintentos = 0
                    todosFallaron = false
                    embedActual = nuevo
                    panelAbierto = false
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

@Composable
private fun FilaSalud(salud: SignalHealthMonitor.Salud) {
    val color = colorSalud(salud.porcentaje)
    val barra = barraSalud(salud.porcentaje)
    val bitrateTxt = formatoBitrate(salud.bitrateBps)
    val resTxt = formatoResolucion(salud.alto)
    val fpsTxt = if (salud.fps > 0f) "%.0f".format(salud.fps) else "—"

    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("📡", fontSize = 14.sp)
        Spacer(Modifier.width(6.dp))
        Text(barra, color = color, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(6.dp))
        Text("${salud.porcentaje}%", color = color, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(14.dp))
        Text("🎞 $resTxt · ${fpsTxt}fps", color = Color(0xFFCBD5E1), fontSize = 12.sp)
        Spacer(Modifier.width(14.dp))
        Text("📶 $bitrateTxt", color = Color(0xFFCBD5E1), fontSize = 12.sp)
    }
}

@Composable
private fun BotonRefrescar(
    refrescando: Boolean,
    focusRequester: FocusRequester,
    onFocusChanged: (Boolean) -> Unit,
    onClick: () -> Unit,
    onDown: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .focusRequester(focusRequester)
            .onFocusChanged {
                focused = it.isFocused
                onFocusChanged(it.isFocused)
            }
            .focusable()
            .clickable(enabled = !refrescando) { onClick() }
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionDown -> { onDown(); true }
                    Key.DirectionCenter, Key.Enter -> {
                        if (!refrescando) onClick()
                        true
                    }
                    else -> false
                }
            }
            .clip(RoundedCornerShape(8.dp))
            .background(
                when {
                    refrescando -> Color(0x33FFFFFF)
                    focused -> Color(0xFFD4AF37)
                    else -> Color(0x22FFFFFF)
                }
            )
            .border(
                width = if (focused) 2.dp else 1.dp,
                color = if (focused) Color(0xFFFFD700) else Color(0xFFD4AF37),
                shape = RoundedCornerShape(8.dp)
            )
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (refrescando) {
            CircularProgressIndicator(
                color = Color(0xFFD4AF37),
                strokeWidth = 2.dp,
                modifier = Modifier.size(16.dp)
            )
        } else {
            Text("🔄", fontSize = 14.sp)
        }
        Spacer(Modifier.width(8.dp))
        Text(
            if (refrescando) "Refrescando..." else "Refrescar señal",
            color = when {
                refrescando -> Color(0xFFD4AF37)
                focused -> Color.Black
                else -> Color(0xFFD4AF37)
            },
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold
        )
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
        Text(
            "📺 ${evento.descripcion}",
            color = Color.White,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2
        )
        Spacer(Modifier.height(4.dp))
        Text("${evento.hora} · ${evento.fuente}", color = Color(0xFF94A3B8), fontSize = 13.sp)

        Spacer(Modifier.height(20.dp))

        val otros = todosEventos.filter {
            it.descripcion != evento.descripcion || it.fuente != evento.fuente
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item(key = "canales_header") {
                Text(
                    "🎬 Canales (${evento.embeds.size})",
                    color = Color(0xFF38BDF8),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
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
                    Text(
                        "📅 Otros eventos",
                        color = Color(0xFF38BDF8),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
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
            Text(
                titulo,
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 2
            )
            subtitulo?.let {
                Text(it, color = Color(0xFF94A3B8), fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}
EOF

echo ""
echo "🔎 Verificando:"
[ -f "$PKG_DIR/data/SignalHealthMonitor.kt" ] && echo "  ✓ SignalHealthMonitor.kt"
[ -f "$PKG_DIR/ui/PlayerScreen.kt" ] && echo "  ✓ PlayerScreen.kt reescrito"
grep -q "canalesIntentados" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ Auto-cambio de canal integrado"
grep -q "avisoCambio" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ Toast de cambio integrado"

echo ""
echo "✅✅✅ Paso 25 completo"
echo ""
echo "📌 Qué hace ahora el reproductor:"
echo "   1. Mide salud (bitrate, resolución, buffering, drops)"
echo "   2. Muestra barrita + datos técnicos en el overlay"
echo "   3. Si el canal falla: 2 reintentos + 1 URL fresca"
echo "   4. Si sigue fallando: SALTA AL SIGUIENTE CANAL del evento"
echo "   5. Toast dorado '📡 Cambiando a Canal X...' durante el salto"
echo "   6. Recuerda los canales que ya fallaron (no los reintenta)"
echo "   7. Si probó todos y todos fallaron: avisa y para"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"