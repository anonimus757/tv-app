#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
[ ! -f "$HOME" ] && { echo "❌ No existe $HOME"; exit 1; }
cp "$HOME" "${HOME}.bak.v3.$(date +%s)"
echo "✅ Backup: ${HOME}.bak.v3.$(date +%s)"

cat > "$HOME" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.ui.graphics.graphicsLayer
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
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

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

private fun minutosHastaEvento(ev: Evento): Int? {
    return try {
        if (ev.fecha != FechaHelper.hoy()) return null
        val ahora = Calendar.getInstance()
        val minActual = ahora.get(Calendar.HOUR_OF_DAY) * 60 + ahora.get(Calendar.MINUTE)
        val minEvento = horaAMinutos(ev.hora)
        if (minEvento == Int.MAX_VALUE) return null
        if (minEvento > minActual) minEvento - minActual else null
    } catch (e: Exception) { null }
}

private fun diaOffset(fechaStr: String): Int? {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(fechaStr) ?: return null
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        ((cal.timeInMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()
    } catch (e: Exception) { null }
}

private fun labelDia(fechaStr: String): String {
    val offset = diaOffset(fechaStr) ?: return "—"
    return when (offset) {
        0 -> "HOY"
        1 -> "MAÑANA"
        2 -> "PASADO"
        in 3..7 -> {
            try {
                val sdfIn = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                val sdfOut = SimpleDateFormat("EEE d", Locale("es", "ES"))
                sdfOut.format(sdfIn.parse(fechaStr)!!).uppercase().replace(".", "")
            } catch (e: Exception) { "DÍA $offset" }
        }
        else -> {
            try {
                val sdfIn = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                val sdfOut = SimpleDateFormat("d MMM", Locale("es", "ES"))
                sdfOut.format(sdfIn.parse(fechaStr)!!).uppercase().replace(".", "")
            } catch (e: Exception) { fechaStr }
        }
    }
}

private fun agruparPorFecha(eventos: List<Evento>): List<Pair<String, List<Evento>>> {
    val porFecha = mutableMapOf<String, MutableList<Evento>>()
    eventos.forEach { ev ->
        if (ev.fecha.isBlank()) return@forEach
        val offset = diaOffset(ev.fecha) ?: return@forEach
        if (offset < 0) return@forEach
        porFecha.getOrPut(ev.fecha) { mutableListOf() }.add(ev)
    }
    porFecha.values.forEach { it.sortBy { e -> horaAMinutos(e.hora) } }
    return porFecha.entries
        .sortedBy { it.key }
        .map { it.key to it.value }
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

    Box(Modifier.fillMaxSize().background(Color(0xFF050505))) {
        // Fondo animado premium (orbes dorados flotando)
        FondoAnimadoPremium()

        if (cargando) {
            SkeletonPremium(status)
        } else {
            Column(Modifier.fillMaxSize()) {
                Spacer(Modifier.height(if (esMovil) 14.dp else 26.dp))
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

                Spacer(Modifier.height(if (esMovil) 16.dp else 24.dp))
                TabPrincipal(tabPrincipal, { tabPrincipal = it }, esMovil)
                Spacer(Modifier.height(8.dp))

                when (tabPrincipal) {
                    0 -> ContenidoMisEventos(eventosFirebase, esTV, esVertical, esMovil, onEventoClick)
                    1 -> ContenidoAgendas(eventosScraping, cargandoScraping, config.mostrarScraping, esTV, esVertical, esMovil, status, onEventoClick)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// FONDO ANIMADO PREMIUM (orbes dorados flotando)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun FondoAnimadoPremium() {
    val transition = rememberInfiniteTransition(label = "fondo")
    val fase by transition.animateFloat(
        initialValue = 0f,
        targetValue = (2 * PI).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(20000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "fase"
    )

    Box(Modifier.fillMaxSize()) {
        // Orbe 1 (arriba izquierda, dorado)
        val x1 = sin(fase) * 80f
        val y1 = sin(fase * 0.7f) * 60f
        Box(
            Modifier
                .graphicsLayer { translationX = x1; translationY = y1 }
                .size(340.dp)
                .offset(x = (-120).dp, y = (-80).dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            AppColors.Gold.copy(alpha = 0.12f),
                            Color.Transparent
                        )
                    )
                )
        )

        // Orbe 2 (abajo derecha, dorado)
        val x2 = sin(fase * 1.3f + 1f) * 100f
        val y2 = sin(fase * 0.9f + 2f) * 80f
        Box(
            Modifier
                .graphicsLayer { translationX = x2; translationY = y2 }
                .size(400.dp)
                .offset(x = 150.dp, y = 350.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            AppColors.Gold.copy(alpha = 0.08f),
                            Color.Transparent
                        )
                    )
                )
        )

        // Orbe 3 (centro, morado sutil)
        val x3 = sin(fase * 0.5f) * 60f
        Box(
            Modifier
                .graphicsLayer { translationX = x3 }
                .size(280.dp)
                .offset(x = 200.dp, y = 100.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color(0xFF7B5CFF).copy(alpha = 0.06f),
                            Color.Transparent
                        )
                    )
                )
        )
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
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 1400)
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
                .background(
                    Brush.horizontalGradient(
                        listOf(Color(0xFFFF3B30), Color(0xFFFF6B5D))
                    )
                )
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

    Spacer(Modifier.height(8.dp))
    Text(
        "$totalEventos eventos · $totalCanales canales",
        color = AppColors.TextSecondary,
        fontSize = if (esMovil) 11.sp else 13.sp,
        modifier = Modifier.padding(horizontal = padH),
        maxLines = 1, overflow = TextOverflow.Ellipsis
    )
}

