#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
[ ! -f "$HOME" ] && { echo "❌ No existe $HOME"; exit 1; }
cp "$HOME" "${HOME}.bak.premium.$(date +%s)"
echo "✅ Backup: ${HOME}.bak.premium.$(date +%s)"

cat > "$HOME" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.notifications.EventNotifScheduler
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.shimmer
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.util.rememberEsTV
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

private fun horaAMinutos(hora: String): Int {
    val match = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return Int.MAX_VALUE
    val h = match.groupValues[1].toIntOrNull() ?: return Int.MAX_VALUE
    val m = match.groupValues[2].toIntOrNull() ?: return Int.MAX_VALUE
    if (h !in 0..23 || m !in 0..59) return Int.MAX_VALUE
    return h * 60 + m
}

private fun estaEnVivo(ev: Evento): Boolean {
    return try {
        if (ev.fecha != FechaHelper.hoy()) return false
        val ahora = Calendar.getInstance()
        val minActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val minEvento = horaAMinutos(ev.hora)
        if (minEvento == Int.MAX_VALUE) return false
        minActual >= minEvento && minActual < minEvento + 150
    } catch (e: Exception) { false }
}

private fun diaRelativo(ev: Evento): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(ev.fecha) ?: return "PRÓXIMOS"
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val diffDias = ((cal.timeInMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()

        when {
            diffDias < 0 -> "IGNORAR"
            diffDias == 0 -> {
                val minActual = Calendar.getInstance().let {
                    it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE)
                }
                val minEvento = horaAMinutos(ev.hora)
                if (minEvento != Int.MAX_VALUE && minActual > minEvento + 150) "FINALIZADOS" else "HOY"
            }
            diffDias == 1 -> "MAÑANA"
            diffDias == 2 -> "PASADO MAÑANA"
            diffDias in 3..7 -> "ESTA SEMANA"
            else -> "PRÓXIMOS"
        }
    } catch (e: Exception) { "PRÓXIMOS" }
}

