#!/bin/bash
set -e

DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.v4.$(date +%s)"
echo "✅ Backup: ${DETAIL}.bak.v4.$(date +%s)"

cat > "$DETAIL" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.ApiSportsRepository
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.EstadisticasPartido
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.EventoPartido
import com.anonimus757.tvapp.data.PartidoEnVivo
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.rememberEsTV
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

// ═══════════════════════════════════════════════════════════════
// ESTADO
// ═══════════════════════════════════════════════════════════════

enum class EstadoEvento { PROXIMO, EN_VIVO, FINALIZADO }

private fun calcularEstado(ev: Evento): EstadoEvento {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val fechaEv = sdf.parse(ev.fecha) ?: return EstadoEvento.PROXIMO
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEv
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val diffDias = ((cal.timeInMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()

        if (diffDias > 0) return EstadoEvento.PROXIMO
        if (diffDias < 0) return EstadoEvento.FINALIZADO

        val ahora = Calendar.getInstance()
        val minActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val match = Regex("""(\d{1,2}):(\d{2})""").find(ev.hora)
        val minEvento = match?.let {
            (it.groupValues[1].toIntOrNull() ?: 0) * 60 + (it.groupValues[2].toIntOrNull() ?: 0)
        } ?: 0

        when {
            minActual < minEvento -> EstadoEvento.PROXIMO
            minActual < minEvento + ev.duracionMinutos -> EstadoEvento.EN_VIVO
            else -> EstadoEvento.FINALIZADO
        }
    } catch (e: Exception) { EstadoEvento.PROXIMO }
}

private fun minutosHasta(ev: Evento): Int? {
    return try {
        val ahora = Calendar.getInstance()
        val minActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val match = Regex("""(\d{1,2}):(\d{2})""").find(ev.hora) ?: return null
        val minEvento = (match.groupValues[1].toIntOrNull() ?: 0) * 60 + (match.groupValues[2].toIntOrNull() ?: 0)
        if (minEvento > minActual) minEvento - minActual else null
    } catch (e: Exception) { null }
}

private fun estadoHumano(corto: String): String = when (corto) {
    "NS" -> "PRÓXIMO"
    "1H" -> "1ER TIEMPO"
    "HT" -> "DESCANSO"
    "2H" -> "2DO TIEMPO"
    "ET" -> "PRÓRROGA"
    "BT" -> "DESCANSO PRÓRROGA"
    "P" -> "PENALES"
    "FT" -> "FINALIZADO"
    "AET" -> "FINALIZADO (PRÓRROGA)"
    "PEN" -> "FINALIZADO (PENALES)"
    "SUSP" -> "SUSPENDIDO"
    "PST" -> "POSTERGADO"
    "CANC" -> "CANCELADO"
    "LIVE" -> "EN VIVO"
    else -> corto
}

private fun emojiEvento(tipo: String, detalle: String): String = when {
    tipo == "Goal" && detalle == "Own Goal" -> "🔴"
    tipo == "Goal" && detalle == "Penalty" -> "⚽"
    tipo == "Goal" -> "⚽"
    tipo == "Card" && detalle == "Yellow Card" -> "🟨"
    tipo == "Card" && detalle == "Red Card" -> "🟥"
    tipo == "Card" && detalle == "Second Yellow card" -> "🟨🟥"
    tipo == "subst" -> "🔄"
    tipo == "Var" -> "📺"
    else -> "•"
}

private fun colorEvento(tipo: String, detalle: String): Color = when {
    tipo == "Goal" -> Color(0xFF4ADE80)          // verde
    tipo == "Card" && detalle == "Yellow Card" -> Color(0xFFFFD93D)
    tipo == "Card" && detalle == "Red Card" -> Color(0xFFFF3B30)
    tipo == "Card" && detalle == "Second Yellow card" -> Color(0xFFFF3B30)
    tipo == "subst" -> Color(0xFF60A5FA)         // azul
    tipo == "Var" -> Color(0xFFA78BFA)           // violeta
    else -> Color(0xFF9CA3AF)
}

// ═══════════════════════════════════════════════════════════════
// VIDEO EN BUCLE
// ═══════════════════════════════════════════════════════════════

@Composable
private fun VideoLoopPlayer(url: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val exoPlayer = remember(url) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(url))
            repeatMode = Player.REPEAT_MODE_ALL
            volume = 0f
            playWhenReady = true
            prepare()
        }
    }
    DisposableEffect(url) {
        onDispose { exoPlayer.release() }
    }
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                player = exoPlayer
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
        },
        modifier = modifier
    )
}

