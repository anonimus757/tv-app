#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# HOME SCREEN — Disney+ Style
# ═══════════════════════════════════════════════════════════
HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME" "${HOME}.bak.disney.$(date +%s)"
echo "✅ Backup Home"

cat > "$HOME" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import androidx.compose.animation.animateColorAsState
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

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

private fun horaAMinutos(hora: String): Int {
    val m = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return Int.MAX_VALUE
    val h = m.groupValues[1].toIntOrNull() ?: return Int.MAX_VALUE
    val mi = m.groupValues[2].toIntOrNull() ?: return Int.MAX_VALUE
    if (h !in 0..23 || mi !in 0..59) return Int.MAX_VALUE
    return h * 60 + mi
}

private fun estaEnVivo(ev: Evento): Boolean {
    return try {
        if (ev.fecha != FechaHelper.hoy()) return false
        val ahora = Calendar.getInstance()
        val minActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val minEv = horaAMinutos(ev.hora)
        if (minEv == Int.MAX_VALUE) return false
        minActual >= minEv && minActual < minEv + ev.duracionMinutos
    } catch (e: Exception) { false }
}

private fun diaRelativo(ev: Evento): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEv = sdf.parse(ev.fecha) ?: return "PRÓXIMOS"
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoy = cal.timeInMillis
        cal.time = fechaEv
        cal.set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val diff = ((cal.timeInMillis - hoy) / (1000L * 60L * 60L * 24L)).toInt()
        when {
            diff < 0 -> "IGNORAR"
            diff == 0 -> {
                val ahora = Calendar.getInstance()
                val minAct = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
                val minEv = horaAMinutos(ev.hora)
                if (minEv != Int.MAX_VALUE && minAct > minEv + ev.duracionMinutos) "FINALIZADOS" else "HOY"
            }
            diff == 1 -> "MAÑANA"
            diff == 2 -> "PASADO MAÑANA"
            diff in 3..7 -> "ESTA SEMANA"
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
            val d = diaRelativo(ev)
            if (d != "IGNORAR") porDia.getOrPut(d) { mutableListOf() }.add(ev)
        }
    }
    enVivo.sortBy { horaAMinutos(it.hora) }
    porDia.values.forEach { it.sortBy { horaAMinutos(it.hora) } }
    val orden = listOf("HOY", "MAÑANA", "PASADO MAÑANA", "ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
    val grupos = porDia.entries
        .sortedBy { (k, _) -> orden.indexOf(k).let { if (it < 0) 999 else it } }
        .map { it.key to it.value }
    return enVivo to grupos
}