@Composable
private fun GlassIconButton(icono: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.12f else 1f, tween(180), label = "glassScale")
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
// TAB PRINCIPAL (Mis Eventos / Agendas)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun TabPrincipal(seleccionado: Int, onSeleccion: (Int) -> Unit, esMovil: Boolean) {
    val padH = if (esMovil) 16.dp else 48.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        TabPill("🎯 Mis Eventos", seleccionado == 0, { onSeleccion(0) }, Modifier.weight(1f), esMovil)
        TabPill("🌐 Agendas", seleccionado == 1, { onSeleccion(1) }, Modifier.weight(1f), esMovil)
    }
}

@Composable
private fun TabPill(titulo: String, activo: Boolean, onClick: () -> Unit, modifier: Modifier, esMovil: Boolean) {
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
// CONTENIDO: MIS EVENTOS (con tabs de fecha horizontales)
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

    val enVivo = remember(eventos) { eventos.filter { estaEnVivo(it) }.sortedBy { horaAMinutos(it.hora) } }
    val porFecha = remember(eventos) { agruparPorFecha(eventos) }

    // Lista de fechas disponibles (con hoy primero, o en vivo primero)
    val fechasDisponibles = remember(porFecha, enVivo) {
        val lista = mutableListOf<Pair<String, String>>() // (fechaYYYY-MM-DD, label)
        if (enVivo.isNotEmpty()) lista.add("__LIVE__" to "EN VIVO")
        porFecha.forEach { (fecha, _) -> lista.add(fecha to labelDia(fecha)) }
        lista
    }

    // Selección inicial: EN VIVO si hay, sino primer día
    var seleccionado by remember(fechasDisponibles) {
        mutableStateOf(fechasDisponibles.firstOrNull()?.first ?: "")
    }

    // Eventos del filtro seleccionado
    val eventosFiltrados = remember(seleccionado, enVivo, porFecha) {
        when (seleccionado) {
            "__LIVE__" -> enVivo
            else -> porFecha.firstOrNull { it.first == seleccionado }?.second ?: emptyList()
        }
    }

    val destacado = remember(eventosFiltrados) { eventosFiltrados.firstOrNull() }
    val listState = rememberLazyListState()

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 4.dp, bottom = 60.dp)
    ) {
        // ─── Tabs de fecha (horizontal scroll) ───
        item(key = "date_tabs") {
            DateTabsSelector(
                fechas = fechasDisponibles,
                seleccionado = seleccionado,
                onSeleccion = { seleccionado = it },
                esMovil = esMovil,
                conteoPorFecha = { fecha ->
                    if (fecha == "__LIVE__") enVivo.size
                    else porFecha.firstOrNull { it.first == fecha }?.second?.size ?: 0
                }
            )
            Spacer(Modifier.height(if (esMovil) 16.dp else 22.dp))
        }

        // ─── Hero (solo para el primer evento del filtro, si no es EN VIVO) ───
        if (destacado != null && seleccionado != "__LIVE__") {
            item(key = "hero_$seleccionado") {
                HeroPremium(
                    destacado, esTV, esMovil,
                    enVivo = false,
                    minutosHasta = minutosHastaEvento(destacado)
                ) { onEventoClick(destacado, eventosFiltrados) }
                Spacer(Modifier.height(if (esMovil) 22.dp else 30.dp))
            }
        }

        // ─── Si estamos en EN VIVO, mostramos todas las cards grandes ───
        if (seleccionado == "__LIVE__") {
            itemsIndexed(
                items = eventosFiltrados,
                key = { _, it -> "live_${it.fuente}_${it.hora}_${it.descripcion}" }
            ) { index, ev ->
                Box(Modifier.fadeInOnLoad(450, delayMs = index * 60)) {
                    LiveCardGrande(ev, esTV, esMovil) { onEventoClick(ev, eventosFiltrados) }
                }
                Spacer(Modifier.height(14.dp))
            }
        } else if (destacado != null) {
            // ─── El resto de eventos del día (cards chicas) ───
            val resto = eventosFiltrados.drop(1)
            if (resto.isNotEmpty()) {
                item(key = "header_resto_$seleccionado") {
                    RowSubtitulo("TAMBIÉN HOY", resto.size, AppColors.TextSecondary, esMovil)
                }
                item(key = "fila_resto_$seleccionado") {
                    FilaEventos(resto, onEventoClick, esTV, esVertical, esMovil)
                }
            } else {
                item(key = "unico") {
                    Box(Modifier.fillMaxWidth().padding(horizontal = if (esMovil) 16.dp else 48.dp)) {
                        Text(
                            "Ese es el único evento de este día",
                            color = AppColors.TextSecondary,
                            fontSize = if (esMovil) 12.sp else 14.sp
                        )
                    }
                }
            }
        } else {
            item(key = "vacio_$seleccionado") {
                EmptyPremiumInline("📅", "Sin eventos este día", esMovil)
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

// ═══════════════════════════════════════════════════════════════
// DATE TABS (horizontal scroll)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun DateTabsSelector(
    fechas: List<Pair<String, String>>,
    seleccionado: String,
    onSeleccion: (String) -> Unit,
    esMovil: Boolean,
    conteoPorFecha: (String) -> Int
) {
    val padH = if (esMovil) 16.dp else 48.dp
    LazyRow(
        contentPadding = PaddingValues(horizontal = padH),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        itemsIndexed(
            items = fechas,
            key = { _, it -> "date_${it.first}" }
        ) { index, (fecha, label) ->
            val activo = fecha == seleccionado
            val conteo = conteoPorFecha(fecha)
            val esLive = fecha == "__LIVE__"

            Box(Modifier.fadeInOnLoad(300, delayMs = index * 30)) {
                DatePill(
                    label = label,
                    conteo = conteo,
                    activo = activo,
                    esLive = esLive,
                    onClick = { onSeleccion(fecha) },
                    esMovil = esMovil
                )
            }
        }
    }
}

@Composable
private fun DatePill(
    label: String, conteo: Int, activo: Boolean, esLive: Boolean,
    onClick: () -> Unit, esMovil: Boolean
) {
    var focused by remember { mutableStateOf(false) }

    val bg = when {
        esLive && activo -> Brush.horizontalGradient(listOf(Color(0xFFFF3B30), Color(0xFFFF6B5D)))
        esLive -> Brush.horizontalGradient(listOf(Color(0xFFFF3B30).copy(alpha = 0.4f), Color(0xFFFF6B5D).copy(alpha = 0.3f)))
        activo -> Brush.horizontalGradient(listOf(AppColors.Gold, AppColors.GoldBright))
        focused -> Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0.15f), Color.White.copy(alpha = 0.08f)))
        else -> Brush.horizontalGradient(listOf(Color.White.copy(alpha = 0.06f), Color.White.copy(alpha = 0.03f)))
    }

    val textColor = when {
        esLive && activo -> Color.White
        esLive -> Color(0xFFFFB0AA)
        activo -> Color.Black
        focused -> AppColors.GoldBright
        else -> AppColors.TextSecondary
    }

    val borderColor = when {
        esLive -> Color(0xFFFF3B30).copy(alpha = 0.6f)
        activo -> AppColors.GoldBright
        focused -> AppColors.Gold
        else -> Color.White.copy(alpha = 0.08f)
    }

    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(20.dp))
            .background(bg)
            .border(if (focused) 2.dp else 1.dp, borderColor, RoundedCornerShape(20.dp))
            .padding(horizontal = if (esMovil) 14.dp else 18.dp, vertical = if (esMovil) 9.dp else 11.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (esLive) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(if (activo) Color.White else Color(0xFFFF3B30)))
            Spacer(Modifier.width(6.dp))
        }
        Text(
            label,
            color = textColor,
            fontSize = if (esMovil) 12.sp else 14.sp,
            fontWeight = if (activo || esLive) FontWeight.Black else FontWeight.Bold,
            letterSpacing = 0.5.sp,
            maxLines = 1
        )
        if (conteo > 0) {
            Spacer(Modifier.width(6.dp))
            Box(
                Modifier.clip(RoundedCornerShape(8.dp))
                    .background(
                        if (activo && !esLive) Color.Black.copy(alpha = 0.25f)
                        else Color.White.copy(alpha = 0.15f)
                    )
                    .padding(horizontal = 6.dp, vertical = 1.dp)
            ) {
                Text(
                    "$conteo",
                    color = if (activo && !esLive) Color.Black.copy(alpha = 0.7f) else textColor,
                    fontSize = if (esMovil) 10.sp else 11.sp,
                    fontWeight = FontWeight.Black
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// HERO PREMIUM con countdown / en vivo
// ═══════════════════════════════════════════════════════════════

@Composable
private fun HeroPremium(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    enVivo: Boolean, minutosHasta: Int?,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.015f else 1f, tween(250), label = "heroScale")
    val padH = if (esMovil) 16.dp else 48.dp
    val altura = if (esTV) 320.dp else if (esMovil) 260.dp else 300.dp

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
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen, contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }

        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    listOf(
                        Color.Transparent,
                        Color(0xFF050505).copy(alpha = 0.5f),
                        Color(0xFF050505).copy(alpha = 0.98f)
                    )
                )
            )
        )

        Column(
            Modifier.fillMaxSize().padding(if (esMovil) 20.dp else 30.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (enVivo) {
                    LiveBadge()
                } else if (minutosHasta != null && minutosHasta <= 60) {
                    CountdownBadge(minutosHasta)
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
                fontSize = if (esTV) 38.sp else if (esMovil) 24.sp else 30.sp,
                fontWeight = FontWeight.Black,
                lineHeight = (if (esTV) 42.sp else if (esMovil) 28.sp else 34.sp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                letterSpacing = (-0.5).sp
            )
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                MetaChip("🕐 ${evento.hora}", esMovil)
                MetaChip("📅 ${evento.fecha}", esMovil)
                MetaChip("📺 ${evento.embeds.size}", esMovil)
            }
            Spacer(Modifier.height(18.dp))
            Box(
                Modifier.clip(RoundedCornerShape(12.dp))
                    .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                    .padding(horizontal = 22.dp, vertical = 12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("▶", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (enVivo) "VER AHORA" else "VER DETALLES",
                        color = Color.Black, fontSize = 14.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 1.sp
                    )
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
private fun CountdownBadge(minutos: Int) {
    Box(
        Modifier.clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFFA500), Color(0xFFFFC040))))
            .padding(horizontal = 12.dp, vertical = 5.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⏰", fontSize = 11.sp)
            Spacer(Modifier.width(6.dp))
            Text(
                "EN ${minutos}MIN",
                color = Color.Black, fontSize = 11.sp,
                fontWeight = FontWeight.Black, letterSpacing = 0.5.sp
            )
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
// LIVE CARD GRANDE (para sección EN VIVO)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun LiveCardGrande(
    ev: Evento, esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.02f else 1f, tween(200), label = "liveScale")
    val padH = if (esMovil) 16.dp else 48.dp
    val altura = if (esTV) 180.dp else if (esMovil) 130.dp else 160.dp

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = padH)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFF0D0D12))
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else Color(0xFFFF3B30).copy(alpha = 0.6f),
                RoundedCornerShape(20.dp)
            )
            .padding(if (esMovil) 12.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Imagen
        Box(
            Modifier.size(if (esMovil) 100.dp else 140.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen, contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Text("⚽", fontSize = if (esMovil) 40.sp else 56.sp)
            }
            Box(
                Modifier.align(Alignment.TopStart).padding(6.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFFFF3B30))
                    .padding(horizontal = 7.dp, vertical = 3.dp)
            ) {
                Text("● LIVE", color = Color.White, fontSize = 9.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
            }
        }
        Spacer(Modifier.width(if (esMovil) 12.dp else 18.dp))
        Column(Modifier.weight(1f)) {
            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = if (esMovil) 15.sp else 19.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = (if (esMovil) 18.sp else 23.sp),
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("🕐 ${ev.hora}", color = AppColors.GoldBright,
                    fontSize = if (esMovil) 11.sp else 13.sp, fontWeight = FontWeight.Bold)
                Text("📺 ${ev.embeds.size}", color = AppColors.TextSecondary,
                    fontSize = if (esMovil) 11.sp else 13.sp)
            }
            Spacer(Modifier.height(10.dp))
            Box(
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(AppColors.Gold)
                    .padding(horizontal = if (esMovil) 12.dp else 16.dp, vertical = if (esMovil) 7.dp else 9.dp)
            ) {
                Text("▶ VER", color = Color.Black,
                    fontSize = if (esMovil) 11.sp else 13.sp, fontWeight = FontWeight.Black, letterSpacing = 0.5.sp)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// FILA + CARD PREMIUM
// ═══════════════════════════════════════════════════════════════

@Composable
private fun RowSubtitulo(titulo: String, count: Int, color: Color, esMovil: Boolean) {
    val padH = if (esMovil) 16.dp else 48.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH, vertical = 8.dp).fadeInOnLoad(400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(3.dp).height(if (esMovil) 18.dp else 22.dp)
            .clip(RoundedCornerShape(2.dp)).background(color))
        Spacer(Modifier.width(10.dp))
        Text(
            titulo, color = AppColors.TextSecondary,
            fontSize = if (esMovil) 12.sp else 14.sp,
            fontWeight = FontWeight.Black, letterSpacing = 1.sp
        )
        Spacer(Modifier.width(8.dp))
        Box(
            Modifier.clip(RoundedCornerShape(8.dp))
                .background(color.copy(alpha = 0.2f))
                .padding(horizontal = 7.dp, vertical = 1.dp)
        ) {
            Text("$count", color = color, fontSize = 10.sp, fontWeight = FontWeight.Black)
        }
    }
}

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    esTV: Boolean, esVertical: Boolean, esMovil: Boolean
) {
    val ancho = anchoCard(esTV, esVertical)
    val padH = if (esMovil) 16.dp else 48.dp
    LazyRow(
        contentPadding = PaddingValues(horizontal = padH, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
            Box(Modifier.fadeInOnLoad(450, delayMs = 80 + index * 50)) {
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
    val altura = if (esTV) 200.dp else if (esMovil) 130.dp else 170.dp

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
                if (focused) AppColors.GoldBright else Color.White.copy(alpha = 0.08f),
                RoundedCornerShape(18.dp)
            )
    ) {
        Column {
            Box(
                Modifier.fillMaxWidth().height(altura).background(
                    Brush.verticalGradient(listOf(Color(0xFF1A1A22), Color(0xFF0D0D12)))
                )
            ) {
                if (ev.imagen.isNotBlank()) {
                    AsyncImage(
                        model = ev.imagen, contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().alpha(0.85f)
                    )
                } else {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("⚽", fontSize = if (esMovil) 36.sp else 50.sp, color = Color.White.copy(alpha = 0.4f))
                    }
                }
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f))
                        )
                    )
                )
                Box(
                    Modifier.align(Alignment.TopEnd).padding(8.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.7f))
                        .padding(horizontal = 7.dp, vertical = 3.dp)
                ) {
                    Text(ev.hora, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                }
            }
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
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Text("${ev.embeds.size} 📺", color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 9.sp else 10.sp)
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
    if (!mostrarScraping) { EmptyPremium("🌐", "Agendas deshabilitadas", "El panel desactivó el scraping", esMovil); return }
    if (cargando) { SkeletonPremium(status); return }
    if (eventos.isEmpty()) { EmptyPremium("🌐", "Sin agendas disponibles", "Probá de nuevo en unos minutos", esMovil); return }

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
        }
        grupos.forEach { (titulo, lista) ->
            item(key = "head_$titulo") {
                RowSubtitulo(
                    titulo = "${AppColors.fuenteIcono(titulo)} ${titulo.uppercase()}",
                    count = lista.size,
                    color = AppColors.fuenteColor(titulo),
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
        LazyRow(contentPadding = PaddingValues(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(10.dp), userScrollEnabled = false) {
            repeat(5) { item { Box(Modifier.width(if (esMovil) 80.dp else 100.dp).height(42.dp).shimmer(RoundedCornerShape(20.dp))) } }
        }
        Spacer(Modifier.height(22.dp))
        Box(Modifier.fillMaxWidth().padding(horizontal = padH).height(if (esMovil) 260.dp else 320.dp).shimmer(RoundedCornerShape(24.dp)))
        Spacer(Modifier.height(24.dp))
        repeat(2) {
            Box(Modifier.padding(horizontal = padH).width(150.dp).height(20.dp).shimmer(RoundedCornerShape(8.dp)))
            Spacer(Modifier.height(12.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(14.dp), userScrollEnabled = false) {
                repeat(4) { item { Box(Modifier.width(if (esMovil) 170.dp else 320.dp).height(if (esMovil) 220.dp else 260.dp).shimmer(RoundedCornerShape(18.dp))) } }
            }
            Spacer(Modifier.height(24.dp))
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

@Composable
private fun EmptyPremiumInline(emoji: String, mensaje: String, esMovil: Boolean) {
    Box(
        Modifier.fillMaxWidth().padding(horizontal = if (esMovil) 16.dp else 48.dp, vertical = 40.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(emoji, fontSize = 40.sp)
            Spacer(Modifier.height(10.dp))
            Text(mensaje, color = AppColors.TextSecondary, fontSize = if (esMovil) 13.sp else 15.sp)
        }
    }
}

@Composable
private fun BannerPremium(mensaje: String, esMovil: Boolean) {
    val padH = if (esMovil) 16.dp else 48.dp
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = padH)
            .fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        AppColors.Gold.copy(alpha = 0.22f),
                        AppColors.Gold.copy(alpha = 0.05f)
                    )
                )
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.55f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📢", fontSize = if (esMovil) 18.sp else 20.sp)
        Spacer(Modifier.width(12.dp))
        Text(
            mensaje,
            color = AppColors.GoldBright,
            fontSize = if (esMovil) 12.sp else 13.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = if (esMovil) 16.sp else 18.sp
        )
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ Home v3 Premium completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
