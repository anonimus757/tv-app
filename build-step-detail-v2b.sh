#!/bin/bash
set -e

DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.v2.$(date +%s)"
echo "✅ Backup: ${DETAIL}.bak.v2.$(date +%s)"

cat > "$DETAIL" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.ApiSportsRepository
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.EstadisticasPartido
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.EventoPartido
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.data.PartidoEnVivo
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.ui.animations.AnimatedGoldBackground
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.rememberEsTV
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

private fun estadoHumano(corto: String): String = when (corto) {
    "NS" -> "PRÓXIMO"
    "1H" -> "1er TIEMPO"
    "HT" -> "DESCANSO"
    "2H" -> "2do TIEMPO"
    "ET" -> "PRÓRROGA"
    "BT" -> "DESCANSO (PRÓRROGA)"
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

// ═══════════════════════════════════════════════════════════════
// EVENT DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════

@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    BackHandler { onBack() }

    val esTV = rememberEsTV()
    val config by RemoteConfigRepository.config.collectAsState()
    val color = AppColors.fuenteColor(evento.groupTitle)
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // ─── Estado del partido en vivo ───
    var partido by remember { mutableStateOf<PartidoEnVivo?>(null) }
    var cargandoPartido by remember { mutableStateOf(false) }
    var errorPartido by remember { mutableStateOf<String?>(null) }
    var statsExpandidas by remember { mutableStateOf(false) }
    var canalesIndex by remember { mutableStateOf(2) } // índice del item "canales"

    // ─── Cargar datos del partido (una sola vez al abrir) ───
    LaunchedEffect(evento.descripcion, evento.fecha) {
        val tieneEquipos = evento.equipoLocal.isNotBlank() && evento.equipoVisitante.isNotBlank()
        if (!tieneEquipos) {
            errorPartido = null
            return@LaunchedEffect
        }
        if (!ApiSportsRepository.tieneApiKey()) {
            errorPartido = "Configurá la API key en Firestore"
            return@LaunchedEffect
        }

        cargandoPartido = true
        errorPartido = null
        try {
            val fixtureId = evento.fixtureId ?: ApiSportsRepository.resolverFixtureId(
                equipoLocal = evento.equipoLocal,
                equipoVisitante = evento.equipoVisitante,
                fechaYYYYMMDD = evento.fecha
            )
            if (fixtureId != null) {
                partido = ApiSportsRepository.obtenerPartidoEnVivo(fixtureId)
                if (partido == null) errorPartido = "Sin datos del partido"
            } else {
                errorPartido = "No se encontró el partido en la API"
            }
        } catch (e: Exception) {
            errorPartido = e.message ?: "Error consultando la API"
        }
        cargandoPartido = false
    }

    // ─── Polling cada 60s si está en vivo ───
    LaunchedEffect(partido?.fixtureId) {
        val id = partido?.fixtureId ?: return@LaunchedEffect
        while (true) {
            delay(60_000)
            val actual = partido
            if (actual?.enVivo != true) continue
            val nuevo = ApiSportsRepository.obtenerPartidoEnVivo(id, forzarRefresh = true)
            if (nuevo != null) partido = nuevo
        }
    }

    // ─── Actualizar índice de canales según si hay sección API ───
    LaunchedEffect(partido, cargandoPartido, errorPartido) {
        canalesIndex = if (cargandoPartido || partido != null || errorPartido != null) 3 else 2
    }

    // ─── Tamaños adaptativos ───
    val paddingH = if (esTV) 48.dp else 16.dp
    val paddingV = if (esTV) 32.dp else 16.dp
    val tituloSize = if (esTV) 32.sp else 22.sp
    val subtituloSize = if (esTV) 14.sp else 12.sp

    Box(Modifier.fillMaxSize()) {
        AnimatedGoldBackground()

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = paddingH, end = paddingH,
                top = paddingV, bottom = 48.dp
            ),
            verticalArrangement = Arrangement.spacedBy(if (esTV) 20.dp else 14.dp)
        ) {
            // ─── Botón Volver ───
            item(key = "volver") {
                Box(Modifier.fadeInOnLoad(350)) {
                    BotonVolverDetalle(onBack, esTV)
                }
            }

            // ─── Hero del evento ───
            item(key = "hero") {
                HeroEvento(evento, esTV, color, onVerCanales = {
                    scope.launch { listState.animateScrollToItem(canalesIndex) }
                })
            }

            // ─── Sección API-Sports ───
            item(key = "api") {
                SeccionPartido(
                    evento = evento,
                    partido = partido,
                    cargando = cargandoPartido,
                    error = errorPartido,
                    esTV = esTV,
                    statsExpandidas = statsExpandidas,
                    onToggleStats = { statsExpandidas = !statsExpandidas }
                )
            }

            // ─── Header canales ───
            item(key = "head_canales") {
                Row(
                    Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 100),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = AppIcons.canales,
                        contentDescription = null,
                        tint = AppColors.GoldBright,
                        modifier = Modifier.size(if (esTV) 22.dp else 18.dp)
                    )
                    Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
                    Text(
                        if (esTV) "Elige un canal para reproducir" else "Elegí un canal",
                        color = AppColors.TextPrimary,
                        fontSize = if (esTV) 22.sp else 16.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.width(if (esTV) 12.dp else 8.dp))
                    Box(
                        Modifier.clip(RoundedCornerShape(10.dp))
                            .background(AppColors.Gold.copy(alpha = 0.2f))
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                    ) {
                        Text(
                            "${evento.embeds.size}",
                            color = AppColors.Gold,
                            fontSize = if (esTV) 12.sp else 11.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            // ─── Lista canales ───
            itemsIndexed(
                items = evento.embeds,
                key = { idx, it -> "emb_${idx}_${it.url}" }
            ) { index, embed ->
                Box(Modifier.fadeInOnLoad(400, delayMs = 150 + index * 50, slideFromDp = 16f)) {
                    CanalCardPro(embed = embed, esTV = esTV, onClick = { onCanalClick(embed) })
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// HERO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun HeroEvento(
    evento: Evento,
    esTV: Boolean,
    color: Color,
    onVerCanales: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val borderWidth by animateDpAsState(if (focused) 2.dp else 1.dp, tween(180), label = "hbw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
        tween(180), label = "hbc"
    )

    val imgSize = if (esTV) 140.dp else 96.dp
    val imgInner = if (esTV) 100.dp else 68.dp
    val tituloSize = if (esTV) 32.sp else 22.sp

    Row(
        Modifier
            .fillMaxWidth()
            .fadeInOnLoad(450)
            .scaleOnFocus(focused, 1.005f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface)))
            .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
            .padding(if (esTV) 24.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(imgSize).clip(RoundedCornerShape(if (esTV) 16.dp else 12.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (evento.imagen.isNotBlank()) {
                AsyncImage(
                    model = evento.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(imgInner)
                )
            } else {
                Text("⚽", fontSize = if (esTV) 60.sp else 42.sp)
            }
        }
        Spacer(Modifier.width(if (esTV) 24.dp else 14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                evento.descripcion,
                color = AppColors.TextPrimary,
                fontSize = tituloSize,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = (tituloSize.value + 6).sp,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(if (esTV) 10.dp else 6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.2f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                        color = color,
                        fontSize = if (esTV) 13.sp else 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1
                    )
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    FechaHelper.badgeCard(evento.fecha, evento.hora),
                    color = AppColors.GoldBright,
                    fontSize = if (esTV) 14.sp else 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            if (evento.liga.isNotBlank() && evento.liga != evento.groupTitle) {
                Spacer(Modifier.height(4.dp))
                Text(
                    "🏆 ${evento.liga}",
                    color = AppColors.TextSecondary,
                    fontSize = if (esTV) 13.sp else 11.sp
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN PARTIDO EN VIVO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionPartido(
    evento: Evento,
    partido: PartidoEnVivo?,
    cargando: Boolean,
    error: String?,
    esTV: Boolean,
    statsExpandidas: Boolean,
    onToggleStats: () -> Unit
) {
    val tieneEquipos = evento.equipoLocal.isNotBlank() && evento.equipoVisitante.isNotBlank()
    if (!tieneEquipos && !cargando && partido == null && error == null) return

    Column(
        Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 200)
    ) {
        // ─── Cargando ───
        if (cargando) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                    .background(AppColors.Card)
                    .border(1.dp, AppColors.Gold.copy(alpha = 0.3f), RoundedCornerShape(14.dp))
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(
                    color = AppColors.Gold,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(if (esTV) 28.dp else 22.dp)
                )
                Spacer(Modifier.width(14.dp))
                Text(
                    "Buscando datos en vivo...",
                    color = AppColors.TextSecondary,
                    fontSize = if (esTV) 15.sp else 13.sp
                )
            }
            return@Column
        }

        // ─── Error ───
        if (error != null && partido == null) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                    .background(AppColors.Card)
                    .border(1.dp, AppColors.TextMuted.copy(alpha = 0.3f), RoundedCornerShape(14.dp))
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("ℹ️", fontSize = if (esTV) 22.sp else 18.sp)
                Spacer(Modifier.width(10.dp))
                Text(
                    error,
                    color = AppColors.TextSecondary,
                    fontSize = if (esTV) 14.sp else 12.sp
                )
            }
            return@Column
        }

        // ─── Partido cargado ───
        if (partido != null) {
            MarcadorCard(partido, esTV, evento.hora)

            if (partido.estadisticas != null && partido.enVivo) {
                Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
                EstadisticasCard(
                    stats = partido.estadisticas,
                    esTV = esTV,
                    expandidas = esTV || statsExpandidas,
                    colapsable = !esTV,
                    onToggle = onToggleStats
                )
            }

            if (partido.eventos.isNotEmpty()) {
                Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
                EventosCard(partido.eventos, esTV)
            }
        }
    }
}

@Composable
private fun MarcadorCard(partido: PartidoEnVivo, esTV: Boolean, horaFallback: String) {
    val liveColor = Color(0xFFFF3B30)
    val pulse = rememberPulseAlpha(min = 0.4f, max = 1f, durationMs = 900)

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface)))
            .border(
                if (partido.enVivo) 2.dp else 1.dp,
                if (partido.enVivo) liveColor.copy(alpha = 0.7f) else AppColors.Gold.copy(alpha = 0.4f),
                RoundedCornerShape(16.dp)
            )
            .padding(if (esTV) 22.dp else 14.dp)
    ) {
        // Header: estado + minuto
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (partido.enVivo) {
                Box(
                    Modifier.alpha(pulse).clip(RoundedCornerShape(6.dp))
                        .background(liveColor)
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        "● EN VIVO",
                        color = Color.White,
                        fontSize = if (esTV) 12.sp else 10.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    "${partido.minuto}'",
                    color = AppColors.GoldBright,
                    fontSize = if (esTV) 22.sp else 16.sp,
                    fontWeight = FontWeight.Black
                )
            } else if (partido.terminado) {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(AppColors.TextMuted.copy(alpha = 0.3f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        "FINALIZADO",
                        color = AppColors.TextSecondary,
                        fontSize = if (esTV) 12.sp else 10.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp
                    )
                }
            } else {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(AppColors.Gold.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        "🕐 $horaFallback",
                        color = AppColors.Gold,
                        fontSize = if (esTV) 12.sp else 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                estadoHumano(partido.estadoCorto),
                color = AppColors.TextSecondary,
                fontSize = if (esTV) 13.sp else 11.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
        Spacer(Modifier.height(if (esTV) 20.dp else 14.dp))

        // Marcador grande
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Local
            Column(
                Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (partido.localLogo.isNotBlank()) {
                    AsyncImage(
                        model = partido.localLogo, contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(if (esTV) 64.dp else 44.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    partido.localNombre,
                    color = AppColors.TextPrimary,
                    fontSize = if (esTV) 16.sp else 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // Score
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    if (partido.noEmpezado) "vs" else "${partido.golesLocal} - ${partido.golesVisitante}",
                    color = if (partido.enVivo) AppColors.GoldBright else AppColors.TextPrimary,
                    fontSize = if (esTV) 48.sp else 34.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 2.sp
                )
            }

            // Visitante
            Column(
                Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (partido.visitanteLogo.isNotBlank()) {
                    AsyncImage(
                        model = partido.visitanteLogo, contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(if (esTV) 64.dp else 44.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    partido.visitanteNombre,
                    color = AppColors.TextPrimary,
                    fontSize = if (esTV) 16.sp else 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun EstadisticasCard(
    stats: EstadisticasPartido,
    esTV: Boolean,
    expandidas: Boolean,
    colapsable: Boolean,
    onToggle: () -> Unit
) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(AppColors.Card)
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(14.dp))
            .padding(if (esTV) 18.dp else 12.dp)
    ) {
        // Header
        Row(
            Modifier.fillMaxWidth()
                .then(if (colapsable) Modifier.clickable { onToggle() } else Modifier),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("📊", fontSize = if (esTV) 18.sp else 15.sp)
            Spacer(Modifier.width(8.dp))
            Text(
                "ESTADÍSTICAS",
                color = AppColors.GoldBright,
                fontSize = if (esTV) 14.sp else 12.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )
            if (colapsable) {
                Spacer(Modifier.weight(1f))
                Text(
                    if (expandidas) "▲" else "▼",
                    color = AppColors.TextSecondary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        AnimatedVisibility(
            visible = expandidas,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Column {
                Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
                StatRow("Posesión", "${stats.posesionLocal}%", "${stats.posesionVisitante}%", esTV)
                Spacer(Modifier.height(8.dp))
                StatRow("Corners", "${stats.cornersLocal}", "${stats.cornersVisitante}", esTV)
                Spacer(Modifier.height(8.dp))
                StatRow("Tiros", "${stats.tirosLocal}", "${stats.tirosVisitante}", esTV)
            }
        }
    }
}

@Composable
private fun StatRow(label: String, valorLocal: String, valorVisitante: String, esTV: Boolean) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            valorLocal,
            color = AppColors.GoldBright,
            fontSize = if (esTV) 15.sp else 13.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(if (esTV) 50.dp else 42.dp),
            textAlign = TextAlign.Start
        )
        Text(
            label,
            color = AppColors.TextSecondary,
            fontSize = if (esTV) 13.sp else 11.sp,
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.Center
        )
        Text(
            valorVisitante,
            color = AppColors.GoldBright,
            fontSize = if (esTV) 15.sp else 13.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(if (esTV) 50.dp else 42.dp),
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun EventosCard(eventos: List<EventoPartido>, esTV: Boolean) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(AppColors.Card)
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(14.dp))
            .padding(if (esTV) 18.dp else 12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚡", fontSize = if (esTV) 18.sp else 15.sp)
            Spacer(Modifier.width(8.dp))
            Text(
                "EVENTOS DEL PARTIDO",
                color = AppColors.GoldBright,
                fontSize = if (esTV) 14.sp else 12.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )
        }
        Spacer(Modifier.height(if (esTV) 12.dp else 10.dp))
        eventos.sortedByDescending { it.minuto }.forEach { ev ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = if (esTV) 4.dp else 3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "${ev.minuto}'",
                    color = AppColors.GoldBright,
                    fontSize = if (esTV) 13.sp else 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.width(if (esTV) 40.dp else 32.dp)
                )
                Text(
                    emojiEvento(ev.tipo, ev.detalle),
                    fontSize = if (esTV) 15.sp else 13.sp
                )
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        ev.jugador.ifBlank { ev.detalle },
                        color = AppColors.TextPrimary,
                        fontSize = if (esTV) 14.sp else 12.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        ev.equipo,
                        color = AppColors.TextSecondary,
                        fontSize = if (esTV) 12.sp else 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// CARD CANAL
// ═══════════════════════════════════════════════════════════════

@Composable
private fun CanalCardPro(embed: Embed, esTV: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    val borderWidth by animateDpAsState(if (focused) 2.dp else 1.dp, tween(180), label = "cbw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.2f),
        tween(180), label = "cbc"
    )
    val bgColor by animateColorAsState(
        if (focused) AppColors.CardFocus else AppColors.Card,
        tween(180), label = "cbg"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(focused, if (esTV) 1.02f else 1.01f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 14.dp else 12.dp))
            .background(bgColor)
            .border(borderWidth, borderColor, RoundedCornerShape(if (esTV) 14.dp else 12.dp))
            .padding(
                horizontal = if (esTV) 24.dp else 14.dp,
                vertical = if (esTV) 20.dp else 14.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(if (esTV) 50.dp else 42.dp).clip(CircleShape)
                .background(if (focused) AppColors.GoldBright else AppColors.Gold),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color.Black,
                modifier = Modifier.size(if (esTV) 26.dp else 20.dp)
            )
        }
        Spacer(Modifier.width(if (esTV) 20.dp else 14.dp))
        Text(
            embed.nombre,
            color = AppColors.TextPrimary,
            fontSize = if (esTV) 20.sp else 15.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        if (esTV) {
            Text(
                if (focused) "Reproducir" else "OK para reproducir",
                color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                fontSize = if (esTV) 14.sp else 12.sp,
                fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
            )
        } else {
            Icon(
                imageVector = if (focused) AppIcons.play else AppIcons.adelante,
                contentDescription = null,
                tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN VOLVER
// ═══════════════════════════════════════════════════════════════

@Composable
private fun BotonVolverDetalle(onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(if (esTV) 10.dp else 8.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(
                if (esTV) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(if (esTV) 10.dp else 8.dp)
            )
            .clickable { onClick() }
            .padding(
                horizontal = if (esTV) 16.dp else 12.dp,
                vertical = if (esTV) 10.dp else 8.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(if (esTV) 20.dp else 16.dp)
        )
        Spacer(Modifier.width(if (esTV) 8.dp else 6.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else AppColors.Gold,
            fontSize = if (esTV) 14.sp else 13.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ EventDetailScreen v2 completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