// ═══════════════════════════════════════════════════════════════
// PANTALLA PRINCIPAL
// ═══════════════════════════════════════════════════════════════

@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    BackHandler { onBack() }

    val esTV = rememberEsTV()
    val configuration = LocalConfiguration.current
    val esVertical = configuration.orientation == Configuration.ORIENTATION_PORTRAIT
    val esMovil = !esTV && esVertical

    val color = AppColors.fuenteColor(evento.groupTitle)
    val scope = rememberCoroutineScope()

    val estado = remember(evento) { calcularEstado(evento) }

    var partido by remember { mutableStateOf<PartidoEnVivo?>(null) }
    var cargandoPartido by remember { mutableStateOf(false) }
    var errorPartido by remember { mutableStateOf<String?>(null) }
    var statsExpandidas by remember { mutableStateOf(false) }

    LaunchedEffect(evento.descripcion, evento.fecha, estado) {
        if (estado != EstadoEvento.EN_VIVO) return@LaunchedEffect
        val tieneEquipos = evento.equipoLocal.isNotBlank() && evento.visitante().isNotBlank()
        if (!tieneEquipos) return@LaunchedEffect
        if (!ApiSportsRepository.tieneApiKey()) {
            errorPartido = "Configurá la API key"
            return@LaunchedEffect
        }
        cargandoPartido = true
        errorPartido = null
        try {
            val fid = evento.fixtureId ?: ApiSportsRepository.resolverFixtureId(
                evento.equipoLocal, evento.equipoVisitante, evento.fecha
            )
            if (fid != null) {
                partido = ApiSportsRepository.obtenerPartidoEnVivo(fid)
                if (partido == null) errorPartido = "Sin datos del partido"
            } else {
                errorPartido = "Buscando partido..."
            }
        } catch (e: Exception) {
            errorPartido = e.message
        }
        cargandoPartido = false
    }

    LaunchedEffect(partido?.fixtureId, estado) {
        val id = partido?.fixtureId ?: return@LaunchedEffect
        if (estado != EstadoEvento.EN_VIVO) return@LaunchedEffect
        while (true) {
            delay(60_000)
            val nuevo = ApiSportsRepository.obtenerPartidoEnVivo(id, forzarRefresh = true)
            if (nuevo != null) partido = nuevo
        }
    }

    val paddingH = if (esMovil) 16.dp else 48.dp
    val paddingV = if (esMovil) 16.dp else 32.dp

    Box(Modifier.fillMaxSize().background(Color(0xFF050505))) {
        FondoDetalle()

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = paddingH, end = paddingH,
                top = paddingV, bottom = 60.dp
            ),
            verticalArrangement = Arrangement.spacedBy(if (esMovil) 14.dp else 18.dp)
        ) {
            // Botón volver
            item(key = "volver") {
                Box(Modifier.fadeInOnLoad(300)) {
                    BotonVolver(onBack, esTV)
                }
            }

            // Hero dramático
            item(key = "hero") {
                HeroDramatico(evento, esTV, esMovil, color, estado, minutosHasta(evento))
            }

            // Sección según estado
            when (estado) {
                EstadoEvento.EN_VIVO -> {
                    item(key = "api") {
                        SeccionEnVivo(evento, partido, cargandoPartido, errorPartido, esTV, esMovil, statsExpandidas) {
                            statsExpandidas = !statsExpandidas
                        }
                    }
                    // Canales SOLO en vivo
                    item(key = "head_canales") {
                        RowCanalesPremium(evento, esTV, esMovil)
                    }
                    itemsIndexed(
                        items = evento.embeds,
                        key = { idx, it -> "emb_${idx}_${it.url}" }
                    ) { index, embed ->
                        Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                            CanalCardPremium(embed, index + 1, esTV, esMovil) { onCanalClick(embed) }
                        }
                    }
                }
                EstadoEvento.FINALIZADO -> {
                    item(key = "finalizado") {
                        SeccionFinalizado(evento, esTV, esMovil)
                    }
                }
                EstadoEvento.PROXIMO -> {
                    item(key = "proximo") {
                        SeccionProximo(evento, esTV, esMovil, minutosHasta(evento))
                    }
                }
            }

            item(key = "footer") { Spacer(Modifier.height(30.dp)) }
        }
    }
}