private fun agruparEventos(eventos: List<Evento>): Pair<List<Evento>, List<Pair<String, List<Evento>>>> {
    val enVivo = mutableListOf<Evento>()
    val porDia = mutableMapOf<String, MutableList<Evento>>()
    eventos.forEach { ev ->
        if (estaEnVivo(ev)) enVivo.add(ev)
        else {
            val dia = diaRelativo(ev)
            if (dia != "IGNORAR") porDia.getOrPut(dia) { mutableListOf() }.add(ev)
        }
    }
    enVivo.sortBy { horaAMinutos(it.hora) }
    porDia.values.forEach { it.sortBy { horaAMinutos(it.hora) } }
    val orden = listOf("HOY", "MAÑANA", "PASADO MAÑANA", "ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
    val gruposOrdenados = porDia.entries
        .sortedBy { (k, _) -> orden.indexOf(k).let { if (it < 0) 999 else it } }
        .map { it.key to it.value }
    return enVivo to gruposOrdenados
}

private fun anchoCard(esTV: Boolean, esVertical: Boolean): Dp = when {
    esTV -> 320.dp
    esVertical -> 170.dp
    else -> 220.dp
}

// ═══════════════════════════════════════════════════════════════
// HOME PRINCIPAL
// ═══════════════════════════════════════════════════════════════

@Composable
fun HomeScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onIrAAjustes: () -> Unit = {},
    onIrABusqueda: () -> Unit = {}
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()
    val esTV = rememberEsTV()
    val configuration = LocalConfiguration.current
    val esVertical = configuration.orientation == Configuration.ORIENTATION_PORTRAIT
    val esMovil = !esTV && esVertical

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var cargandoScraping by remember { mutableStateOf(false) }
    var scrapingCargado by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Conectando...") }
    var tabSeleccionado by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        try {
            status = "Cargando..."
            eventosFirebase = EventRepository.obtenerEventosFirestore()
        } catch (e: Exception) { status = "Error: ${e.message}" }
        cargando = false
        try { EventNotifScheduler.reagendar(context, eventosFirebase) } catch (_: Exception) {}
    }

    LaunchedEffect(tabSeleccionado) {
        if (tabSeleccionado == 1 && !scrapingCargado && eventosScraping.isEmpty()) {
            cargandoScraping = true
            try {
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
                scrapingCargado = true
                EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping)
            } catch (e: Exception) { status = "Error: ${e.message}" }
            cargandoScraping = false
        }
    }

    Box(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(listOf(Color(0xFF050505), Color(0xFF0A0A0F)))
        )
    ) {
        if (cargando) {
            SkeletonPremium(status)
        } else {
            Column(Modifier.fillMaxSize()) {
                Spacer(Modifier.height(if (esMovil) 14.dp else 28.dp))
                TopBar(
                    totalEventos = eventosFirebase.size + eventosScraping.size,
                    totalCanales = (eventosFirebase + eventosScraping).sumOf { it.embeds.size },
                    esMovil = esMovil,
                    onIrAAjustes = onIrAAjustes,
                    onIrABusqueda = onIrABusqueda
                )

                if (config.mensajeSistema.isNotBlank()) {
                    Spacer(Modifier.height(14.dp))
                    BannerPremium(config.mensajeSistema, esMovil)
                }

                Spacer(Modifier.height(if (esMovil) 14.dp else 22.dp))
                TabSelectorPremium(tabSeleccionado, { tabSeleccionado = it }, esMovil)
                Spacer(Modifier.height(4.dp))

                when (tabSeleccionado) {
                    0 -> ContenidoMisEventos(eventosFirebase, esTV, esVertical, esMovil, onEventoClick)
                    1 -> ContenidoAgendas(eventosScraping, cargandoScraping, config.mostrarScraping, esTV, esVertical, esMovil, status, onEventoClick)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// TOP BAR
// ═══════════════════════════════════════════════════════════════

@Composable
private fun TopBar(
    totalEventos: Int, totalCanales: Int,
    esMovil: Boolean,
    onIrAAjustes: () -> Unit, onIrABusqueda: () -> Unit
) {
    val pulse = rememberPulseAlpha(min = 0.4f, max = 1f, durationMs = 1400)
    val padH = if (esMovil) 16.dp else 48.dp
    val tituloSize = if (esMovil) 26.sp else 38.sp
    val logoSize = if (esMovil) 26.sp else 34.sp

    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("⚽", fontSize = logoSize)
        Spacer(Modifier.width(8.dp))
        Text(
            "FutTV",
            color = AppColors.GoldBright,
            fontSize = tituloSize,
            fontWeight = FontWeight.Black,
            letterSpacing = (-0.5).sp
        )
        Spacer(Modifier.width(10.dp))
        Box(
            Modifier.alpha(pulse)
                .clip(RoundedCornerShape(20.dp))
                .background(Brush.horizontalGradient(listOf(
                    Color(0xFFFF3B30), Color(0xFFFF6B5D)
                )))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(Color.White))
                Spacer(Modifier.width(5.dp))
                Text("EN VIVO", color = Color.White, fontSize = 10.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            }
        }
        Spacer(Modifier.weight(1f))
        GlassIconButton("🔍", onIrABusqueda)
        Spacer(Modifier.width(10.dp))
        GlassIconButton("⚙️", onIrAAjustes)
    }

    Spacer(Modifier.height(6.dp))
    Text(
        "$totalEventos eventos · $totalCanales canales disponibles",
        color = AppColors.TextSecondary,
        fontSize = if (esMovil) 11.sp else 13.sp,
        modifier = Modifier.padding(horizontal = padH),
        maxLines = 1, overflow = TextOverflow.Ellipsis
    )
}

@Composable
private fun GlassIconButton(icono: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.1f else 1f, tween(180), label = "glassScale")
    Box(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(CircleShape)
            .background(if (focused) AppColors.GoldBright.copy(alpha = 0.25f) else Color.White.copy(alpha = 0.08f))
            .border(1.dp, if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.15f), CircleShape)
            .padding(10.dp)
    ) {
        Text(icono, fontSize = 16.sp)
    }
}

