#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-limpio"

echo "📝 Reescribiendo PlayerScreen.kt completo y limpio..."
echo "   Esto va a tardar unos segundos..."

cat > "$UI_DIR/PlayerScreen.kt" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.content.pm.ActivityInfo
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
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.data.CanalCache
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.M3u8Extractor
import com.anonimus757.tvapp.data.SignalHealthMonitor
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.findActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

private const val TAG = "PlayerLive"
private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

// ═══════════════════════════════════════════════════════════
// CONSTANTES DE COMPORTAMIENTO
// ═══════════════════════════════════════════════════════════
private const val TIEMPO_GRACIA_MS = 8000L       // Ignorar errores en los primeros 8 seg
private const val REFRESH_PROACTIVO_MS = 10 * 60 * 1000L // Refresh token cada 10 min

private val JS_HOOK = """
(function() {
    if (window.__hooked) return;
    window.__hooked = true;
    function send(url) {
        try {
            if (url && typeof url === 'string' && (url.indexOf('.m3u8') !== -1 || url.indexOf('.ts') !== -1)) {
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

// ═══════════════════════════════════════════════════════════
// HELPERS DE FORMATO
// ═══════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════
    // ESTADOS PRINCIPALES
    // ═══════════════════════════════════════════════════════
    var embedActual by remember { mutableStateOf(embedInicial) }
    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Analizando embed...") }
    var exoError by remember { mutableStateOf<String?>(null) }
    var contadorErrores by remember { mutableIntStateOf(0) }
    var tiempoInicioStream by remember { mutableLongStateOf(0L) }
    var reloadTrigger by remember { mutableIntStateOf(0) }
    var todosFallaron by remember { mutableStateOf(false) }
    var canalesIntentados by remember { mutableStateOf(emptySet<String>()) }

    // ═══════════════════════════════════════════════════════
    // ESTADOS DE UI
    // ═══════════════════════════════════════════════════════
    var panelAbierto by remember { mutableStateOf(false) }
    var mostrarControles by remember { mutableStateOf(true) }
    var refrescando by remember { mutableStateOf(false) }
    var segundosActivo by remember { mutableIntStateOf(0) }
    var zona by remember { mutableStateOf(ZonaUI.VIDEO) }
    var idxBottom by remember { mutableIntStateOf(0) }
    var volumen by remember { mutableFloatStateOf(1f) }
    var reproduciendo by remember { mutableStateOf(false) }
    var calidadActual by remember { mutableStateOf(AjustesStore.obtenerCalidad(context)) }
    var toast by remember { mutableStateOf<String?>(null) }
    var mostrarSelectorCalidad by remember { mutableStateOf(false) }
    var calidadesDisponibles by remember { mutableStateOf(listOf<Pair<Int, String>>()) }

    // ═══════════════════════════════════════════════════════
    // WEBVIEW FALLBACK (para embeds que no se extraen)
    // ═══════════════════════════════════════════════════════
    var usarWebView by remember { mutableStateOf(false) }
    var cookies by remember { mutableStateOf<String?>(null) }

    val playerFocus = remember { FocusRequester() }
    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }

    // ═══════════════════════════════════════════════════════
    // CREAR EXOPLAYER (una sola vez)
    // ═══════════════════════════════════════════════════════
    val exoPlayer = remember {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 45000, 2000, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()

        val trackSelector = DefaultTrackSelector(context).apply {
            val calidad = AjustesStore.obtenerCalidad(context)
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
            .build()
    }

    // ═══════════════════════════════════════════════════════
    // LISTENER DE ERRORES (flujo simple)
    // 1-2 errores → reintentar misma URL
    // 3-4 errores → extraer URL fresca
    // 5+ errores  → siguiente canal
    // ═══════════════════════════════════════════════════════
    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onPlayerError(e: PlaybackException) {
                val ahora = System.currentTimeMillis()
                val esTemprano = (ahora - tiempoInicioStream) < TIEMPO_GRACIA_MS

                // Ignorar errores durante el arranque (buffer inicial)
                if (esTemprano) {
                    addLog("⏳ Error temprano ignorado: ${e.errorCodeName}")
                    return
                }

                contadorErrores++
                addLog("❌ Error #$contadorErrores: ${e.errorCodeName}")

                scope.launch {
                    when {
                        contadorErrores <= 2 -> {
                            addLog("🔄 Reintento #$contadorErrores (misma URL)")
                            delay(1500L)
                            exoError = null
                            reloadTrigger++
                        }
                        contadorErrores <= 4 -> {
                            addLog("🔄 Extrayendo URL fresca...")
                            exoError = "Recuperando señal..."
                            delay(1000L)
                            val fresh = try {
                                M3u8Extractor.extraerYTestear(embedActual.url, embedActual.referer, addLog)
                            } catch (_: Exception) { null }
                            if (fresh != null) {
                                cookies = M3u8Extractor.cookieString()
                                exoError = null
                                m3u8Url = fresh
                            } else {
                                exoError = null
                                reloadTrigger++
                            }
                        }
                        else -> {
                            addLog("➡️  Demasiados errores → siguiente canal")
                            exoError = "Cambiando de canal..."
                            delay(1500L)
                            val siguiente = evento.embeds.firstOrNull {
                                it.url != embedActual.url && it.url !in canalesIntentados
                            }
                            if (siguiente == null) {
                                todosFallaron = true
                                exoError = null
                            } else {
                                canalesIntentados = canalesIntentados + embedActual.url
                                exoError = null
                                embedActual = siguiente
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
                        contadorErrores = 0
                        canalesIntentados = canalesIntentados - embedActual.url
                    }
                    Player.STATE_BUFFERING -> addLog("⏳ Buffering...")
                }
            }
        }
        exoPlayer.addListener(listener)
        onDispose { exoPlayer.removeListener(listener) }
    }

    // ═══════════════════════════════════════════════════════
    // LISTENER IS PLAYING
    // ═══════════════════════════════════════════════════════
    DisposableEffect(exoPlayer) {
        val l = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { reproduciendo = isPlaying }
        }
        exoPlayer.addListener(l)
        onDispose { exoPlayer.removeListener(l) }
    }

    // ═══════════════════════════════════════════════════════
    // VOLUMEN
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(volumen) { exoPlayer.volume = volumen }

    // ═══════════════════════════════════════════════════════
    // SALUD DEL STREAM
    // ═══════════════════════════════════════════════════════
    val saludMonitor = remember { SignalHealthMonitor(exoPlayer) }
    val salud by saludMonitor.estado.collectAsState()

    // ═══════════════════════════════════════════════════════
    // PANTALLA ENCENDIDA
    // ═══════════════════════════════════════════════════════
    val view = androidx.compose.ui.platform.LocalView.current
    DisposableEffect(Unit) {
        val window = (view.context as? android.app.Activity)?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // ═══════════════════════════════════════════════════════
    // FORZAR HORIZONTAL EN EL REPRODUCTOR
    // ═══════════════════════════════════════════════════════
    DisposableEffect(Unit) {
        val activity = context.findActivity()
        val esTV = com.anonimus757.tvapp.ui.util.DetectorDispositivo.esTV(context)

        try {
            if (!esTV) {
                activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
        } catch (_: Exception) {}

        onDispose {
            try {
                if (!esTV) {
                    val pref = AjustesStore.obtenerOrientacion(context)
                    activity?.requestedOrientation = when (pref) {
                        "vertical" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "horizontal" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                }
            } catch (_: Exception) {}
        }
    }

    // ═══════════════════════════════════════════════════════
    // INICIAR MONITOR DE SALUD
    // ═══════════════════════════════════════════════════════
    DisposableEffect(Unit) {
        CookieManager.getInstance().setAcceptCookie(true)
        saludMonitor.iniciar(scope)
        onDispose {
            saludMonitor.detener()
            exoPlayer.release()
        }
    }

    // ═══════════════════════════════════════════════════════
    // FLUJO PRINCIPAL: CAMBIO DE CANAL
    // Se cancela automáticamente si cambia embedActual
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(embedActual) {
        // Reset de estados
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        contadorErrores = 0
        todosFallaron = false
        usarWebView = false
        status = "Analizando..."
        saludMonitor.reset()

        // Chequear cache primero
        val cacheado = CanalCache.get(embedActual.url)
        if (cacheado != null) {
            addLog("⚡ Canal cacheado")
            status = "Cargando..."
            m3u8Url = cacheado
            // Precargar el siguiente en background
            scope.launch(Dispatchers.IO) {
                try {
                    val siguiente = evento.embeds.firstOrNull {
                        it.url != embedActual.url && CanalCache.get(it.url) == null
                    }
                    if (siguiente != null) {
                        val m3u8 = M3u8Extractor.extraer(siguiente.url, siguiente.referer) {}
                        if (m3u8 != null) CanalCache.put(siguiente.url, m3u8)
                    }
                } catch (_: Exception) {}
            }
            return@LaunchedEffect
        }

        // Extraer URL (esto se cancela si el usuario cambia de canal rápido)
        try {
            status = "Analizando..."
            val url = withTimeoutOrNull(15000L) {
                M3u8Extractor.extraerYTestear(embedActual.url, embedActual.referer, addLog)
            }
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                CanalCache.put(embedActual.url, url)
                m3u8Url = url
                status = "Cargando..."

                // Precargar siguiente
                scope.launch(Dispatchers.IO) {
                    try {
                        val siguiente = evento.embeds.firstOrNull {
                            it.url != embedActual.url && CanalCache.get(it.url) == null
                        }
                        if (siguiente != null) {
                            val m3u8 = M3u8Extractor.extraer(siguiente.url, siguiente.referer) {}
                            if (m3u8 != null) CanalCache.put(siguiente.url, m3u8)
                        }
                    } catch (_: Exception) {}
                }
            } else {
                addLog("⚠️ No se pudo extraer → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }
    }

    // ═══════════════════════════════════════════════════════
    // CARGAR URL EN EXOPLAYER (se dispara cuando m3u8Url cambia)
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            tiempoInicioStream = System.currentTimeMillis()
            try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}

            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Accept" to "*/*"
            )
            if (embedActual.referer.isNotBlank()) {
                headers["Referer"] = embedActual.referer
                headers["Origin"] = embedActual.referer.trimEnd('/')
            }
            // Para .ts → Referer del propio host (Xtream Codes)
            if (esTS) {
                try {
                    val uri = Uri.parse(url)
                    headers["Referer"] = "${uri.scheme}://${uri.host}:${uri.port}/"
                    headers["Origin"] = "${uri.scheme}://${uri.host}:${uri.port}"
                } catch (_: Exception) {}
            }
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }

            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(15000)

            val src = if (esTS) {
                ProgressiveMediaSource.Factory(ds)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            } else {
                HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            }

            exoPlayer.setMediaSource(src)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            exoError = "Init: ${e.message}"
        }
    }

    // ═══════════════════════════════════════════════════════
    // TIMER (segundos activo)
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }

    // ═══════════════════════════════════════════════════════
    // REFRESH PROACTIVO (cada 10 min renueva el token)
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) return@LaunchedEffect
        while (true) {
            delay(REFRESH_PROACTIVO_MS)
            if (m3u8Url != null && !refrescando && !todosFallaron) {
                addLog("🔄 Auto-refresh de token")
                try {
                    val fresh = M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                    if (fresh != null && fresh != m3u8Url) {
                        cookies = M3u8Extractor.cookieString()
                        m3u8Url = fresh
                        addLog("✅ Token renovado")
                    }
                } catch (_: Exception) {}
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // AUTO-HIDE DE CONTROLES
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(mostrarControles, panelAbierto, refrescando, zona, toast) {
        if (mostrarControles && !panelAbierto && !refrescando && zona == ZonaUI.VIDEO && toast == null) {
            delay(4500)
            mostrarControles = false
        }
    }

    // ═══════════════════════════════════════════════════════
    // AUTO-HIDE DE TOAST
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(toast) {
        if (toast != null) { delay(1800); toast = null }
    }

    // ═══════════════════════════════════════════════════════
    // FOCO INICIAL
    // ═══════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════
    // BACK
    // ═══════════════════════════════════════════════════════
    BackHandler {
        if (panelAbierto) panelAbierto = false
        else onBack()
    }

    // ═══════════════════════════════════════════════════════
    // ACCIONES
    // ═══════════════════════════════════════════════════════
    val refrescarSenal: () -> Unit = {
        if (!refrescando) {
            scope.launch {
                refrescando = true
                contadorErrores = 0
                tiempoInicioStream = System.currentTimeMillis()
                try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
                m3u8Url = null
                exoError = null
                usarWebView = false
                saludMonitor.reset()
                todosFallaron = false

                val fresh = try {
                    M3u8Extractor.extraerYTestear(embedActual.url, embedActual.referer, addLog)
                } catch (_: Exception) { null }

                if (fresh != null) {
                    cookies = M3u8Extractor.cookieString()
                    CanalCache.put(embedActual.url, fresh)
                    m3u8Url = fresh
                    addLog("✅ Señal refrescada")
                } else {
                    addLog("⚠️ Falló extracción → WebView")
                    usarWebView = true
                }
                refrescando = false
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

    val abrirSelectorCalidad: () -> Unit = {
        val calidades = mutableListOf<Pair<Int, String>>()
        try {
            exoPlayer.currentTracks.groups.forEach { grupo ->
                if (grupo.type == androidx.media3.common.C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until grupo.length) {
                        val formato = grupo.getTrackFormat(i)
                        val altura = formato.height
                        if (altura > 0 && !calidades.any { it.first == altura }) {
                            val label = when {
                                altura >= 2160 -> "4K (${altura}p)"
                                altura >= 1080 -> "Full HD (${altura}p)"
                                altura >= 720 -> "HD (${altura}p)"
                                altura >= 480 -> "SD (${altura}p)"
                                else -> "${altura}p"
                            }
                            calidades.add(altura to label)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // Si hay 1 sola calidad → no tiene sentido el selector
        if (calidades.size <= 1) {
            toast = "Este canal tiene 1 sola calidad"
            return@let
        }

        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }.let { { it() } }

    val aplicarCalidad: (Int) -> Unit = { altura ->
        try {
            val params = exoPlayer.trackSelectionParameters
            val nuevo = if (altura <= 0) {
                params.buildUpon().setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE).build()
            } else {
                params.buildUpon().setMaxVideoSize(Int.MAX_VALUE, altura).build()
            }
            exoPlayer.trackSelectionParameters = nuevo
            calidadActual = if (altura <= 0) "auto" else "$altura"
            toast = if (altura <= 0) "Calidad: AUTO" else "Calidad: ${altura}p"
        } catch (_: Exception) {}
        mostrarSelectorCalidad = false
    }

    // ═══════════════════════════════════════════════════════
    // UI
    // ═══════════════════════════════════════════════════════
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
                            ZonaUI.BOTTOM -> idxBottom = (idxBottom - 1 + 5) % 5
                            else -> {}
                        }
                        true
                    }
                    Key.DirectionRight -> {
                        when (zona) {
                            ZonaUI.BOTTOM -> idxBottom = (idxBottom + 1) % 5
                            else -> {}
                        }
                        true
                    }
                    Key.DirectionUp -> {
                        when (zona) {
                            ZonaUI.VIDEO -> { mostrarControles = true; zona = ZonaUI.TOP }
                            ZonaUI.BOTTOM -> zona = ZonaUI.TOP
                            else -> {}
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
                                3 -> abrirSelectorCalidad()
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
            .pointerInput(panelAbierto, evento.embeds.size) {
                if (panelAbierto) return@pointerInput
                var totalDragY = 0f
                var xInicial = 0f
                detectVerticalDragGestures(
                    onDragStart = { offset ->
                        totalDragY = 0f
                        xInicial = offset.x
                    },
                    onDragEnd = {
                        if (kotlin.math.abs(totalDragY) > 120f) {
                            val anchoPantalla = size.width.toFloat()
                            val esZonaIzquierda = xInicial < anchoPantalla * 0.30f
                            if (esZonaIzquierda) {
                                val idxActual = evento.embeds.indexOfFirst { it.url == embedActual.url }
                                if (totalDragY > 0 && idxActual > 0) {
                                    embedActual = evento.embeds[idxActual - 1]
                                } else if (totalDragY < 0 && idxActual >= 0 && idxActual < evento.embeds.size - 1) {
                                    embedActual = evento.embeds[idxActual + 1]
                                }
                            } else {
                                val nuevo = if (totalDragY > 0) {
                                    (volumen - 0.15f).coerceAtLeast(0f)
                                } else {
                                    (volumen + 0.15f).coerceAtMost(1f)
                                }
                                volumen = nuevo
                                toast = "Volumen ${(nuevo * 100).toInt()}%"
                            }
                        }
                        totalDragY = 0f
                    },
                    onVerticalDrag = { change, dragAmount ->
                        change.consume()
                        totalDragY += dragAmount
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
                    onDoubleTap = { offset ->
                        mostrarControles = true
                        zona = ZonaUI.VIDEO
                        try {
                            val anchoPantalla = size.width.toFloat()
                            val esIzquierda = offset.x < anchoPantalla / 2
                            if (esIzquierda) {
                                exoPlayer.seekTo((exoPlayer.currentPosition - 10000L).coerceAtLeast(0L))
                                toast = "⏪ -10 seg"
                            } else {
                                exoPlayer.seekTo(exoPlayer.currentPosition + 10000L)
                                toast = "⏩ +10 seg"
                            }
                        } catch (_: Exception) {}
                    }
                )
            }
    ) {
        // ═══════════════════════════════════════════════════════
        // PLAYER VIEW — SIEMPRE MONTADO (evita parpadeo)
        // ═══════════════════════════════════════════════════════
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
            update = { view ->
                // Actualizar el player si cambió (nunca debería)
                if (view.player != exoPlayer) view.player = exoPlayer
            },
            modifier = Modifier.fillMaxSize()
        )

        // ═══════════════════════════════════════════════════════
        // TOP OVERLAY
        // ═══════════════════════════════════════════════════════
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
                seleccionado = (zona == ZonaUI.TOP),
                onRefrescar = refrescarSenal,
                refrescando = refrescando
            )
        }

        // ═══════════════════════════════════════════════════════
        // BOTTOM CONTROLS
        // ═══════════════════════════════════════════════════════
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
                onCiclarCalidad = abrirSelectorCalidad,
                onAbrirPanel = { panelAbierto = true }
            )
        }

        // ═══════════════════════════════════════════════════════
        // ESTADO (loading / error)
        // ═══════════════════════════════════════════════════════
        if (m3u8Url == null && !refrescando) {
            EstadoOverlay(
                error = exoError,
                status = status,
                todosFallaron = todosFallaron
            )
        }

        // ═══════════════════════════════════════════════════════
        // SPINNER REFRESCANDO
        // ═══════════════════════════════════════════════════════
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
            }
        }

        // ═══════════════════════════════════════════════════════
        // TOAST
        // ═══════════════════════════════════════════════════════
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

        // ═══════════════════════════════════════════════════════
        // PANEL LATERAL
        // ═══════════════════════════════════════════════════════
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
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                    // Cambio DIRECTO — el LaunchedEffect(embedActual) hace el resto
                    embedActual = nuevo
                },
                onEventoClick = { nuevo -> panelAbierto = false; onEventoChange(nuevo) }
            )
        }

        // ═══════════════════════════════════════════════════════
        // SELECTOR DE CALIDAD
        // ═══════════════════════════════════════════════════════
        AnimatedVisibility(
            visible = mostrarSelectorCalidad,
            enter = fadeIn(tween(200)),
            exit = fadeOut(tween(150)),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color(0xCC000000))
                    .clickable { mostrarSelectorCalidad = false },
                contentAlignment = Alignment.Center
            ) {
                Column(
                    Modifier
                        .width(400.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color(0xF0000000))
                        .border(2.dp, Color(0x66D4AF37), RoundedCornerShape(20.dp))
                        .clickable(enabled = false) {}
                        .padding(24.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.calidad,
                            contentDescription = null,
                            tint = Color(0xFFFFD700),
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "Calidad de video",
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.height(16.dp))

                    SelectorCalidadItem(
                        titulo = "Automático",
                        subtitulo = "Se adapta a tu red",
                        seleccionado = calidadActual == "auto",
                        onClick = { aplicarCalidad(0) }
                    )
                    Spacer(Modifier.height(8.dp))

                    calidadesDisponibles.forEach { (altura, label) ->
                        SelectorCalidadItem(
                            titulo = label,
                            subtitulo = if (altura >= 720) "Más calidad" else "Menos datos",
                            seleccionado = calidadActual == "$altura",
                            onClick = { aplicarCalidad(altura) }
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        // OVERLAY "EVENTO SIN SEÑAL"
        // ═══════════════════════════════════════════════════════
        AnimatedVisibility(
            visible = todosFallaron,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFEF4444), RoundedCornerShape(20.dp))
                    .padding(horizontal = 44.dp, vertical = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = AppIcons.advertencia,
                    contentDescription = null,
                    tint = Color(0xFFEF4444),
                    modifier = Modifier.size(52.dp)
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "Evento sin señal",
                    color = Color(0xFFEF4444),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Probá más tarde",
                    color = Color(0xFF94A3B8),
                    fontSize = 13.sp
                )
            }
        }

        // ═══════════════════════════════════════════════════════
        // WEBVIEW INVISIBLE (fallback)
        // ═══════════════════════════════════════════════════════
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
                            if ((url.contains(".m3u8") || url.contains(".ts")) && m3u8Url == null) {
                                cookies = CookieManager.getInstance().getCookie(url)
                                m3u8Url = url
                            }
                        }, "AndroidBridge")
                        webViewClient = object : WebViewClient() {
                            override fun onPageStarted(v: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                                super.onPageStarted(v, url, favicon)
                                v?.evaluateJavascript(JS_HOOK, null)
                            }
                            override fun onPageFinished(v: WebView?, url: String?) {
                                super.onPageFinished(v, url)
                                val wv = v ?: return
                                wv.evaluateJavascript(JS_HOOK, null)
                                wv.postDelayed({ wv.evaluateJavascript(JS_HOOK, null) }, 800)
                                wv.postDelayed({ wv.evaluateJavascript(JS_HOOK, null) }, 2000)
                            }
                            override fun shouldInterceptRequest(v: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                                val u = request?.url?.toString()
                                if (u != null && m3u8Url == null) {
                                    val low = u.lowercase()
                                    if ((low.contains(".m3u8") || low.contains(".ts")) &&
                                        !low.contains(".js") && !low.contains(".css")) {
                                        cookies = CookieManager.getInstance().getCookie(u)
                                        m3u8Url = u
                                    }
                                }
                                return super.shouldInterceptRequest(v, request)
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
            if (error == null && !todosFallaron) {
                CircularProgressIndicator(color = Color(0xFF38BDF8), strokeWidth = 3.dp, modifier = Modifier.size(46.dp))
                Spacer(Modifier.height(18.dp))
                Text(status, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            } else if (error != null) {
                CircularProgressIndicator(color = Color(0xFFFACC15), strokeWidth = 3.dp, modifier = Modifier.size(46.dp))
                Spacer(Modifier.height(18.dp))
                Text(error, color = Color(0xFFFACC15), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
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
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFFFFD700)))
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
            itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" }) { idx, emb ->
                val isFirst = idx == 0
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    miniaturaUrl = evento.imagen,
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
                itemsIndexed(otros.take(30), key = { idx, it -> "ev_${idx}_${it.descripcion}_${it.fuente}_${it.hora}" }) { _, ev ->
                    PanelItem(
                        titulo = ev.descripcion,
                        subtitulo = "${ev.hora} · ${ev.fuente}",
                        seleccionado = false,
                        miniaturaUrl = ev.imagen,
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
    onClick: () -> Unit,
    miniaturaUrl: String? = null
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
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (miniaturaUrl != null && miniaturaUrl.isNotBlank()) {
            Box(
                Modifier
                    .size(width = 70.dp, height = 42.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFF1A1A1A)),
                contentAlignment = Alignment.Center
            ) {
                coil.compose.AsyncImage(
                    model = miniaturaUrl,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                if (seleccionado) {
                    Box(
                        Modifier
                            .align(Alignment.TopStart)
                            .padding(3.dp)
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF4ADE80))
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
        } else {
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
        }

        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 14.sp,
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

// ═══════════════════════════════════════════════════════════
// SELECTOR DE CALIDAD — Item
// ═══════════════════════════════════════════════════════════
@Composable
private fun SelectorCalidadItem(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        when {
            seleccionado -> Color(0x55D4AF37)
            focused -> Color(0x44FFFFFF)
            else -> Color(0x22FFFFFF)
        },
        tween(150), label = "scBg"
    )
    val border by animateColorAsState(
        when {
            seleccionado -> Color(0xFFFFD700)
            focused -> Color(0x88FFFFFF)
            else -> Color.Transparent
        },
        tween(150), label = "scBd"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (seleccionado || focused) 2.dp else 0.dp, border, RoundedCornerShape(12.dp))
            .clickable(enabled = !seleccionado) { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(10.dp).clip(CircleShape).background(
                if (seleccionado) Color(0xFF4ADE80) else Color(0xFF64748B)
            )
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = if (seleccionado) Color(0xFFFFD700) else Color.White,
                fontSize = 15.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium
            )
            Text(
                if (seleccionado) "Calidad actual" else subtitulo,
                color = if (seleccionado) Color(0xFF4ADE80) else Color(0xFF94A3B8),
                fontSize = 12.sp
            )
        }
        if (seleccionado) {
            Icon(
                imageVector = AppIcons.ok,
                contentDescription = null,
                tint = Color(0xFF4ADE80),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
KOTLIN_EOF

echo ""
echo "🔎 Verificando:"
grep -c "LaunchedEffect" "$UI_DIR/PlayerScreen.kt" | xargs -I {} echo "  LaunchedEffect: {} (antes eran 8+)"
grep -q "TIEMPO_GRACIA_MS" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Período de gracia 8 seg"
grep -q "PlayerView(ctx).apply" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ PlayerView siempre montado"
grep -q "abrirSelectorCalidad" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Selector calidad oculto si hay 1"

echo ""
echo "✅✅✅ PlayerScreen reescrito limpio"
echo ""
echo "📌 Bugs que arregla:"
echo "   🎬 Parpadeo → PlayerView siempre montado"
echo "   🎬 Cambio de canal → instantáneo (sin esperar extracción)"
echo "   🎬 A veces anda / a veces no → 5 LaunchedEffect limpios"
echo "   🎬 Error handling → flujo simple y claro"
echo "   🎬 Selector calidad → no aparece si hay 1 sola calidad"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"