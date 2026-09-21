#!/bin/bash
set -e

echo "🔧 Aplicando EventDetail v3 Premium..."

# ═══════════════════════════════════════════════════════════
# 1. MODELS.KT: agregar campos
# ═══════════════════════════════════════════════════════════
MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
cp "$MODELS" "${MODELS}.bak.v3.$(date +%s)"
echo "✅ Backup Models.kt"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

viejo = '''    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null
)'''

nuevo = '''    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null,

    // ═══ Duración y videos en bucle ═══
    val duracionMinutos: Int = 150,        // Cuánto dura el evento (default 2.5h)
    val videoFinalizado: String = "",      // URL MP4 en bucle al finalizar
    val videoProximo: String = ""          // URL MP4 en bucle antes de empezar
)'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ Models.kt actualizado")
else:
    print("⚠️ Models.kt no matcheó. Ya puede estar actualizado.")
PYEOF

# ═══════════════════════════════════════════════════════════
# 2. EVENTREPOSITORY.KT: parsear nuevos campos
# ═══════════════════════════════════════════════════════════
REPO="app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
cp "$REPO" "${REPO}.bak.v3.$(date +%s)"
echo "✅ Backup EventRepository.kt"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Agregar lectura de los 3 campos nuevos
viejo = '''            val liga = doc.getString("liga")?.trim()?.takeIf { it.isNotBlank() } ?: categoria
            val fixtureId = doc.getLong("fixture_id")?.toInt()'''

nuevo = '''            val liga = doc.getString("liga")?.trim()?.takeIf { it.isNotBlank() } ?: categoria
            val fixtureId = doc.getLong("fixture_id")?.toInt()
            val duracionMinutos = doc.getLong("duracion_minutos")?.toInt() ?: 150
            val videoFinalizado = doc.getString("video_finalizado")?.trim() ?: ""
            val videoProximo = doc.getString("video_proximo")?.trim() ?: ""'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ EventRepository: lectura de campos agregada")
else:
    print("⚠️ No matcheó la lectura. Probando variante...")
    # Variante: si no tiene la línea exacta
    if 'val fixtureId = doc.getLong("fixture_id")?.toInt()' in c:
        c = c.replace(
            'val fixtureId = doc.getLong("fixture_id")?.toInt()',
            '''val fixtureId = doc.getLong("fixture_id")?.toInt()
            val duracionMinutos = doc.getLong("duracion_minutos")?.toInt() ?: 150
            val videoFinalizado = doc.getString("video_finalizado")?.trim() ?: ""
            val videoProximo = doc.getString("video_proximo")?.trim() ?: ""''',
            1
        )
        print("✅ Variante aplicada")

# Actualizar constructor Evento
viejo_ev = '''                equipoLocal = equipoLocal,
                equipoVisitante = equipoVisitante,
                liga = liga,
                fixtureId = fixtureId
            )'''

nuevo_ev = '''                equipoLocal = equipoLocal,
                equipoVisitante = equipoVisitante,
                liga = liga,
                fixtureId = fixtureId,
                duracionMinutos = duracionMinutos,
                videoFinalizado = videoFinalizado,
                videoProximo = videoProximo
            )'''

if viejo_ev in c:
    c = c.replace(viejo_ev, nuevo_ev, 1)
    print("✅ Constructor Evento actualizado")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3. EVENTDETAILSCREEN.KT: rediseño completo v3
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
cp "$DETAIL" "${DETAIL}.bak.v3.$(date +%s)"
echo "✅ Backup EventDetailScreen.kt"

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
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.data.PartidoEnVivo
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.rememberEsTV
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