// Helper para visitante (por si no tenés el campo directo)
private fun Evento.visitante() = this.equipoVisitante

// ═══════════════════════════════════════════════════════════════
// FONDO ANIMADO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun FondoDetalle() {
    val transition = rememberInfiniteTransition(label = "fondo")
    val fase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (2 * PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(20000, easing = LinearEasing)),
        label = "fase"
    )
    Box(Modifier.fillMaxSize()) {
        val x1 = sin(fase) * 80f
        val y1 = sin(fase * 0.8f) * 40f
        Box(
            Modifier
                .graphicsLayer { translationX = x1; translationY = y1 }
                .size(360.dp)
                .offset(x = (-120).dp, y = (-100).dp)
                .clip(CircleShape)
                .background(Brush.radialGradient(listOf(
                    AppColors.Gold.copy(alpha = 0.10f), Color.Transparent
                )))
        )
        val x2 = sin(fase * 1.3f + 1f) * 100f
        Box(
            Modifier
                .graphicsLayer { translationX = x2 }
                .size(420.dp)
                .offset(x = 150.dp, y = 400.dp)
                .clip(CircleShape)
                .background(Brush.radialGradient(listOf(
                    Color(0xFF7B5CFF).copy(alpha = 0.06f), Color.Transparent
                )))
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// HERO DRAMÁTICO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun HeroDramatico(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    color: Color, estado: EstadoEvento, minsHasta: Int?
) {
    val altura = if (esTV) 300.dp else if (esMovil) 240.dp else 280.dp

    Box(
        Modifier
            .fillMaxWidth()
            .fadeInOnLoad(450)
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF0D0D12))
            .border(
                1.dp,
                when {
                    estado == EstadoEvento.EN_VIVO -> Color(0xFFFF3B30).copy(alpha = 0.5f)
                    else -> AppColors.Gold.copy(alpha = 0.25f)
                },
                RoundedCornerShape(24.dp)
            )
            .height(altura)
    ) {
        // Imagen full-bleed
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.linearGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                ),
                contentAlignment = Alignment.Center
            ) {
                Text("⚽", fontSize = 100.sp, color = Color.White.copy(alpha = 0.15f))
            }
        }

        // Gradiente dramático: transparente arriba → negro abajo
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color(0xFF050505).copy(alpha = 0.3f),
                        Color(0xFF050505).copy(alpha = 0.85f),
                        Color(0xFF050505)
                    ),
                    startY = 0f
                )
            )
        )

        // Contenido inferior
        Column(
            Modifier.fillMaxSize().padding(if (esMovil) 18.dp else 26.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                when (estado) {
                    EstadoEvento.EN_VIVO -> LiveBadgeGrande()
                    EstadoEvento.FINALIZADO -> PillBadgeGrande("✓ FINALIZADO", Color.White.copy(alpha = 0.15f), Color.White)
                    EstadoEvento.PROXIMO -> {
                        if (minsHasta != null && minsHasta <= 60) CountdownBadgeGrande(minsHasta)
                        else PillBadgeGrande("🕐 PRÓXIMO", AppColors.Gold, Color.Black)
                    }
                }
                PillBadgeGrande(
                    "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                    Color.White.copy(alpha = 0.15f), Color.White
                )
            }
            Spacer(Modifier.height(14.dp))
            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = if (esTV) 38.sp else if (esMovil) 24.sp else 30.sp,
                fontWeight = FontWeight.Black,
                lineHeight = (if (esTV) 42.sp else if (esMovil) 28.sp else 34.sp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                letterSpacing = (-0.6).sp
            )
            Spacer(Modifier.height(10.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetaChip("🕐 ${evento.hora}", esMovil)
                DotSeparator()
                MetaChip("📅 ${evento.fecha}", esMovil)
                if (evento.liga.isNotBlank() && evento.liga != evento.groupTitle) {
                    DotSeparator()
                    MetaChip("🏆 ${evento.liga}", esMovil)
                }
            }
        }
    }
}