// ═══════════════════════════════════════════════════════════
// HOME PRINCIPAL
// ═══════════════════════════════════════════════════════════

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
    var tabPrincipal by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        try {
            status = "Cargando..."
            eventosFirebase = EventRepository.obtenerEventosFirestore()
        } catch (e: Exception) { status = "Error: ${e.message}" }
        cargando = false
        try { EventNotifScheduler.reagendar(context, eventosFirebase) } catch (_: Exception) {}
    }

    LaunchedEffect(tabPrincipal) {
        if (tabPrincipal == 1 && !scrapingCargado && eventosScraping.isEmpty()) {
            cargandoScraping = true
            try {
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
                scrapingCargado = true
                EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping)
            } catch (e: Exception) { status = "Error: ${e.message}" }
            cargandoScraping = false
        }
    }

    Box(Modifier.fillMaxSize().background(Color(0xFF0A0A0F))) {
        if (cargando) {
            SkeletonHome(status)
        } else {
            Column(Modifier.fillMaxSize()) {
                // TopNav sticky
                TopNav(
                    esTV = esTV, esMovil = esMovil,
                    tab = tabPrincipal,
                    onTab = { tabPrincipal = it },
                    onIrAAjustes = onIrAAjustes,
                    onIrABusqueda = onIrABusqueda
                )

                when (tabPrincipal) {
                    0 -> ContenidoMisEventos(eventosFirebase, esTV, esMovil, esVertical, onEventoClick)
                    1 -> ContenidoAgendas(eventosScraping, cargandoScraping, config.mostrarScraping, esTV, esMovil, esVertical, status, onEventoClick)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// TOP NAV (Disney+ style)
// ═══════════════════════════════════════════════════════════

@Composable
private fun TopNav(
    esTV: Boolean, esMovil: Boolean,
    tab: Int, onTab: (Int) -> Unit,
    onIrAAjustes: () -> Unit, onIrABusqueda: () -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val logoSize = if (esTV) 30.sp else if (esMovil) 22.sp else 26.sp
    val pillSize = if (esTV) 14.sp else if (esMovil) 12.sp else 13.sp

    Row(
        Modifier.fillMaxWidth()
            .background(Color(0xFF0A0A0F))
            .padding(horizontal = padH, vertical = if (esTV) 18.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("⚽", fontSize = if (esTV) 28.sp else 22.sp)
        Spacer(Modifier.width(8.dp))
        Text(
            "FutTV",
            color = Color(0xFFFFD700),
            fontSize = logoSize,
            fontWeight = FontWeight.Black,
            letterSpacing = (-0.5).sp
        )
        Spacer(Modifier.width(if (esTV) 42.dp else 20.dp))

        // Tabs estilo Disney+ (texto plano, activo en blanco, inactivo en gris)
        NavPill("Inicio", tab == 0, { onTab(0) }, esTV, pillSize)
        Spacer(Modifier.width(if (esTV) 26.dp else 14.dp))
        NavPill("Agendas", tab == 1, { onTab(1) }, esTV, pillSize)

        Spacer(Modifier.weight(1f))

        NavIcon("🔍", onIrABusqueda, esTV)
        Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
        NavIcon("⚙", onIrAAjustes, esTV)
    }
}

@Composable
private fun NavPill(texto: String, activo: Boolean, onClick: () -> Unit, esTV: Boolean, size: androidx.compose.ui.unit.TextUnit) {
    var focused by remember { mutableStateOf(false) }
    val color by animateColorAsState(
        when {
            focused -> Color.White
            activo -> Color.White
            else -> Color.White.copy(alpha = 0.55f)
        }, tween(150), label = "navColor"
    )

    Column(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            texto,
            color = color,
            fontSize = size,
            fontWeight = if (activo || focused) FontWeight.Bold else FontWeight.Medium,
            letterSpacing = 0.3.sp
        )
        if (activo) {
            Spacer(Modifier.height(4.dp))
            Box(
                Modifier.width(if (esTV) 30.dp else 20.dp).height(2.dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(Color(0xFFFFD700))
            )
        }
    }
}

@Composable
private fun NavIcon(icono: String, onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.15f else 1f, tween(150), label = "navScale")

    Box(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(CircleShape)
            .background(if (focused) Color.White.copy(alpha = 0.15f) else Color.Transparent)
            .padding(if (esTV) 10.dp else 8.dp)
    ) {
        Text(icono, fontSize = if (esTV) 20.sp else 16.sp, color = Color.White)
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: MIS EVENTOS
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoMisEventos(
    eventos: List<Evento>,
    esTV: Boolean, esMovil: Boolean, esVertical: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (eventos.isEmpty()) {
        EmptyState(esMovil)
        return
    }

    val (enVivo, grupos) = remember(eventos) { agruparEventos(eventos) }
    val destacado = remember(enVivo, grupos) {
        enVivo.firstOrNull() ?: grupos.firstOrNull()?.second?.firstOrNull()
    }
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 40.dp)
    ) {
        // HERO (Disney+ style: grande, imagen full, título, CTA)
        if (destacado != null) {
            item(key = "hero") {
                HeroBanner(
                    evento = destacado,
                    esTV = esTV, esMovil = esMovil,
                    onClick = {
                        val lista = if (enVivo.isNotEmpty()) enVivo else (grupos.firstOrNull()?.second ?: listOf(destacado))
                        onEventoClick(destacado, lista)
                    }
                )
                Spacer(Modifier.height(if (esTV) 40.dp else 24.dp))
            }
        }

        // EN VIVO
        if (enVivo.isNotEmpty()) {
            item(key = "h_live") {
                SectionHeader("EN VIVO", "🔴", esTV, esMovil)
            }
            item(key = "r_live") {
                FilaEventosDisney(enVivo, esTV, esMovil, esVertical, onEventoClick)
                Spacer(Modifier.height(if (esTV) 32.dp else 20.dp))
            }
        }

        // HOY, MAÑANA, PASADO, etc.
        grupos.forEach { (dia, lista) ->
            item(key = "h_$dia") {
                SectionHeader(dia, iconoParaDia(dia), esTV, esMovil)
            }
            item(key = "r_$dia") {
                FilaEventosDisney(lista, esTV, esMovil, esVertical, onEventoClick)
                Spacer(Modifier.height(if (esTV) 32.dp else 20.dp))
            }
        }

        item(key = "footer") {
            Spacer(Modifier.height(60.dp))
            Text(
                "FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = Color.White.copy(alpha = 0.3f), fontSize = 11.sp,
                modifier = Modifier.padding(horizontal = padH)
            )
        }
    }
}

private fun iconoParaDia(dia: String): String = when (dia) {
    "HOY" -> "📅"
    "MAÑANA" -> "🌅"
    "PASADO MAÑANA" -> "📆"
    "ESTA SEMANA" -> "🗓"
    "PRÓXIMOS" -> "⏳"
    "FINALIZADOS" -> "✓"
    else -> "📅"
}

// ═══════════════════════════════════════════════════════════
// HERO BANNER (Disney+ style)
// ═══════════════════════════════════════════════════════════

@Composable
private fun HeroBanner(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val altura = if (esTV) 400.dp else if (esMovil) 260.dp else 340.dp
    val tituloSize = if (esTV) 48.sp else if (esMovil) 26.sp else 36.sp
    val enVivo = estaEnVivo(evento)

    Box(
        Modifier.fillMaxWidth().height(altura)
    ) {
        // Imagen full bleed
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.7f)
            )
        } else {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.linearGradient(listOf(Color(0xFF1A1A22), Color(0xFF0A0A0F)))
                )
            )
        }

        // Gradiente izquierda→derecha (Disney+ style)
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color(0xFF0A0A0F),
                        Color(0xFF0A0A0F).copy(alpha = 0.85f),
                        Color(0xFF0A0A0F).copy(alpha = 0.3f),
                        Color.Transparent
                    ),
                    startX = 0f
                )
            )
        )
        // Gradiente abajo (para fade al fondo)
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    colors = listOf(Color.Transparent, Color(0xFF0A0A0F))
                )
            )
        )

        // Contenido
        Column(
            Modifier.fillMaxSize().padding(horizontal = padH).padding(bottom = if (esTV) 40.dp else 20.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            if (enVivo) {
                Row(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFFF3B30))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(Color.White))
                    Spacer(Modifier.width(6.dp))
                    Text("EN VIVO", color = Color.White,
                        fontSize = if (esTV) 12.sp else 10.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 1.5.sp)
                }
                Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
            }

            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = tituloSize,
                fontWeight = FontWeight.Black,
                lineHeight = (tituloSize.value * 1.05f).sp,
                letterSpacing = (-0.5).sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = if (esTV) 700.dp else 500.dp)
            )
            Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐 ${evento.hora}",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esTV) 15.sp else 12.sp, fontWeight = FontWeight.Medium)
                Text("  ·  ", color = Color.White.copy(alpha = 0.4f), fontSize = if (esTV) 15.sp else 12.sp)
                Text(evento.groupTitle,
                    color = Color(0xFFFFD700),
                    fontSize = if (esTV) 15.sp else 12.sp, fontWeight = FontWeight.SemiBold)
                Text("  ·  ", color = Color.White.copy(alpha = 0.4f), fontSize = if (esTV) 15.sp else 12.sp)
                Text("📺 ${evento.embeds.size} canales",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esTV) 15.sp else 12.sp)
            }
            Spacer(Modifier.height(if (esTV) 20.dp else 14.dp))

            // CTA Button (blanco, Disney+ style)
            BotonHero(onClick, esTV, esMovil)
        }
    }
}