// ═══════════════════════════════════════════════════════════════
// ESTADO DEL EVENTO
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
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    val estado = remember(evento) { calcularEstado(evento) }

    var partido by remember { mutableStateOf<PartidoEnVivo?>(null) }
    var cargandoPartido by remember { mutableStateOf(false) }
    var errorPartido by remember { mutableStateOf<String?>(null) }
    var statsExpandidas by remember { mutableStateOf(false) }

    // ─── Cargar API solo si EN VIVO ───
    LaunchedEffect(evento.descripcion, evento.fecha, estado) {
        if (estado != EstadoEvento.EN_VIVO) return@LaunchedEffect
        val tieneEquipos = evento.equipoLocal.isNotBlank() && evento.equipoVisitante.isNotBlank()
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

    // ─── Polling 60s si está en vivo ───
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
            state = listState,
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

            // Hero del evento
            item(key = "hero") {
                HeroEvento(evento, esTV, esMovil, color, estado, minutosHasta(evento))
            }

            // Sección según estado
            when (estado) {
                EstadoEvento.EN_VIVO -> {
                    item(key = "api") {
                        SeccionEnVivo(evento, partido, cargandoPartido, errorPartido, esTV, esMovil, statsExpandidas) {
                            statsExpandidas = !statsExpandidas
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

            // Canales
            item(key = "head_canales") {
                RowCanales(evento, esTV, esMovil)
            }
            itemsIndexed(
                items = evento.embeds,
                key = { idx, it -> "emb_${idx}_${it.url}" }
            ) { index, embed ->
                Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                    CanalCard(embed, esTV, esMovil) { onCanalClick(embed) }
                }
            }

            item(key = "footer") { Spacer(Modifier.height(30.dp)) }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// FONDO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun FondoDetalle() {
    val transition = rememberInfiniteTransition(label = "fondo")
    val fase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (2 * kotlin.math.PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(18000, easing = LinearEasing)),
        label = "fase"
    )
    Box(Modifier.fillMaxSize()) {
        val x = kotlin.math.sin(fase) * 60f
        Box(
            Modifier
                .size(320.dp)
                .offset(x = x.dp, y = (-80).dp)
                .clip(CircleShape)
                .background(Brush.radialGradient(listOf(
                    AppColors.Gold.copy(alpha = 0.10f), Color.Transparent
                )))
        )
        val x2 = kotlin.math.sin(fase * 1.2f + 1f) * 80f
        Box(
            Modifier
                .size(380.dp)
                .offset(x = x2.dp, y = 400.dp)
                .clip(CircleShape)
                .background(Brush.radialGradient(listOf(
                    AppColors.Gold.copy(alpha = 0.07f), Color.Transparent
                )))
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// HERO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun HeroEvento(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    color: Color, estado: EstadoEvento, minsHasta: Int?
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.005f else 1f, tween(220), label = "heroScale")
    val altura = if (esTV) 260.dp else if (esMovil) 200.dp else 230.dp

    Box(
        Modifier
            .fillMaxWidth()
            .fadeInOnLoad(450)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF0D0D12))
            .border(
                if (focused) 2.dp else 1.dp,
                when {
                    estado == EstadoEvento.EN_VIVO -> Color(0xFFFF3B30).copy(alpha = 0.6f)
                    focused -> AppColors.GoldBright
                    else -> AppColors.Gold.copy(alpha = 0.25f)
                },
                RoundedCornerShape(24.dp)
            )
            .height(altura)
    ) {
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen, contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(listOf(
                    Color.Transparent,
                    Color(0xFF050505).copy(alpha = 0.6f),
                    Color(0xFF050505).copy(alpha = 0.98f)
                ))
            )
        )
        Column(
            Modifier.fillMaxSize().padding(if (esMovil) 18.dp else 26.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (estado) {
                    EstadoEvento.EN_VIVO -> LiveBadgeDetalle()
                    EstadoEvento.FINALIZADO -> PillBadge("✓ FINALIZADO", AppColors.TextMuted.copy(alpha = 0.4f), Color.White)
                    EstadoEvento.PROXIMO -> {
                        if (minsHasta != null && minsHasta <= 60) CountdownBadgeDetalle(minsHasta)
                        else PillBadge("🕐 PRÓXIMO", AppColors.Gold, Color.Black)
                    }
                }
                PillBadge(
                    "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                    Color.White.copy(alpha = 0.15f), Color.White
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = if (esTV) 34.sp else if (esMovil) 22.sp else 28.sp,
                fontWeight = FontWeight.Black,
                lineHeight = (if (esTV) 38.sp else if (esMovil) 26.sp else 32.sp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                letterSpacing = (-0.4).sp
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("🕐 ${evento.hora}", color = Color.White.copy(alpha = 0.95f),
                    fontSize = if (esMovil) 12.sp else 13.sp, fontWeight = FontWeight.Medium)
                Text("📅 ${evento.fecha}", color = Color.White.copy(alpha = 0.95f),
                    fontSize = if (esMovil) 12.sp else 13.sp, fontWeight = FontWeight.Medium)
                if (evento.liga.isNotBlank() && evento.liga != evento.groupTitle) {
                    Text("🏆 ${evento.liga}", color = Color.White.copy(alpha = 0.95f),
                        fontSize = if (esMovil) 12.sp else 13.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@Composable
private fun LiveBadgeDetalle() {
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 900)
    Box(
        Modifier.alpha(pulse)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFF3B30), Color(0xFFFF6B5D))))
            .padding(horizontal = 12.dp, vertical = 5.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(Color.White))
            Spacer(Modifier.width(6.dp))
            Text("EN VIVO", color = Color.White, fontSize = 11.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
    }
}

@Composable
private fun CountdownBadgeDetalle(mins: Int) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFFA500), Color(0xFFFFC040))))
            .padding(horizontal = 12.dp, vertical = 5.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⏰", fontSize = 11.sp)
            Spacer(Modifier.width(5.dp))
            Text("EN ${mins}MIN", color = Color.Black, fontSize = 11.sp,
                fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
        }
    }
}