@Composable
private fun LiveBadgeGrande() {
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 900)
    Box(
        Modifier.alpha(pulse)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFF3B30), Color(0xFFFF6B5D))))
            .padding(horizontal = 14.dp, vertical = 6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(Color.White))
            Spacer(Modifier.width(6.dp))
            Text("EN VIVO", color = Color.White, fontSize = 12.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
    }
}

@Composable
private fun CountdownBadgeGrande(mins: Int) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFFA500), Color(0xFFFFC040))))
            .padding(horizontal = 14.dp, vertical = 6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⏰", fontSize = 12.sp)
            Spacer(Modifier.width(6.dp))
            Text("EN ${mins}MIN", color = Color.Black, fontSize = 12.sp,
                fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
        }
    }
}

@Composable
private fun PillBadgeGrande(texto: String, bg: Color, fg: Color) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp)).background(bg)
            .padding(horizontal = 12.dp, vertical = 5.dp)
    ) {
        Text(texto, color = fg, fontSize = 11.sp, fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp, maxLines = 1)
    }
}

@Composable
private fun MetaChip(texto: String, esMovil: Boolean) {
    Text(texto, color = Color.White.copy(alpha = 0.9f),
        fontSize = if (esMovil) 12.sp else 13.sp,
        fontWeight = FontWeight.Medium)
}