@Composable
private fun BotonHero(onClick: () -> Unit, esTV: Boolean, esMovil: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.05f else 1f, tween(150), label = "heroBtnScale")

    Row(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 10.dp else 8.dp))
            .background(if (focused) Color.White else Color.White.copy(alpha = 0.92f))
            .padding(
                horizontal = if (esTV) 26.dp else 18.dp,
                vertical = if (esTV) 12.dp else 9.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("▶", color = Color.Black, fontSize = if (esTV) 16.sp else 13.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
        Text(
            "Ver ahora",
            color = Color.Black,
            fontSize = if (esTV) 15.sp else 12.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.3.sp
        )
    }
}

// ═══════════════════════════════════════════════════════════
// SECTION HEADER (Disney+ style: simple, uppercase, claro)
// ═══════════════════════════════════════════════════════════

@Composable
private fun SectionHeader(titulo: String, icono: String, esTV: Boolean, esMovil: Boolean) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH, vertical = if (esTV) 12.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(icono, fontSize = if (esTV) 20.sp else 16.sp)
        Spacer(Modifier.width(if (esTV) 10.dp else 8.dp))
        Text(
            titulo,
            color = Color.White,
            fontSize = if (esTV) 24.sp else if (esMovil) 18.sp else 20.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp
        )
    }
}