@Composable
private fun PillBadge(texto: String, bg: Color, fg: Color) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp)).background(bg)
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Text(texto, color = fg, fontSize = 10.sp, fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp, maxLines = 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN: EN VIVO
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionEnVivo(
    evento: Evento, partido: PartidoEnVivo?, cargando: Boolean, error: String?,
    esTV: Boolean, esMovil: Boolean, statsExpandidas: Boolean,
    onToggleStats: () -> Unit
) {
    Column(
        Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 150)
    ) {
        if (cargando && partido == null) {
            CargandoCard("Buscando datos en vivo...", esTV)
            return@Column
        }
        if (partido != null) {
            MarcadorBroadcast(partido, esTV, esMovil)
            if (partido.estadisticas != null && partido.enVivo) {
                Spacer(Modifier.height(12.dp))
                StatsCard(
                    partido.estadisticas, esTV, esMovil,
                    expandidas = esTV || statsExpandidas,
                    colapsable = !esTV,
                    onToggle = onToggleStats
                )
            }
            if (partido.eventos.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                TimelineCard(partido.eventos, esTV, esMovil)
            }
        } else if (error != null) {
            InfoCard("ℹ️", error, esTV)
        }
    }
}

@Composable
private fun MarcadorBroadcast(partido: PartidoEnVivo, esTV: Boolean, esMovil: Boolean) {
    val liveColor = Color(0xFFFF3B30)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 900)

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(listOf(
                    Color(0xFF15151C), Color(0xFF0D0D12)
                ))
            )
            .border(
                if (partido.enVivo) 2.dp else 1.dp,
                if (partido.enVivo) liveColor.copy(alpha = 0.6f) else AppColors.Gold.copy(alpha = 0.3f),
                RoundedCornerShape(20.dp)
            )
            .padding(if (esMovil) 16.dp else 22.dp)
    ) {
        // Header: estado + minuto
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (partido.enVivo) {
                Box(
                    Modifier.alpha(pulse).clip(RoundedCornerShape(6.dp))
                        .background(liveColor)
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text("● LIVE", color = Color.White,
                        fontSize = if (esMovil) 10.sp else 12.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                }
                Spacer(Modifier.width(10.dp))
                Text("${partido.minuto}'",
                    color = AppColors.GoldBright,
                    fontSize = if (esMovil) 18.sp else 24.sp,
                    fontWeight = FontWeight.Black)
            } else if (partido.terminado) {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(AppColors.TextMuted.copy(alpha = 0.3f))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text("FINALIZADO", color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 10.sp else 12.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(estadoHumano(partido.estadoCorto),
                color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 13.sp,
                fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(if (esMovil) 16.dp else 22.dp))

        // Marcador
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                if (partido.localLogo.isNotBlank()) {
                    AsyncImage(
                        model = partido.localLogo, contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(if (esMovil) 52.dp else 68.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(partido.localNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    if (partido.noEmpezado) "vs" else "${partido.golesLocal} - ${partido.golesVisitante}",
                    color = if (partido.enVivo) AppColors.GoldBright else Color.White,
                    fontSize = if (esMovil) 40.sp else 54.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 3.sp
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                if (partido.visitanteLogo.isNotBlank()) {
                    AsyncImage(
                        model = partido.visitanteLogo, contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(if (esMovil) 52.dp else 68.dp)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text(partido.visitanteNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun StatsCard(
    stats: EstadisticasPartido, esTV: Boolean, esMovil: Boolean,
    expandidas: Boolean, colapsable: Boolean, onToggle: () -> Unit
) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(16.dp))
            .padding(if (esMovil) 14.dp else 18.dp)
    ) {
        Row(
            Modifier.fillMaxWidth()
                .then(if (colapsable) Modifier.clickable { onToggle() } else Modifier),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("📊", fontSize = if (esMovil) 15.sp else 18.sp)
            Spacer(Modifier.width(8.dp))
            Text("ESTADÍSTICAS", color = AppColors.GoldBright,
                fontSize = if (esMovil) 12.sp else 14.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            if (colapsable) {
                Spacer(Modifier.weight(1f))
                Text(if (expandidas) "▲" else "▼",
                    color = AppColors.TextSecondary, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
        AnimatedVisibility(expandidas, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            Column {
                Spacer(Modifier.height(14.dp))
                StatBar("Posesión", stats.posesionLocal, stats.posesionVisitante, "%", esMovil)
                Spacer(Modifier.height(12.dp))
                StatBar("Corners", stats.cornersLocal, stats.cornersVisitante, "", esMovil)
                Spacer(Modifier.height(12.dp))
                StatBar("Tiros", stats.tirosLocal, stats.tirosVisitante, "", esMovil)
            }
        }
    }
}

@Composable
private fun StatBar(label: String, local: Int, visitante: Int, sufijo: String, esMovil: Boolean) {
    val total = (local + visitante).coerceAtLeast(1)
    val fracLocal = local.toFloat() / total
    val animFrac by animateFloatAsState(fracLocal, tween(600), label = "statBar")

    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("$local$sufijo", color = AppColors.GoldBright,
                fontSize = if (esMovil) 13.sp else 14.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Text(label, color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 12.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.weight(1f))
            Text("$visitante$sufijo", color = AppColors.GoldBright,
                fontSize = if (esMovil) 13.sp else 14.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(Color(0xFF1A1A22))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(animFrac).background(AppColors.Gold))
            Box(Modifier.fillMaxHeight().weight(1f).background(Color(0xFF2A2A33)))
        }
    }
}

@Composable
private fun TimelineCard(eventos: List<EventoPartido>, esTV: Boolean, esMovil: Boolean) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(16.dp))
            .padding(if (esMovil) 14.dp else 18.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚡", fontSize = if (esMovil) 15.sp else 18.sp)
            Spacer(Modifier.width(8.dp))
            Text("EVENTOS", color = AppColors.GoldBright,
                fontSize = if (esMovil) 12.sp else 14.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(12.dp))
        eventos.sortedByDescending { it.minuto }.forEach { ev ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = if (esMovil) 4.dp else 5.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier.width(if (esMovil) 34.dp else 40.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFF1A1A22))
                        .padding(vertical = 3.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("${ev.minuto}'", color = AppColors.GoldBright,
                        fontSize = if (esMovil) 11.sp else 12.sp, fontWeight = FontWeight.Black)
                }
                Spacer(Modifier.width(10.dp))
                Text(emojiEvento(ev.tipo, ev.detalle), fontSize = if (esMovil) 14.sp else 16.sp)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(ev.jugador.ifBlank { ev.detalle }, color = Color.White,
                        fontSize = if (esMovil) 12.sp else 14.sp,
                        fontWeight = FontWeight.Medium, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                    Text(ev.equipo, color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 10.sp else 11.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun CargandoCard(mensaje: String, esTV: Boolean) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(14.dp))
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CircularProgressIndicator(color = AppColors.Gold, strokeWidth = 2.dp,
            modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(mensaje, color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun InfoCard(emoji: String, mensaje: String, esTV: Boolean) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF0D0D12))
            .border(1.dp, AppColors.TextMuted.copy(alpha = 0.3f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(emoji, fontSize = 18.sp)
        Spacer(Modifier.width(10.dp))
        Text(mensaje, color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN: FINALIZADO (con video MP4 en bucle)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SeccionFinalizado(evento: Evento, esTV: Boolean, esMovil: Boolean) {
    Column(
        Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 150)
    ) {
        Box(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF0D0D12))
                .border(1.dp, AppColors.TextMuted.copy(alpha = 0.3f), RoundedCornerShape(20.dp))
                .height(if (esMovil) 200.dp else 280.dp)
        ) {
            if (evento.videoFinalizado.isNotBlank()) {
                VideoLoopPlayer(evento.videoFinalizado, Modifier.fillMaxSize())
                // Overlay con mensaje
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.75f)
                        ))
                    )
                )
                Column(
                    Modifier.fillMaxSize().padding(20.dp),
                    verticalArrangement = Arrangement.Bottom
                ) {
                    Text(
                        "Evento Finalizado",
                        color = Color.White,
                        fontSize = if (esMovil) 18.sp else 22.sp,
                        fontWeight = FontWeight.Black
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "El partido ya terminó. Podés ver los canales pero no hay transmisión en vivo.",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = if (esMovil) 11.sp else 13.sp,
                        lineHeight = if (esMovil) 15.sp else 17.sp
                    )
                }
            } else {
                // Placeholder sin video
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("✓", fontSize = if (esMovil) 44.sp else 56.sp, color = AppColors.TextMuted)
                        Spacer(Modifier.height(10.dp))
                        Text("Evento Finalizado", color = Color.White,
                            fontSize = if (esMovil) 16.sp else 20.sp, fontWeight = FontWeight.Black)
                        Spacer(Modifier.height(6.dp))
                        Text("Los canales siguen disponibles", color = AppColors.TextSecondary,
                            fontSize = if (esMovil) 11.sp else 13.sp)
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN: PRÓXIMO (con video MP4 en bucle)
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

    Column(
        Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 150)
    ) {
        Box(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF0D0D12))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.35f), RoundedCornerShape(20.dp))
                .height(if (esMovil) 200.dp else 280.dp)
        ) {
            if (evento.videoProximo.isNotBlank()) {
                VideoLoopPlayer(evento.videoProximo, Modifier.fillMaxSize())
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.75f)
                        ))
                    )
                )
                Column(
                    Modifier.fillMaxSize().padding(20.dp),
                    verticalArrangement = Arrangement.Bottom
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("⏰", fontSize = 16.sp)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            cuentaTexto,
                            color = AppColors.GoldBright,
                            fontSize = if (esMovil) 14.sp else 16.sp,
                            fontWeight = FontWeight.Black
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "El evento todavía no comenzó. Volvé a esta pantalla cuando arranque.",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = if (esMovil) 11.sp else 13.sp,
                        lineHeight = if (esMovil) 15.sp else 17.sp
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
                        Text("⏰", fontSize = if (esMovil) 44.sp else 56.sp)
                        Spacer(Modifier.height(10.dp))
                        Text(cuentaTexto, color = AppColors.GoldBright,
                            fontSize = if (esMovil) 16.sp else 20.sp, fontWeight = FontWeight.Black)
                        Spacer(Modifier.height(6.dp))
                        Text("Los canales aparecerán aquí", color = AppColors.TextSecondary,
                            fontSize = if (esMovil) 11.sp else 13.sp)
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// CANALES
// ═══════════════════════════════════════════════════════════════

@Composable
private fun RowCanales(evento: Evento, esTV: Boolean, esMovil: Boolean) {
    Row(
        Modifier.fillMaxWidth().fadeInOnLoad(450, delayMs = 100),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.canales,
            contentDescription = null,
            tint = AppColors.GoldBright,
            modifier = Modifier.size(if (esMovil) 18.dp else 22.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            if (esMovil) "Elegí un canal" else "Elegí un canal para reproducir",
            color = AppColors.TextPrimary,
            fontSize = if (esMovil) 16.sp else 20.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.width(10.dp))
        Box(
            Modifier.clip(RoundedCornerShape(10.dp))
                .background(AppColors.Gold.copy(alpha = 0.2f))
                .padding(horizontal = 9.dp, vertical = 3.dp)
        ) {
            Text("${evento.embeds.size}", color = AppColors.Gold,
                fontSize = if (esMovil) 11.sp else 12.sp,
                fontWeight = FontWeight.Black)
        }
    }
}

@Composable
private fun CanalCard(embed: Embed, esTV: Boolean, esMovil: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.02f else 1f, tween(200), label = "canalScale")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.18f),
        tween(180), label = "canalBorder"
    )
    val bg by animateColorAsState(
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
            .clip(RoundedCornerShape(16.dp))
            .background(bg)
            .border(if (focused) 2.dp else 1.dp, borderColor, RoundedCornerShape(16.dp))
            .padding(
                horizontal = if (esMovil) 14.dp else 22.dp,
                vertical = if (esMovil) 14.dp else 18.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(if (esMovil) 44.dp else 52.dp).clip(CircleShape)
                .background(
                    Brush.linearGradient(
                        if (focused) listOf(AppColors.GoldBright, AppColors.Gold)
                        else listOf(AppColors.Gold, AppColors.Gold.copy(alpha = 0.8f))
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color.Black,
                modifier = Modifier.size(if (esMovil) 20.dp else 24.dp)
            )
        }
        Spacer(Modifier.width(if (esMovil) 12.dp else 18.dp))
        Column(Modifier.weight(1f)) {
            Text(
                embed.nombre,
                color = Color.White,
                fontSize = if (esMovil) 14.sp else 18.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            if (esTV) {
                Spacer(Modifier.height(2.dp))
                Text(
                    if (focused) "Presioná OK para reproducir" else "OK para reproducir",
                    color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                    fontSize = 11.sp,
                    fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
        Text(
            if (focused) "▶" else "→",
            color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            fontSize = if (esMovil) 18.sp else 20.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN VOLVER
// ═══════════════════════════════════════════════════════════════

@Composable
private fun BotonVolver(onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.08f))
            .border(1.dp, if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else AppColors.GoldBright,
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(6.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else AppColors.GoldBright,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
KOTLIN_EOF

echo "✅ EventDetailScreen.kt reescrito"

echo ""
echo "✅✅✅ Detail v3 Premium completo"
echo ""
echo "📋 Próximos pasos:"
echo "  1. Agregar columnas al Sheet: duracion_minutos, video_finalizado, video_proximo"
echo "  2. Actualizar el Apps Script para sincronizar esos campos"
echo "  3. Compilar:  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