// ═══════════════════════════════════════════════════════════════
// TABS PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun TabSelectorPremium(seleccionado: Int, onSeleccion: (Int) -> Unit, esMovil: Boolean) {
    val padH = if (esMovil) 16.dp else 48.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        TabPremium("🎯 Mis Eventos", seleccionado == 0, { onSeleccion(0) }, Modifier.weight(1f), esMovil)
        TabPremium("🌐 Agendas", seleccionado == 1, { onSeleccion(1) }, Modifier.weight(1f), esMovil)
    }
}

@Composable
private fun TabPremium(titulo: String, activo: Boolean, onClick: () -> Unit, modifier: Modifier, esMovil: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        when {
            focused -> AppColors.GoldBright.copy(alpha = 0.25f)
            activo -> AppColors.Gold.copy(alpha = 0.15f)
            else -> Color.White.copy(alpha = 0.05f)
        }, tween(200), label = "tabBg"
    )
    val border by animateColorAsState(
        when {
            focused -> AppColors.GoldBright
            activo -> AppColors.Gold
            else -> Color.White.copy(alpha = 0.1f)
        }, tween(200), label = "tabBorder"
    )
    val textColor = if (focused || activo) AppColors.GoldBright else AppColors.TextSecondary

    Box(
        modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(if (focused) 2.dp else 1.dp, border, RoundedCornerShape(14.dp))
            .padding(vertical = if (esMovil) 12.dp else 16.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            titulo, color = textColor,
            fontSize = if (esMovil) 13.sp else 15.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.3.sp,
            maxLines = 1, overflow = TextOverflow.Ellipsis
        )
    }
}

// ═══════════════════════════════════════════════════════════════
// CONTENIDO: MIS EVENTOS
// ═══════════════════════════════════════════════════════════════

@Composable
private fun ContenidoMisEventos(
    eventos: List<Evento>,
    esTV: Boolean, esVertical: Boolean, esMovil: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (eventos.isEmpty()) {
        EmptyPremium("📭", "Sin eventos programados", "Cargá eventos desde el panel", esMovil)
        return
    }

    val (enVivo, gruposPorDia) = remember(eventos) { agruparEventos(eventos) }
    val expandidos = remember { mutableStateMapOf<String, Boolean>() }
    val destacado = enVivo.firstOrNull() ?: gruposPorDia.firstOrNull()?.second?.firstOrNull()

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 60.dp)) {
        if (destacado != null) {
            item(key = "hero") {
                Spacer(Modifier.height(16.dp))
                HeroPremium(destacado, esTV, esMovil, estaEnVivo(destacado)) {
                    val listaHero = if (enVivo.isNotEmpty()) enVivo else (gruposPorDia.firstOrNull()?.second ?: listOf(destacado))
                    onEventoClick(destacado, listaHero)
                }
                Spacer(Modifier.height(28.dp))
            }
        }

        if (enVivo.isNotEmpty()) {
            item(key = "row_live_header") {
                RowTitulo(
                    titulo = "EN VIVO AHORA",
                    subtitulo = "${enVivo.size} ${if (enVivo.size == 1) "evento" else "eventos"}",
                    acento = Color(0xFFFF3B30),
                    esMovil = esMovil
                )
            }
            item(key = "row_live") { FilaEventos(enVivo, onEventoClick, esTV, esVertical, esMovil) }
        }

        gruposPorDia.forEach { (dia, lista) ->
            val acento = when (dia) {
                "HOY" -> AppColors.GoldBright
                "MAÑANA" -> AppColors.Gold
                "PASADO MAÑANA" -> AppColors.Gold.copy(alpha = 0.8f)
                "FINALIZADOS" -> AppColors.TextMuted
                else -> AppColors.TextSecondary
            }
            val label = when (dia) {
                "HOY" -> "HOY"
                "MAÑANA" -> "MAÑANA"
                "PASADO MAÑANA" -> "PASADO MAÑANA"
                "ESTA SEMANA" -> "ESTA SEMANA"
                "PRÓXIMOS" -> "PRÓXIMOS DÍAS"
                "FINALIZADOS" -> "FINALIZADOS"
                else -> dia
            }
            val colapsable = dia in listOf("ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
            val expandido = expandidos.getOrPut(dia) { !colapsable }

            item(key = "head_$dia") {
                RowTitulo(
                    titulo = label,
                    subtitulo = "${lista.size} ${if (lista.size == 1) "evento" else "eventos"}",
                    acento = acento,
                    esMovil = esMovil,
                    colapsable = colapsable,
                    expandido = expandido,
                    onToggle = { expandidos[dia] = !expandido }
                )
            }
            if (expandido) {
                item(key = "row_$dia") { FilaEventos(lista, onEventoClick, esTV, esVertical, esMovil) }
            }
        }

        item(key = "footer") {
            Spacer(Modifier.height(40.dp))
            Text(
                "FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = AppColors.TextMuted, fontSize = 10.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = if (esMovil) 16.dp else 48.dp)
            )
        }
    }
}

