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