@Composable
private fun DotSeparator() {
    Box(Modifier.size(3.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.4f)))
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN EN VIVO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionEnVivo(
    evento: Evento, partido: PartidoEnVivo?, cargando: Boolean, error: String?,
    esTV: Boolean, esMovil: Boolean, statsExpandidas: Boolean,
    onToggleStats: () -> Unit
) {
    Column(Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 100)) {
        if (cargando && partido == null) {
            CargandoCard("Buscando datos en vivo...", esTV)
            return@Column
        }
        if (partido != null) {
            MarcadorBroadcast(partido, esTV, esMovil)
            if (partido.estadisticas != null && partido.enVivo) {
                Spacer(Modifier.height(14.dp))
                StatsCardPremium(
                    partido.estadisticas, esTV, esMovil,
                    expandidas = esTV || statsExpandidas,
                    colapsable = !esTV,
                    onToggle = onToggleStats
                )
            }
            if (partido.eventos.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                TimelinePremium(partido.eventos, partido.localNombre, partido.visitanteNombre, esTV, esMovil)
            }
        } else if (error != null) {
            InfoCard("ℹ️", error, esTV)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARCADOR BROADCAST
// ═══════════════════════════════════════════════════════════════

@Composable
private fun MarcadorBroadcast(partido: PartidoEnVivo, esTV: Boolean, esMovil: Boolean) {
    val liveColor = Color(0xFFFF3B30)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 900)

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(listOf(Color(0xFF15151C), Color(0xFF0A0A0F)))
            )
            .border(
                if (partido.enVivo) 2.dp else 1.dp,
                if (partido.enVivo) liveColor.copy(alpha = 0.5f) else AppColors.Gold.copy(alpha = 0.25f),
                RoundedCornerShape(20.dp)
            )
            .padding(if (esMovil) 18.dp else 24.dp)
    ) {
        // Header
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (partido.enVivo) {
                Box(
                    Modifier.alpha(pulse).clip(RoundedCornerShape(6.dp))
                        .background(liveColor)
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text("● LIVE", color = Color.White,
                        fontSize = if (esMovil) 10.sp else 11.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                }
                Spacer(Modifier.width(10.dp))
                Text("${partido.minuto}'",
                    color = AppColors.GoldBright,
                    fontSize = if (esMovil) 20.sp else 24.sp,
                    fontWeight = FontWeight.Black)
            } else if (partido.terminado) {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(AppColors.TextMuted.copy(alpha = 0.3f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text("FINALIZADO", color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 10.sp else 11.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(estadoHumano(partido.estadoCorto),
                color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 12.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.5.sp)
        }
        Spacer(Modifier.height(if (esMovil) 20.dp else 26.dp))

        // Marcador
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Local
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(if (esMovil) 64.dp else 80.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.radialGradient(listOf(
                                Color.White.copy(alpha = 0.1f),
                                Color.Transparent
                            ))
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    if (partido.localLogo.isNotBlank()) {
                        AsyncImage(
                            model = partido.localLogo, contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.size(if (esMovil) 52.dp else 68.dp)
                        )
                    } else {
                        Text("⚽", fontSize = if (esMovil) 32.sp else 40.sp)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Text(partido.localNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
            }

            // Score con glow
            Box(
                Modifier.padding(horizontal = if (esMovil) 8.dp else 16.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    if (partido.noEmpezado) "VS" else "${partido.golesLocal} - ${partido.golesVisitante}",
                    color = if (partido.enVivo) AppColors.GoldBright else Color.White,
                    fontSize = if (esMovil) 44.sp else 56.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 3.sp
                )
            }

            // Visitante
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(if (esMovil) 64.dp else 80.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.radialGradient(listOf(
                                Color.White.copy(alpha = 0.1f),
                                Color.Transparent
                            ))
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    if (partido.visitanteLogo.isNotBlank()) {
                        AsyncImage(
                            model = partido.visitanteLogo, contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.size(if (esMovil) 52.dp else 68.dp)
                        )
                    } else {
                        Text("⚽", fontSize = if (esMovil) 32.sp else 40.sp)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Text(partido.visitanteNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// STATS PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun StatsCardPremium(
    stats: EstadisticasPartido, esTV: Boolean, esMovil: Boolean,
    expandidas: Boolean, colapsable: Boolean, onToggle: () -> Unit
) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(listOf(Color(0xFF15151C), Color(0xFF0A0A0F)))
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(20.dp))
            .padding(if (esMovil) 16.dp else 20.dp)
    ) {
        Row(
            Modifier.fillMaxWidth()
                .then(if (colapsable) Modifier.clickable { onToggle() } else Modifier),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("📊", fontSize = if (esMovil) 16.sp else 18.sp)
            Spacer(Modifier.width(8.dp))
            Text("ESTADÍSTICAS", color = AppColors.GoldBright,
                fontSize = if (esMovil) 12.sp else 13.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            if (colapsable) {
                Spacer(Modifier.weight(1f))
                Text(if (expandidas) "▲" else "▼",
                    color = AppColors.TextSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
        AnimatedVisibility(expandidas, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            Column {
                Spacer(Modifier.height(16.dp))
                StatBarPremium("Posesión", stats.posesionLocal, stats.posesionVisitante, "%", esMovil)
                Spacer(Modifier.height(16.dp))
                StatBarPremium("Corners", stats.cornersLocal, stats.cornersVisitante, "", esMovil)
                Spacer(Modifier.height(16.dp))
                StatBarPremium("Tiros", stats.tirosLocal, stats.tirosVisitante, "", esMovil)
            }
        }
    }
}

@Composable
private fun StatBarPremium(label: String, local: Int, visitante: Int, sufijo: String, esMovil: Boolean) {
    val total = (local + visitante).coerceAtLeast(1)
    val fracLocal = local.toFloat() / total
    val animFrac by animateFloatAsState(fracLocal, tween(700, easing = FastOutSlowInEasing), label = "statBar")

    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("$local$sufijo", color = AppColors.GoldBright,
                fontSize = if (esMovil) 16.sp else 18.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            Text(label, color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 12.sp,
                fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp)
            Spacer(Modifier.weight(1f))
            Text("$visitante$sufijo", color = AppColors.GoldBright,
                fontSize = if (esMovil) 16.sp else 18.sp, fontWeight = FontWeight.Black)
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp))
                .background(Color(0xFF1A1A22))
        ) {
            Box(
                Modifier.fillMaxHeight().fillMaxWidth(animFrac)
                    .background(
                        Brush.horizontalGradient(listOf(AppColors.Gold, AppColors.GoldBright))
                    )
            )
            Box(Modifier.fillMaxHeight().weight(1f).background(Color(0xFF2A2A33)))
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// TIMELINE PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun TimelinePremium(
    eventos: List<EventoPartido>,
    localNombre: String, visitanteNombre: String,
    esTV: Boolean, esMovil: Boolean
) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(listOf(Color(0xFF15151C), Color(0xFF0A0A0F)))
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(20.dp))
            .padding(if (esMovil) 16.dp else 20.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚡", fontSize = if (esMovil) 16.sp else 18.sp)
            Spacer(Modifier.width(8.dp))
            Text("EVENTOS DEL PARTIDO", color = AppColors.GoldBright,
                fontSize = if (esMovil) 12.sp else 13.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(16.dp))

        val eventosOrdenados = eventos.sortedByDescending { it.minuto }
        eventosOrdenados.forEachIndexed { idx, ev ->
            val color = colorEvento(ev.tipo, ev.detalle)
            val esLocal = ev.equipo.equals(localNombre, ignoreCase = true) ||
                    localNombre.contains(ev.equipo, ignoreCase = true) ||
                    ev.equipo.contains(localNombre, ignoreCase = true)

            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                // Minuto
                Box(
                    Modifier.width(if (esMovil) 38.dp else 44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(color.copy(alpha = 0.18f))
                        .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                        .padding(vertical = 5.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("${ev.minuto}'", color = color,
                        fontSize = if (esMovil) 11.sp else 12.sp,
                        fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.width(10.dp))

                // Columna con línea vertical + dot + info
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier.size(if (esMovil) 26.dp else 30.dp)
                                .clip(CircleShape)
                                .background(color.copy(alpha = 0.2f))
                                .border(1.dp, color.copy(alpha = 0.6f), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(emojiEvento(ev.tipo, ev.detalle),
                                fontSize = if (esMovil) 12.sp else 14.sp)
                        }
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                ev.jugador.ifBlank { ev.detalle },
                                color = Color.White,
                                fontSize = if (esMovil) 13.sp else 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1, overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                "${if (esLocal) "🏠" else "✈️"} ${ev.equipo}",
                                color = AppColors.TextSecondary,
                                fontSize = if (esMovil) 10.sp else 11.sp,
                                maxLines = 1, overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                    // Línea vertical conectora (excepto último)
                    if (idx < eventosOrdenados.size - 1) {
                        Box(
                            Modifier
                                .padding(start = if (esMovil) 12.dp else 14.dp, top = 2.dp)
                                .width(1.dp)
                                .height(if (esMovil) 14.dp else 16.dp)
                                .background(Color.White.copy(alpha = 0.08f))
                        )
                    } else {
                        Spacer(Modifier.height(4.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun CargandoCard(mensaje: String, esTV: Boolean) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(16.dp))
            .padding(20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CircularProgressIndicator(color = AppColors.Gold, strokeWidth = 2.dp,
            modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Text(mensaje, color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun InfoCard(emoji: String, mensaje: String, esTV: Boolean) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.TextMuted.copy(alpha = 0.3f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(emoji, fontSize = 18.sp)
        Spacer(Modifier.width(10.dp))
        Text(mensaje, color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN FINALIZADO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionFinalizado(evento: Evento, esTV: Boolean, esMovil: Boolean) {
    Box(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.TextMuted.copy(alpha = 0.25f), RoundedCornerShape(24.dp))
            .height(if (esMovil) 240.dp else 320.dp)
    ) {
        if (evento.videoFinalizado.isNotBlank()) {
            VideoLoopPlayer(evento.videoFinalizado, Modifier.fillMaxSize())
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(listOf(
                        Color.Transparent,
                        Color(0xFF050505).copy(alpha = 0.5f),
                        Color(0xFF050505).copy(alpha = 0.95f)
                    ))
                )
            )
            Column(
                Modifier.fillMaxSize().padding(if (esMovil) 20.dp else 26.dp),
                verticalArrangement = Arrangement.Bottom
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(if (esMovil) 34.dp else 40.dp).clip(CircleShape)
                            .background(AppColors.TextMuted.copy(alpha = 0.3f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("✓", color = Color.White, fontSize = if (esMovil) 18.sp else 22.sp,
                            fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.width(12.dp))
                    Text("Evento Finalizado", color = Color.White,
                        fontSize = if (esMovil) 18.sp else 22.sp,
                        fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "El partido ya terminó. Gracias por ver FutTV.",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esMovil) 12.sp else 14.sp,
                    lineHeight = if (esMovil) 16.sp else 18.sp
                )
            }
        } else {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                ),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.size(if (esMovil) 60.dp else 72.dp).clip(CircleShape)
                            .background(AppColors.TextMuted.copy(alpha = 0.2f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("✓", fontSize = if (esMovil) 32.sp else 40.sp,
                            color = AppColors.TextSecondary, fontWeight = FontWeight.Black)
                    }
                    Spacer(Modifier.height(14.dp))
                    Text("Evento Finalizado", color = Color.White,
                        fontSize = if (esMovil) 18.sp else 22.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(6.dp))
                    Text("Gracias por ver FutTV", color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 12.sp else 14.sp)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN PRÓXIMO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionProximo(evento: Evento, esTV: Boolean, esMovil: Boolean, minsHasta: Int?) {
    val horas = minsHasta?.let { it / 60 }
    val mins = minsHasta?.let { it % 60 }
    val cuentaTexto = when {
        minsHasta == null -> "Programado"
        horas != null && horas > 0 -> "Empieza en ${horas}h ${mins}min"
        else -> "Empieza en ${mins}min"
    }

    Box(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.3f), RoundedCornerShape(24.dp))
            .height(if (esMovil) 240.dp else 320.dp)
    ) {
        if (evento.videoProximo.isNotBlank()) {
            VideoLoopPlayer(evento.videoProximo, Modifier.fillMaxSize())
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(listOf(
                        Color.Transparent,
                        Color(0xFF050505).copy(alpha = 0.5f),
                        Color(0xFF050505).copy(alpha = 0.95f)
                    ))
                )
            )
            Column(
                Modifier.fillMaxSize().padding(if (esMovil) 20.dp else 26.dp),
                verticalArrangement = Arrangement.Bottom
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("⏰", fontSize = if (esMovil) 18.sp else 22.sp)
                    Spacer(Modifier.width(8.dp))
                    Text(cuentaTexto, color = AppColors.GoldBright,
                        fontSize = if (esMovil) 16.sp else 20.sp,
                        fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "El evento todavía no comenzó. Los canales estarán disponibles cuando empiece.",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esMovil) 12.sp else 14.sp,
                    lineHeight = if (esMovil) 16.sp else 18.sp
                )
            }
        } else {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                ),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.size(if (esMovil) 60.dp else 72.dp).clip(CircleShape)
                            .background(AppColors.Gold.copy(alpha = 0.15f))
                            .border(1.dp, AppColors.Gold.copy(alpha = 0.4f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("⏰", fontSize = if (esMovil) 32.sp else 40.sp)
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(cuentaTexto, color = AppColors.GoldBright,
                        fontSize = if (esMovil) 18.sp else 22.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(8.dp))
                    Text("Los canales aparecerán cuando empiece",
                        color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 12.sp else 14.sp)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// CANALES PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun RowCanalesPremium(evento: Evento, esTV: Boolean, esMovil: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp).fadeInOnLoad(450, delayMs = 100),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.width(4.dp).height(if (esMovil) 22.dp else 28.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(AppColors.GoldBright)
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                if (esMovil) "Canales disponibles" else "Canales disponibles para ver",
                color = Color.White,
                fontSize = if (esMovil) 17.sp else 20.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = (-0.3).sp
            )
            Text(
                "${evento.embeds.size} ${if (evento.embeds.size == 1) "opción" else "opciones"}",
                color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 12.sp
            )
        }
    }
}

@Composable
private fun CanalCardPremium(
    embed: Embed, indice: Int, esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.02f else 1f, tween(200), label = "canalScale")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f),
        tween(180), label = "canalBorder"
    )
    val bgColor by animateColorAsState(
        if (focused) Color(0xFF1A1A22) else Color(0xFF0D0D12),
        tween(180), label = "canalBg"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(18.dp))
            .background(bgColor)
            .border(if (focused) 2.dp else 1.dp, borderColor, RoundedCornerShape(18.dp))
            .padding(
                horizontal = if (esMovil) 14.dp else 20.dp,
                vertical = if (esMovil) 14.dp else 16.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Número de canal + ícono play
        Box(
            Modifier.size(if (esMovil) 48.dp else 58.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(
                    Brush.linearGradient(
                        if (focused) listOf(AppColors.GoldBright, AppColors.Gold)
                        else listOf(AppColors.Gold.copy(alpha = 0.9f), AppColors.Gold.copy(alpha = 0.6f))
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "$indice",
                    color = Color.Black,
                    fontSize = if (esMovil) 18.sp else 22.sp,
                    fontWeight = FontWeight.Black
                )
                Text(
                    "▶",
                    color = Color.Black.copy(alpha = 0.7f),
                    fontSize = if (esMovil) 10.sp else 11.sp,
                    fontWeight = FontWeight.Black
                )
            }
        }
        Spacer(Modifier.width(if (esMovil) 14.dp else 18.dp))

        Column(Modifier.weight(1f)) {
            Text(
                embed.nombre,
                color = Color.White,
                fontSize = if (esMovil) 15.sp else 17.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            if (esTV) {
                Spacer(Modifier.height(3.dp))
                Text(
                    if (focused) "Presioná OK para reproducir" else "OK para reproducir",
                    color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                    fontSize = 11.sp,
                    fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }

        // Flecha o ícono de acción
        Box(
            Modifier.size(if (esMovil) 34.dp else 38.dp)
                .clip(CircleShape)
                .background(
                    if (focused) AppColors.GoldBright
                    else Color.White.copy(alpha = 0.08f)
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                if (focused) "▶" else "→",
                color = if (focused) Color.Black else AppColors.TextMuted,
                fontSize = if (esMovil) 14.sp else 16.sp,
                fontWeight = FontWeight.Black
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN VOLVER
// ═══════════════════════════════════════════════════════════════

@Composable
private fun BotonVolver(onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.05f else 1f, tween(180), label = "volverScale")
    Row(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(
                if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.08f)
            )
            .border(
                1.dp,
                if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.15f),
                RoundedCornerShape(14.dp)
            )
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else AppColors.GoldBright,
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else AppColors.GoldBright,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.3.sp
        )
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ Detail v4 Premium completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