@Composable
private fun RowTitulo(
    titulo: String, subtitulo: String, acento: Color,
    esMovil: Boolean,
    colapsable: Boolean = false,
    expandido: Boolean = true,
    onToggle: (() -> Unit)? = null
) {
    var focused by remember { mutableStateOf(false) }
    val padH = if (esMovil) 16.dp else 48.dp

    val base = Modifier.fillMaxWidth().padding(horizontal = padH, vertical = 6.dp)
        .fadeInOnLoad(400)
    val interactivo = if (colapsable && onToggle != null) {
        base.onFocusChanged { focused = it.isFocused }.focusable().clickable { onToggle() }
    } else base

    Row(interactivo, verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.width(4.dp)
                .height(if (esMovil) 26.dp else 34.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(acento)
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo, color = AppColors.TextPrimary,
                fontSize = if (esMovil) 18.sp else 22.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 0.5.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitulo, color = AppColors.TextSecondary,
                fontSize = if (esMovil) 11.sp else 12.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
        if (colapsable) {
            Text(
                if (expandido) "▲" else "▼",
                color = if (focused) AppColors.GoldBright else AppColors.TextSecondary,
                fontSize = 14.sp, fontWeight = FontWeight.Bold
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// HERO PREMIUM (Disney+ style)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun HeroPremium(
    evento: Evento, esTV: Boolean, esMovil: Boolean, enVivo: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.015f else 1f, tween(250), label = "heroScale")
    val padH = if (esMovil) 16.dp else 48.dp
    val altura = if (esTV) 340.dp else if (esMovil) 280.dp else 320.dp

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = padH)
            .fadeInOnLoad(500)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(24.dp))
            .background(Color(0xFF0D0D12))
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.3f),
                RoundedCornerShape(24.dp)
            )
            .height(altura)
    ) {
        // Imagen de fondo
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }

        // Gradiente oscuro abajo (estilo Disney+)
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    listOf(
                        Color.Transparent,
                        Color(0xFF050505).copy(alpha = 0.4f),
                        Color(0xFF050505).copy(alpha = 0.95f)
                    )
                )
            )
        )

        // Contenido inferior
        Column(
            Modifier.fillMaxSize().padding(if (esMovil) 20.dp else 32.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (enVivo) {
                    LiveBadge()
                } else {
                    PillBadge("⭐ DESTACADO", AppColors.GoldBright, Color.Black)
                }
                PillBadge(
                    "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                    Color.White.copy(alpha = 0.15f),
                    Color.White
                )
            }
            Spacer(Modifier.height(14.dp))
            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = if (esTV) 40.sp else if (esMovil) 26.sp else 32.sp,
                fontWeight = FontWeight.Black,
                lineHeight = (if (esTV) 44.sp else if (esMovil) 30.sp else 36.sp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                letterSpacing = (-0.5).sp
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                MetaChip("🕐 ${evento.hora}", esMovil)
                MetaChip("📅 ${evento.fecha}", esMovil)
                MetaChip("📺 ${evento.embeds.size} canales", esMovil)
            }
            Spacer(Modifier.height(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    Modifier.clip(RoundedCornerShape(12.dp))
                        .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                        .padding(horizontal = 22.dp, vertical = 12.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("▶", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "VER AHORA", color = Color.Black,
                            fontSize = 14.sp, fontWeight = FontWeight.Black,
                            letterSpacing = 1.sp
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LiveBadge() {
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
private fun PillBadge(texto: String, bg: Color, fg: Color) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp)).background(bg)
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Text(texto, color = fg, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp, maxLines = 1)
    }
}

@Composable
private fun MetaChip(texto: String, esMovil: Boolean) {
    Text(texto, color = Color.White.copy(alpha = 0.9f), fontSize = if (esMovil) 11.sp else 13.sp, fontWeight = FontWeight.Medium)
}

// ═══════════════════════════════════════════════════════════════
// FILA + CARD PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    esTV: Boolean, esVertical: Boolean, esMovil: Boolean
) {
    val ancho = anchoCard(esTV, esVertical)
    val padH = if (esMovil) 16.dp else 48.dp
    LazyRow(
        contentPadding = PaddingValues(horizontal = padH, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
            Box(Modifier.fadeInOnLoad(450, delayMs = 100 + index * 50)) {
                CardPremium(ev, ancho, esTV, esMovil) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun CardPremium(
    ev: Evento, ancho: Dp, esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, tween(220), label = "cardScale")
    val enVivo = estaEnVivo(ev)
    val altura = if (esTV) 220.dp else if (esMovil) 140.dp else 180.dp

    Box(
        Modifier
            .width(ancho)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF0D0D12))
            .border(
                if (focused) 2.dp else 1.dp,
                when {
                    enVivo -> Color(0xFFFF3B30)
                    focused -> AppColors.GoldBright
                    else -> Color.White.copy(alpha = 0.08f)
                },
                RoundedCornerShape(18.dp)
            )
    ) {
        Column {
            // Imagen / fondo
            Box(
                Modifier.fillMaxWidth().height(altura).background(
                    Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                ),
                contentAlignment = Alignment.Center
            ) {
                if (ev.imagen.isNotBlank()) {
                    AsyncImage(
                        model = ev.imagen, contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().alpha(0.75f)
                    )
                    // Gradiente para legibilidad
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))
                            )
                        )
                    )
                } else {
                    Text("⚽", fontSize = if (esMovil) 40.sp else 56.sp, color = Color.White.copy(alpha = 0.4f))
                }

                // Badge LIVE arriba-izq
                if (enVivo) {
                    Box(
                        Modifier.align(Alignment.TopStart).padding(10.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFFFF3B30))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Text("● LIVE", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
                    }
                }
                // Hora arriba-der
                Box(
                    Modifier.align(Alignment.TopEnd).padding(10.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.7f))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(ev.hora, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }

            // Info abajo (fuera de la imagen)
            Column(Modifier.padding(if (esMovil) 10.dp else 12.dp)) {
                Text(
                    ev.descripcion,
                    color = Color.White,
                    fontSize = if (esMovil) 12.sp else 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    lineHeight = if (esMovil) 15.sp else 16.sp,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.height(if (esMovil) 30.dp else 32.dp)
                )
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${AppColors.fuenteIcono(ev.groupTitle)} ${ev.groupTitle}",
                        color = AppColors.Gold,
                        fontSize = if (esMovil) 9.sp else 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        "${ev.embeds.size} 📺",
                        color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 9.sp else 10.sp
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// CONTENIDO: AGENDAS
// ═══════════════════════════════════════════════════════════════

@Composable
private fun ContenidoAgendas(
    eventos: List<Evento>, cargando: Boolean, mostrarScraping: Boolean,
    esTV: Boolean, esVertical: Boolean, esMovil: Boolean,
    status: String, onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (!mostrarScraping) {
        EmptyPremium("🌐", "Agendas deshabilitadas", "El panel desactivó el scraping", esMovil)
        return
    }
    if (cargando) { SkeletonPremium(status); return }
    if (eventos.isEmpty()) {
        EmptyPremium("🌐", "Sin agendas disponibles", "Probá de nuevo en unos minutos", esMovil)
        return
    }

    val grupos = remember(eventos) { eventos.groupBy { it.groupTitle } }
    val padH = if (esMovil) 16.dp else 48.dp

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 60.dp)) {
        item(key = "intro") {
            Spacer(Modifier.height(14.dp))
            Text(
                "${eventos.size} eventos · scraping en vivo",
                color = AppColors.TextSecondary, fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = padH).fadeInOnLoad(400)
            )
            Spacer(Modifier.height(8.dp))
        }
        grupos.forEach { (titulo, lista) ->
            item(key = "head_$titulo") {
                RowTitulo(
                    titulo = titulo,
                    subtitulo = "${lista.size} eventos",
                    acento = AppColors.fuenteColor(titulo),
                    esMovil = esMovil
                )
            }
            item(key = "row_$titulo") { FilaEventos(lista, onEventoClick, esTV, esVertical, esMovil) }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// SKELETON + EMPTY
// ═══════════════════════════════════════════════════════════════

@Composable
private fun SkeletonPremium(status: String) {
    val esMovil = !rememberEsTV()
    val padH = if (esMovil) 16.dp else 48.dp
    Column(Modifier.fillMaxSize().padding(top = if (esMovil) 20.dp else 36.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(350), verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = if (esMovil) 26.sp else 34.sp)
            Spacer(Modifier.width(8.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = if (esMovil) 26.sp else 38.sp,
                fontWeight = FontWeight.Black, letterSpacing = (-0.5).sp)
            Spacer(Modifier.width(14.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(22.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(50.dp).shimmer(RoundedCornerShape(14.dp)))
            Box(Modifier.weight(1f).height(50.dp).shimmer(RoundedCornerShape(14.dp)))
        }
        Spacer(Modifier.height(20.dp))
        Box(Modifier.fillMaxWidth().padding(horizontal = padH).height(if (esMovil) 280.dp else 340.dp).shimmer(RoundedCornerShape(24.dp)))
        Spacer(Modifier.height(28.dp))
        repeat(2) {
            Box(Modifier.padding(horizontal = padH).width(200.dp).height(26.dp).shimmer(RoundedCornerShape(8.dp)))
            Spacer(Modifier.height(14.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(14.dp), userScrollEnabled = false) {
                repeat(4) { item { Box(Modifier.width(if (esMovil) 170.dp else 320.dp).height(if (esMovil) 240.dp else 280.dp).shimmer(RoundedCornerShape(18.dp))) } }
            }
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun EmptyPremium(emoji: String, titulo: String, subtitulo: String, esMovil: Boolean) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(emoji, fontSize = if (esMovil) 60.sp else 72.sp)
            Spacer(Modifier.height(16.dp))
            Text(titulo, color = AppColors.TextPrimary, fontSize = if (esMovil) 18.sp else 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(subtitulo, color = AppColors.TextSecondary, fontSize = if (esMovil) 12.sp else 14.sp)
        }
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ Home Premium Disney+ style completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