// ═══════════════════════════════════════════════════════════
// FILA DE EVENTOS (Disney+ style: landscape cards 16:9)
// ═══════════════════════════════════════════════════════════

@Composable
private fun FilaEventosDisney(
    lista: List<Evento>,
    esTV: Boolean, esMovil: Boolean, esVertical: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val ancho = when {
        esTV -> 340.dp
        esMovil -> 200.dp
        esVertical -> 240.dp
        else -> 280.dp
    }
    val alto = when {
        esTV -> 190.dp
        esMovil -> 112.dp
        esVertical -> 135.dp
        else -> 158.dp
    }

    LazyRow(
        contentPadding = PaddingValues(horizontal = padH),
        horizontalArrangement = Arrangement.spacedBy(if (esTV) 16.dp else 10.dp)
    ) {
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
            Box(Modifier.fadeInOnLoad(350, delayMs = index * 40)) {
                CardEventoDisney(ev, ancho, alto, esTV, esMovil) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun CardEventoDisney(
    ev: Evento, ancho: Dp, alto: Dp,
    esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, tween(200), label = "cardScale")
    val borderColor by animateColorAsState(
        if (focused) Color.White else Color.Transparent,
        tween(150), label = "cardBorder"
    )
    val enVivo = estaEnVivo(ev)

    Box(
        Modifier
            .width(ancho)
            .height(alto)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 14.dp else 10.dp))
            .background(Color(0xFF1A1A22))
            .border(if (focused) 3.dp else 0.dp, borderColor, RoundedCornerShape(if (esTV) 14.dp else 10.dp))
    ) {
        // Imagen de fondo
        if (ev.imagen.isNotBlank()) {
            AsyncImage(
                model = ev.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Gradiente abajo para legibilidad
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.85f)
                    )
                )
            )
        )

        // Badge EN VIVO arriba
        if (enVivo) {
            Row(
                Modifier.align(Alignment.TopStart).padding(if (esTV) 10.dp else 8.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(Color(0xFFFF3B30))
                    .padding(horizontal = 7.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(Modifier.size(5.dp).clip(CircleShape).background(Color.White))
                Spacer(Modifier.width(4.dp))
                Text("LIVE", color = Color.White,
                    fontSize = if (esTV) 10.sp else 9.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
            }
        }

        // Hora arriba a la derecha
        Box(
            Modifier.align(Alignment.TopEnd).padding(if (esTV) 10.dp else 8.dp)
                .clip(RoundedCornerShape(5.dp))
                .background(Color.Black.copy(alpha = 0.65f))
                .padding(horizontal = 7.dp, vertical = 3.dp)
        ) {
            Text(ev.hora, color = Color.White,
                fontSize = if (esTV) 11.sp else 10.sp,
                fontWeight = FontWeight.Bold)
        }

        // Info abajo
        Column(
            Modifier.fillMaxSize().padding(if (esTV) 14.dp else 10.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = if (esTV) 15.sp else 12.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = if (esTV) 18.sp else 14.sp,
                overflow = TextOverflow.Ellipsis
            )
            if (esTV && ev.groupTitle.isNotBlank()) {
                Spacer(Modifier.height(3.dp))
                Text(
                    ev.groupTitle,
                    color = Color(0xFFFFD700),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: AGENDAS WEB
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoAgendas(
    eventos: List<Evento>, cargando: Boolean, mostrarScraping: Boolean,
    esTV: Boolean, esMovil: Boolean, esVertical: Boolean,
    status: String, onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp

    if (!mostrarScraping) { EmptyState(esMovil); return }
    if (cargando) { SkeletonHome(status); return }
    if (eventos.isEmpty()) { EmptyState(esMovil); return }

    val grupos = remember(eventos) { eventos.groupBy { it.groupTitle } }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 40.dp)) {
        item(key = "intro") {
            Spacer(Modifier.height(if (esTV) 24.dp else 16.dp))
            Text(
                "${eventos.size} eventos en vivo · scrapeado de la web",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = if (esTV) 14.sp else 12.sp,
                modifier = Modifier.padding(horizontal = padH)
            )
        }
        grupos.forEach { (titulo, lista) ->
            item(key = "h_$titulo") {
                SectionHeader(titulo.uppercase(), "🌐", esTV, esMovil)
            }
            item(key = "r_$titulo") {
                FilaEventosDisney(lista, esTV, esMovil, esVertical, onEventoClick)
                Spacer(Modifier.height(if (esTV) 32.dp else 20.dp))
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// SKELETON / EMPTY
// ═══════════════════════════════════════════════════════════

@Composable
private fun SkeletonHome(status: String) {
    val esTV = rememberEsTV()
    val padH = if (esTV) 44.dp else 16.dp
    Column(Modifier.fillMaxSize().padding(top = if (esTV) 20.dp else 14.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = padH), verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = if (esTV) 28.sp else 22.sp)
            Spacer(Modifier.width(8.dp))
            Text("FutTV", color = Color(0xFFFFD700),
                fontSize = if (esTV) 28.sp else 22.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.width(14.dp))
            Text(status, color = Color.White.copy(alpha = 0.5f), fontSize = 12.sp)
        }
        Spacer(Modifier.height(24.dp))
        Box(Modifier.fillMaxWidth().height(if (esTV) 400.dp else 260.dp).shimmer(RoundedCornerShape(0.dp)))
        Spacer(Modifier.height(24.dp))
        repeat(2) {
            Box(Modifier.padding(horizontal = padH).width(200.dp).height(24.dp).shimmer(RoundedCornerShape(6.dp)))
            Spacer(Modifier.height(14.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(16.dp), userScrollEnabled = false) {
                repeat(4) { item { Box(Modifier.width(if (esTV) 340.dp else 240.dp).height(if (esTV) 190.dp else 135.dp).shimmer(RoundedCornerShape(14.dp))) } }
            }
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun EmptyState(esMovil: Boolean) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("📭", fontSize = if (esMovil) 60.sp else 72.sp)
            Spacer(Modifier.height(16.dp))
            Text("Sin eventos", color = Color.White, fontSize = if (esMovil) 18.sp else 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text("Cargá eventos desde el panel", color = Color.White.copy(alpha = 0.5f), fontSize = 13.sp)
        }
    }
}
KOTLIN_EOF

echo "✅ HomeScreen.kt reescrito Disney+"

# ═══════════════════════════════════════════════════════════
# EVENT DETAIL — Disney+ Grid
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
cp "$DETAIL" "${DETAIL}.bak.disney.$(date +%s)"
echo "✅ Backup Detail"

cat > "$DETAIL" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
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
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.rememberEsTV
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

// ═══════════════════════════════════════════════════════════
// ESTADO
// ═══════════════════════════════════════════════════════════

enum class EstadoEvento { PROXIMO, EN_VIVO, FINALIZADO }

private fun calcularEstado(ev: Evento): EstadoEvento {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val fechaEv = sdf.parse(ev.fecha) ?: return EstadoEvento.PROXIMO
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoy = cal.timeInMillis
        cal.time = fechaEv
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val diff = ((cal.timeInMillis - hoy) / (1000L * 60L * 60L * 24L)).toInt()
        if (diff > 0) return EstadoEvento.PROXIMO
        if (diff < 0) return EstadoEvento.FINALIZADO
        val ahora = Calendar.getInstance()
        val minAct = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val m = Regex("""(\d{1,2}):(\d{2})""").find(ev.hora)
        val minEv = m?.let { (it.groupValues[1].toIntOrNull() ?: 0) * 60 + (it.groupValues[2].toIntOrNull() ?: 0) } ?: 0
        when {
            minAct < minEv -> EstadoEvento.PROXIMO
            minAct < minEv + ev.duracionMinutos -> EstadoEvento.EN_VIVO
            else -> EstadoEvento.FINALIZADO
        }
    } catch (e: Exception) { EstadoEvento.PROXIMO }
}

private fun minutosHasta(ev: Evento): Int? {
    return try {
        val ahora = Calendar.getInstance()
        val minAct = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val m = Regex("""(\d{1,2}):(\d{2})""").find(ev.hora) ?: return null
        val minEv = (m.groupValues[1].toIntOrNull() ?: 0) * 60 + (m.groupValues[2].toIntOrNull() ?: 0)
        if (minEv > minAct) minEv - minAct else null
    } catch (e: Exception) { null }
}

// ═══════════════════════════════════════════════════════════
// VIDEO EN BUCLE
// ═══════════════════════════════════════════════════════════

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
    DisposableEffect(url) { onDispose { exoPlayer.release() } }
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

// ═══════════════════════════════════════════════════════════
// PANTALLA
// ═══════════════════════════════════════════════════════════

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
    val estado = remember(evento) { calcularEstado(evento) }
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp

    Box(Modifier.fillMaxSize().background(Color(0xFF0A0A0F))) {
        Column(Modifier.fillMaxSize()) {
            // Top bar con botón volver
            Row(
                Modifier.fillMaxWidth().padding(horizontal = padH, vertical = if (esTV) 18.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BotonVolverCompact(onBack, esTV)
            }

            // Hero con imagen del evento (más chico, Disney+ style)
            HeroEvento(evento, esTV, esMovil, estado, minutosHasta(evento))

            Spacer(Modifier.height(if (esTV) 24.dp else 16.dp))

            // Contenido según estado
            when (estado) {
                EstadoEvento.EN_VIVO -> {
                    SeccionCanales(evento, esTV, esMovil, esVertical, onCanalClick)
                }
                EstadoEvento.FINALIZADO -> {
                    SeccionVideoEstado(evento, esTV, esMovil, esFinalizado = true)
                }
                EstadoEvento.PROXIMO -> {
                    SeccionVideoEstado(evento, esTV, esMovil, esFinalizado = false)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// BOTÓN VOLVER (compact)
// ═══════════════════════════════════════════════════════════

@Composable
private fun BotonVolverCompact(onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.05f else 1f, tween(150), label = "vbScale")

    Row(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(CircleShape)
            .background(if (focused) Color.White.copy(alpha = 0.2f) else Color.Transparent)
            .padding(horizontal = if (esTV) 14.dp else 10.dp, vertical = if (esTV) 8.dp else 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = Color.White,
            modifier = Modifier.size(if (esTV) 22.dp else 18.dp)
        )
        Spacer(Modifier.width(if (esTV) 8.dp else 6.dp))
        Text(
            "Volver",
            color = Color.White,
            fontSize = if (esTV) 15.sp else 13.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

// ═══════════════════════════════════════════════════════════
// HERO (más chico, horizontal, Disney+ style)
// ═══════════════════════════════════════════════════════════

@Composable
private fun HeroEvento(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    estado: EstadoEvento, minsHasta: Int?
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val altura = if (esTV) 260.dp else if (esMovil) 160.dp else 200.dp
    val tituloSize = if (esTV) 36.sp else if (esMovil) 22.sp else 28.sp

    Box(Modifier.fillMaxWidth().height(altura)) {
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen, contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.5f)
            )
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    listOf(
                        Color(0xFF0A0A0F),
                        Color(0xFF0A0A0F).copy(alpha = 0.85f),
                        Color(0xFF0A0A0F).copy(alpha = 0.4f),
                        Color.Transparent
                    )
                )
            )
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(listOf(Color.Transparent, Color(0xFF0A0A0F)))
            )
        )

        Column(
            Modifier.fillMaxSize().padding(horizontal = padH).padding(bottom = if (esTV) 24.dp else 16.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            // Badges
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (estado) {
                    EstadoEvento.EN_VIVO -> BadgeEstado("● EN VIVO", Color(0xFFFF3B30), Color.White, esTV)
                    EstadoEvento.FINALIZADO -> BadgeEstado("✓ FINALIZADO", Color.White.copy(alpha = 0.15f), Color.White, esTV)
                    EstadoEvento.PROXIMO -> {
                        if (minsHasta != null && minsHasta <= 60) {
                            BadgeEstado("⏰ EN ${minsHasta}MIN", Color(0xFFFFA500), Color.Black, esTV)
                        } else {
                            BadgeEstado("🕐 PRÓXIMO", Color(0xFFFFD700), Color.Black, esTV)
                        }
                    }
                }
                BadgeEstado(evento.groupTitle, Color.White.copy(alpha = 0.15f), Color.White, esTV)
            }
            Spacer(Modifier.height(if (esTV) 14.dp else 10.dp))
            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = tituloSize,
                fontWeight = FontWeight.Black,
                lineHeight = (tituloSize.value * 1.05f).sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                letterSpacing = (-0.4).sp
            )
            Spacer(Modifier.height(if (esTV) 10.dp else 6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐 ${evento.hora}",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esTV) 14.sp else 12.sp, fontWeight = FontWeight.Medium)
                Text("  ·  ", color = Color.White.copy(alpha = 0.4f), fontSize = if (esTV) 14.sp else 12.sp)
                Text("📅 ${evento.fecha}",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = if (esTV) 14.sp else 12.sp)
            }
        }
    }
}

@Composable
private fun BadgeEstado(texto: String, bg: Color, fg: Color, esTV: Boolean) {
    Box(
        Modifier.clip(RoundedCornerShape(6.dp)).background(bg)
            .padding(horizontal = if (esTV) 12.dp else 9.dp, vertical = if (esTV) 5.dp else 4.dp)
    ) {
        Text(texto, color = fg,
            fontSize = if (esTV) 12.sp else 10.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.8.sp,
            maxLines = 1)
    }
}

// ═══════════════════════════════════════════════════════════
// SECCIÓN CANALES (GRID Disney+ style)
// ═══════════════════════════════════════════════════════════

@Composable
private fun SeccionCanales(
    evento: Evento, esTV: Boolean, esMovil: Boolean, esVertical: Boolean,
    onCanalClick: (Embed) -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val columnas = when {
        esTV -> 4
        esMovil -> 1
        esVertical -> 2
        else -> 3
    }

    Column(Modifier.fillMaxSize()) {
        // Header
        Row(
            Modifier.fillMaxWidth().padding(horizontal = padH, vertical = if (esTV) 10.dp else 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("📺", fontSize = if (esTV) 20.sp else 16.sp)
            Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
            Text(
                "Elegí un canal",
                color = Color.White,
                fontSize = if (esTV) 22.sp else 16.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.width(10.dp))
            Box(
                Modifier.clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFFFFD700).copy(alpha = 0.2f))
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            ) {
                Text("${evento.embeds.size}",
                    color = Color(0xFFFFD700),
                    fontSize = if (esTV) 12.sp else 10.sp,
                    fontWeight = FontWeight.Black)
            }
        }
        Spacer(Modifier.height(if (esTV) 14.dp else 8.dp))

        LazyVerticalGrid(
            columns = GridCells.Fixed(columnas),
            contentPadding = PaddingValues(horizontal = padH, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(if (esTV) 16.dp else 10.dp),
            verticalArrangement = Arrangement.spacedBy(if (esTV) 16.dp else 10.dp),
            modifier = Modifier.fillMaxSize()
        ) {
            itemsIndexed(
                items = evento.embeds,
                key = { idx, it -> "ch_${idx}_${it.url}" }
            ) { index, embed ->
                Box(Modifier.fadeInOnLoad(350, delayMs = index * 40)) {
                    CanalCardDisney(embed, index + 1, evento.imagen, esTV, esMovil) { onCanalClick(embed) }
                }
            }
        }
    }
}

@Composable
private fun CanalCardDisney(
    embed: Embed, indice: Int, imagenEvento: String,
    esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, tween(200), label = "chScale")
    val borderColor by animateColorAsState(
        if (focused) Color.White else Color.Transparent,
        tween(150), label = "chBorder"
    )
    val altura = if (esTV) 180.dp else if (esMovil) 130.dp else 160.dp

    Box(
        Modifier
            .fillMaxWidth()
            .height(altura)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 14.dp else 10.dp))
            .background(Color(0xFF1A1A22))
            .border(if (focused) 3.dp else 0.dp, borderColor, RoundedCornerShape(if (esTV) 14.dp else 10.dp))
    ) {
        // Imagen de fondo
        if (imagenEvento.isNotBlank()) {
            AsyncImage(
                model = imagenEvento, contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.4f)
            )
        }
        // Gradiente
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                )
            )
        )

        // Número del canal arriba
        Box(
            Modifier.align(Alignment.TopStart).padding(if (esTV) 10.dp else 8.dp)
                .size(if (esTV) 32.dp else 26.dp)
                .clip(CircleShape)
                .background(if (focused) Color.White else Color(0xFFFFD700)),
            contentAlignment = Alignment.Center
        ) {
            Text("$indice", color = Color.Black,
                fontSize = if (esTV) 15.sp else 12.sp,
                fontWeight = FontWeight.Black)
        }

        // Play icon flotante arriba derecha (solo cuando focused)
        if (focused) {
            Box(
                Modifier.align(Alignment.TopEnd).padding(if (esTV) 10.dp else 8.dp)
                    .size(if (esTV) 32.dp else 26.dp)
                    .clip(CircleShape)
                    .background(Color.White),
                contentAlignment = Alignment.Center
            ) {
                Text("▶", color = Color.Black,
                    fontSize = if (esTV) 14.sp else 11.sp,
                    fontWeight = FontWeight.Black)
            }
        }

        // Nombre abajo
        Column(
            Modifier.fillMaxSize().padding(if (esTV) 12.dp else 8.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Text(
                embed.nombre,
                color = Color.White,
                fontSize = if (esTV) 15.sp else 12.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = if (esTV) 18.sp else 14.sp,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// SECCIÓN PRÓXIMO / FINALIZADO
// ═══════════════════════════════════════════════════════════

@Composable
private fun SeccionVideoEstado(
    evento: Evento, esTV: Boolean, esMovil: Boolean, esFinalizado: Boolean
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val altura = if (esTV) 380.dp else if (esMovil) 220.dp else 300.dp
    val video = if (esFinalizado) evento.videoFinalizado else evento.videoProximo

    Box(
        Modifier.fillMaxSize().padding(horizontal = padH),
        contentAlignment = Alignment.TopCenter
    ) {
        Box(
            Modifier.fillMaxWidth().height(altura)
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF1A1A22))
        ) {
            if (video.isNotBlank()) {
                VideoLoopPlayer(video, Modifier.fillMaxSize())
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(
                            listOf(
                                Color.Transparent,
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.85f)
                            )
                        )
                    )
                )
                Column(
                    Modifier.fillMaxSize().padding(if (esTV) 32.dp else 20.dp),
                    verticalArrangement = Arrangement.Bottom
                ) {
                    IconEstado(esFinalizado, esTV)
                    Spacer(Modifier.height(if (esTV) 16.dp else 10.dp))
                    Text(
                        if (esFinalizado) "Evento finalizado" else "El evento está por comenzar",
                        color = Color.White,
                        fontSize = if (esTV) 26.sp else 18.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = (-0.3).sp
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        if (esFinalizado) "Gracias por ver FutTV"
                        else "Los canales aparecerán cuando empiece",
                        color = Color.White.copy(alpha = 0.75f),
                        fontSize = if (esTV) 15.sp else 12.sp
                    )
                }
            } else {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    IconEstado(esFinalizado, esTV)
                    Spacer(Modifier.height(if (esTV) 20.dp else 14.dp))
                    Text(
                        if (esFinalizado) "Evento finalizado" else "El evento está por comenzar",
                        color = Color.White,
                        fontSize = if (esTV) 24.sp else 18.sp,
                        fontWeight = FontWeight.Black
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        if (esFinalizado) "Gracias por ver FutTV"
                        else "Volvé cuando empiece",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = if (esTV) 14.sp else 12.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun IconEstado(esFinalizado: Boolean, esTV: Boolean) {
    Box(
        Modifier.size(if (esTV) 64.dp else 48.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.1f))
            .border(1.5.dp, Color(0xFFFFD700).copy(alpha = 0.4f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            if (esFinalizado) "✓" else "⏰",
            fontSize = if (esTV) 28.sp else 22.sp,
            color = Color(0xFFFFD700),
            fontWeight = FontWeight.Black
        )
    }
}
KOTLIN_EOF

echo "✅ EventDetailScreen.kt reescrito Disney+"
echo ""
echo "✅✅✅ Disney+ Home + Detail completos"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
