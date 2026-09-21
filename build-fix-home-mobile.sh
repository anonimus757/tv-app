#!/bin/bash
set -e

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
BACKUP="${HOME_FILE}.bak.mobile.$(date +%s)"
[ ! -f "$HOME_FILE" ] && { echo "❌ No existe $HOME_FILE"; exit 1; }
cp "$HOME_FILE" "$BACKUP"
echo "✅ Backup: $BACKUP"

cat > "$HOME_FILE" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.ui

import android.content.res.Configuration
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
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
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
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

private fun diaRelativo(fechaStr: String): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(fechaStr) ?: return "PRÓXIMOS"
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val eventoMillis = cal.timeInMillis
        val diffDias = ((eventoMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()
        when {
            diffDias < 0 -> "FINALIZADOS"
            diffDias == 0 -> "HOY"
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
        else porDia.getOrPut(diaRelativo(ev.fecha)) { mutableListOf() }.add(ev)
    }
    enVivo.sortBy { horaAMinutos(it.hora) }
    porDia.values.forEach { it.sortBy { horaAMinutos(it.hora) } }
    val orden = listOf("HOY", "MAÑANA", "PASADO MAÑANA", "ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
    val gruposOrdenados = porDia.entries
        .sortedBy { (k, _) -> orden.indexOf(k).let { if (it < 0) 999 else it } }
        .map { it.key to it.value }
    return enVivo to gruposOrdenados
}

private fun anchoCardPorDispositivo(esTV: Boolean, esVertical: Boolean): Dp = when {
    esTV -> 340.dp
    esVertical -> 160.dp
    else -> 240.dp
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
    val esMobileVertical = !esTV && esVertical

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var cargandoScraping by remember { mutableStateOf(false) }
    var scrapingCargado by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Conectando...") }
    var tabSeleccionado by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        try {
            status = "Cargando eventos..."
            eventosFirebase = EventRepository.obtenerEventosFirestore()
        } catch (e: Exception) { status = "Error: ${e.message}" }
        cargando = false
        try { EventNotifScheduler.reagendar(context, eventosFirebase) } catch (_: Exception) {}
    }

    LaunchedEffect(tabSeleccionado) {
        if (tabSeleccionado == 1 && !scrapingCargado && eventosScraping.isEmpty()) {
            cargandoScraping = true
            try {
                status = "Cargando agendas..."
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
                scrapingCargado = true
                EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping)
            } catch (e: Exception) { status = "Error: ${e.message}" }
            cargandoScraping = false
        }
    }

    Box(Modifier.fillMaxSize().background(
        Brush.verticalGradient(listOf(AppColors.Background, AppColors.BackgroundGradient))
    )) {
        if (cargando) {
            SkeletonHome(status)
        } else {
            Column(Modifier.fillMaxSize()) {
                Spacer(Modifier.height(if (esMobileVertical) 12.dp else 24.dp))
                HeaderFutTV(
                    totalEventos = eventosFirebase.size + eventosScraping.size,
                    totalCanales = (eventosFirebase + eventosScraping).sumOf { it.embeds.size },
                    esTV = esTV,
                    esMobileVertical = esMobileVertical,
                    onIrAAjustes = onIrAAjustes,
                    onIrABusqueda = onIrABusqueda
                )

                if (config.mensajeSistema.isNotBlank()) {
                    Spacer(Modifier.height(12.dp))
                    BannerSistema(config.mensajeSistema, esMobileVertical)
                }

                Spacer(Modifier.height(if (esMobileVertical) 12.dp else 18.dp))
                TabsSelector(
                    seleccionado = tabSeleccionado,
                    onSeleccion = { tabSeleccionado = it },
                    esMobileVertical = esMobileVertical
                )
                Spacer(Modifier.height(4.dp))

                when (tabSeleccionado) {
                    0 -> ContenidoMisEventos(eventosFirebase, esTV, esVertical, esMobileVertical, onEventoClick)
                    1 -> ContenidoAgendasWeb(eventosScraping, cargandoScraping, config.mostrarScraping, esTV, esVertical, esMobileVertical, status, onEventoClick)
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// HEADER con botones Ajustes/Busqueda
// ═══════════════════════════════════════════════════════════

@Composable
private fun HeaderFutTV(
    totalEventos: Int, totalCanales: Int,
    esTV: Boolean, esMobileVertical: Boolean,
    onIrAAjustes: () -> Unit, onIrABusqueda: () -> Unit
) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)
    val padH = if (esMobileVertical) 14.dp else 40.dp
    val tituloSize = if (esMobileVertical) 24.sp else 34.sp
    val logoSize = if (esMobileVertical) 24.sp else 32.sp

    Column(Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(durationMs = 400)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = logoSize)
            Spacer(Modifier.width(8.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = tituloSize,
                fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Spacer(Modifier.width(10.dp))
            Box(
                Modifier.alpha(pulse).clip(RoundedCornerShape(8.dp))
                    .background(AppColors.Gold.copy(alpha = 0.15f))
                    .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text("● EN VIVO", color = AppColors.Gold, fontSize = 10.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = 1.sp, maxLines = 1)
            }
            Spacer(Modifier.weight(1f))
            IconBtn("🔍", onIrABusqueda)
            Spacer(Modifier.width(8.dp))
            IconBtn("⚙️", onIrAAjustes)
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "$totalEventos eventos · $totalCanales canales",
            color = AppColors.TextSecondary, fontSize = 12.sp,
            maxLines = 1, overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun IconBtn(icono: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.Gold.copy(alpha = 0.3f) else AppColors.Card)
            .border(1.dp, if (focused) AppColors.GoldBright else AppColors.SurfaceLight, RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Text(icono, fontSize = 18.sp)
    }
}

// ═══════════════════════════════════════════════════════════
// TABS
// ═══════════════════════════════════════════════════════════

@Composable
private fun TabsSelector(seleccionado: Int, onSeleccion: (Int) -> Unit, esMobileVertical: Boolean) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = if (esMobileVertical) 14.dp else 40.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        TabChip("🎯 MIS EVENTOS", seleccionado == 0, { onSeleccion(0) }, Modifier.weight(1f), esMobileVertical)
        TabChip("🌐 AGENDAS WEB", seleccionado == 1, { onSeleccion(1) }, Modifier.weight(1f), esMobileVertical)
    }
}

@Composable
private fun TabChip(titulo: String, activo: Boolean, onClick: () -> Unit, modifier: Modifier, esMobileVertical: Boolean) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        targetValue = when {
            focused -> AppColors.GoldBright.copy(alpha = 0.25f)
            activo -> AppColors.Gold.copy(alpha = 0.15f)
            else -> AppColors.Card
        }, animationSpec = tween(180), label = "tabBg"
    )
    val border by animateColorAsState(
        targetValue = when {
            focused -> AppColors.GoldBright
            activo -> AppColors.Gold
            else -> AppColors.SurfaceLight
        }, animationSpec = tween(180), label = "tabBorder"
    )
    val textColor = if (focused || activo) AppColors.GoldBright else AppColors.TextSecondary

    Box(
        modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (focused) 2.dp else 1.dp, border, RoundedCornerShape(12.dp))
            .padding(vertical = if (esMobileVertical) 10.dp else 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            titulo,
            color = textColor,
            fontSize = if (esMobileVertical) 13.sp else 16.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 1.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: MIS EVENTOS
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoMisEventos(
    eventos: List<Evento>,
    esTV: Boolean, esVertical: Boolean, esMobileVertical: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (eventos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("📭", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Sin eventos programados", color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Cargá eventos desde el panel de Sheets", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
        }
        return
    }

    val (enVivo, gruposPorDia) = remember(eventos) { agruparEventos(eventos) }
    val expandidos = remember { mutableStateMapOf<String, Boolean>() }
    val destacado = enVivo.firstOrNull() ?: gruposPorDia.firstOrNull()?.second?.firstOrNull()

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 48.dp)) {
        if (destacado != null) {
            item(key = "hero") {
                Spacer(Modifier.height(12.dp))
                HeroEvento(destacado, esTV, esMobileVertical) {
                    val listaHero = if (enVivo.isNotEmpty()) enVivo else (gruposPorDia.firstOrNull()?.second ?: listOf(destacado))
                    onEventoClick(destacado, listaHero)
                }
                Spacer(Modifier.height(24.dp))
            }
        }

        if (enVivo.isNotEmpty()) {
            item(key = "sep_live") {
                SeparadorSeccion("🔴 EN VIVO AHORA", "${enVivo.size} evento(s) en curso", Color(0xFFFF3B30), esMobileVertical)
            }
            item(key = "row_live") { FilaEventos(enVivo, onEventoClick, esTV, esVertical, esMobileVertical) }
            item(key = "sp_live") { Spacer(Modifier.height(20.dp)) }
        }

        gruposPorDia.forEach { (dia, lista) ->
            val color = when (dia) {
                "HOY", "MAÑANA" -> AppColors.GoldBright
                "PASADO MAÑANA" -> AppColors.Gold
                "FINALIZADOS" -> AppColors.TextMuted
                else -> AppColors.TextSecondary
            }
            val icono = when (dia) {
                "HOY" -> "📅 HOY"
                "MAÑANA" -> "📅 MAÑANA"
                "PASADO MAÑANA" -> "📅 PASADO MAÑANA"
                "ESTA SEMANA" -> "📅 ESTA SEMANA"
                "PRÓXIMOS" -> "📅 PRÓXIMOS DÍAS"
                "FINALIZADOS" -> "📅 FINALIZADOS"
                else -> "📅 $dia"
            }
            val colapsable = dia in listOf("ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
            val expandido = expandidos.getOrPut(dia) { !colapsable }

            item(key = "head_$dia") {
                HeaderFechaColapsable(icono, lista.size, color, colapsable, expandido, esMobileVertical) {
                    expandidos[dia] = !expandido
                }
            }
            if (expandido) {
                item(key = "row_$dia") { FilaEventos(lista, onEventoClick, esTV, esVertical, esMobileVertical) }
            }
            item(key = "sp_$dia") { Spacer(Modifier.height(16.dp)) }
        }

        item(key = "footer") {
            Spacer(Modifier.height(40.dp))
            Text("FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = AppColors.TextMuted, fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = if (esMobileVertical) 14.dp else 40.dp))
        }
    }
}

@Composable
private fun HeaderFechaColapsable(
    titulo: String, total: Int, color: Color,
    colapsable: Boolean, expandido: Boolean, esMobileVertical: Boolean,
    onToggle: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val padH = if (esMobileVertical) 14.dp else 40.dp

    val base = Modifier.fillMaxWidth().padding(horizontal = padH, vertical = 4.dp).fadeInOnLoad(durationMs = 400, delayMs = 150)
    val interactivo = if (colapsable) base.onFocusChanged { focused = it.isFocused }.focusable().clickable { onToggle() } else base

    Row(interactivo, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(4.dp).height(if (esMobileVertical) 24.dp else 30.dp).clip(RoundedCornerShape(2.dp)).background(color))
        Spacer(Modifier.width(10.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = if (esMobileVertical) 18.sp else 24.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(8.dp))
        Box(Modifier.clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.2f)).padding(horizontal = 8.dp, vertical = 2.dp)) {
            Text("$total", color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        if (colapsable) {
            Spacer(Modifier.weight(1f))
            Text(if (expandido) "▲" else "▼",
                color = if (focused) AppColors.GoldBright else AppColors.TextSecondary,
                fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: AGENDAS WEB
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoAgendasWeb(
    eventos: List<Evento>, cargando: Boolean, mostrarScraping: Boolean,
    esTV: Boolean, esVertical: Boolean, esMobileVertical: Boolean,
    status: String, onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (!mostrarScraping) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("🌐", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Agendas deshabilitadas", color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }
        return
    }
    if (cargando) { SkeletonAgendas(status, esMobileVertical); return }
    if (eventos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("🌐", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Sin agendas disponibles", color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Probá de nuevo en unos minutos", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
        }
        return
    }

    val grupos = remember(eventos) { eventos.groupBy { it.groupTitle } }
    val padH = if (esMobileVertical) 14.dp else 40.dp

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 48.dp)) {
        item(key = "sc_intro") {
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(400), verticalAlignment = Alignment.CenterVertically) {
                Text("🌐", fontSize = 20.sp)
                Spacer(Modifier.width(8.dp))
                Text("${eventos.size} eventos scrapeados en vivo", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
            Spacer(Modifier.height(16.dp))
        }
        grupos.forEach { (titulo, lista) ->
            item(key = "sc_head_$titulo") { HeaderCategoria(titulo, lista.size, esMobileVertical) }
            item(key = "sc_row_$titulo") { FilaEventos(lista, onEventoClick, esTV, esVertical, esMobileVertical) }
            item(key = "sc_sp_$titulo") { Spacer(Modifier.height(20.dp)) }
        }
        item(key = "footer") {
            Spacer(Modifier.height(40.dp))
            Text("FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = AppColors.TextMuted, fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = padH))
        }
    }
}

// ═══════════════════════════════════════════════════════════
// SKELETONS
// ═══════════════════════════════════════════════════════════

@Composable
private fun SkeletonHome(status: String) {
    val esMobile = !rememberEsTV()
    val padH = if (esMobile) 14.dp else 40.dp
    Column(Modifier.fillMaxSize().padding(top = if (esMobile) 12.dp else 32.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(350), verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = if (esMobile) 26.sp else 32.sp)
            Spacer(Modifier.width(8.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = if (esMobile) 26.sp else 34.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Spacer(Modifier.width(12.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(20.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f).height(44.dp).shimmer(RoundedCornerShape(12.dp)))
            Box(Modifier.weight(1f).height(44.dp).shimmer(RoundedCornerShape(12.dp)))
        }
        Spacer(Modifier.height(20.dp))
        Box(Modifier.fillMaxWidth().padding(horizontal = padH).height(if (esMobile) 300.dp else 200.dp).shimmer(RoundedCornerShape(20.dp)))
    }
}

@Composable
private fun SkeletonAgendas(status: String, esMobileVertical: Boolean) {
    val padH = if (esMobileVertical) 14.dp else 40.dp
    Column(Modifier.fillMaxSize().padding(top = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = padH), verticalAlignment = Alignment.CenterVertically) {
            Text("🌐", fontSize = 22.sp)
            Spacer(Modifier.width(8.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 13.sp)
        }
        Spacer(Modifier.height(20.dp))
        repeat(3) {
            Box(Modifier.padding(horizontal = padH).width(200.dp).height(24.dp).shimmer(RoundedCornerShape(8.dp)))
            Spacer(Modifier.height(12.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = padH), horizontalArrangement = Arrangement.spacedBy(12.dp), userScrollEnabled = false) {
                repeat(4) { item { Box(Modifier.width(160.dp).height(200.dp).shimmer(RoundedCornerShape(14.dp))) } }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

// ═══════════════════════════════════════════════════════════
// COMPONENTES
// ═══════════════════════════════════════════════════════════

@Composable
private fun SeparadorSeccion(titulo: String, subtitulo: String, color: Color, esMobileVertical: Boolean) {
    val padH = if (esMobileVertical) 14.dp else 40.dp
    Column(Modifier.fillMaxWidth().padding(horizontal = padH, vertical = 8.dp).fadeInOnLoad(400)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(5.dp).height(if (esMobileVertical) 26.dp else 32.dp).clip(RoundedCornerShape(3.dp)).background(color))
            Spacer(Modifier.width(12.dp))
            Text(titulo, color = color, fontSize = if (esMobileVertical) 20.sp else 26.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(4.dp))
        Text(subtitulo, color = AppColors.TextSecondary, fontSize = 12.sp, modifier = Modifier.padding(start = 17.dp))
    }
}

@Composable
private fun BannerSistema(mensaje: String, esMobileVertical: Boolean) {
    val padH = if (esMobileVertical) 14.dp else 40.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH).fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(Brush.horizontalGradient(listOf(AppColors.Gold.copy(alpha = 0.25f), AppColors.Gold.copy(alpha = 0.08f))))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📢", fontSize = 20.sp)
        Spacer(Modifier.width(10.dp))
        Text(mensaje, color = AppColors.GoldBright, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, lineHeight = 17.sp)
    }
}

@Composable
private fun HeroEvento(evento: Evento, esTV: Boolean, esMobileVertical: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(evento.groupTitle)
    val estaLive = estaEnVivo(evento)
    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "hbw")
    val borderColor by animateColorAsState(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f), tween(180), label = "hbc")

    val padH = if (esMobileVertical) 14.dp else 40.dp
    val base = Modifier.fillMaxWidth().padding(horizontal = padH)
        .fadeInOnLoad(durationMs = 500, delayMs = 100)
        .scaleOnFocus(isFocused = focused, focusedScale = 1.02f)
        .onFocusChanged { focused = it.isFocused }
        .focusable().clickable { onClick() }
        .clip(RoundedCornerShape(20.dp))
        .background(Brush.horizontalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface)))
        .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
        .padding(if (esMobileVertical) 14.dp else 24.dp)

    if (esMobileVertical) {
        Column(base) {
            Box(Modifier.fillMaxWidth().height(160.dp).clip(RoundedCornerShape(14.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                contentAlignment = Alignment.Center
            ) {
                if (evento.imagen.isNotBlank()) AsyncImage(evento.imagen, null, contentScale = ContentScale.Fit, modifier = Modifier.size(120.dp))
                else Text("⚽", fontSize = 60.sp)
            }
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (estaLive) BadgeMini("🔴 EN VIVO", Color(0xFFFF3B30), Color.White)
                else BadgeMini("⭐ DESTACADO", AppColors.Gold, Color.Black)
                BadgeMini("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}", color.copy(alpha = 0.2f), color)
            }
            Spacer(Modifier.height(10.dp))
            Text(evento.descripcion, color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, lineHeight = 24.sp)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐 ${evento.hora}", color = AppColors.GoldBright, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(12.dp))
                Text("📺 ${evento.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
            Spacer(Modifier.height(12.dp))
            BotonVerAhora(focused, true)
        }
    } else {
        Row(base, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(140.dp).clip(RoundedCornerShape(16.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                contentAlignment = Alignment.Center
            ) {
                if (evento.imagen.isNotBlank()) AsyncImage(evento.imagen, null, contentScale = ContentScale.Fit, modifier = Modifier.size(110.dp))
                else Text("⚽", fontSize = 60.sp)
            }
            Spacer(Modifier.width(28.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (estaLive) BadgeMini("🔴 EN VIVO", Color(0xFFFF3B30), Color.White)
                    else BadgeMini("⭐ DESTACADO", AppColors.Gold, Color.Black)
                    BadgeMini("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}", color.copy(alpha = 0.2f), color)
                }
                Spacer(Modifier.height(14.dp))
                Text(evento.descripcion, color = AppColors.TextPrimary, fontSize = 28.sp, fontWeight = FontWeight.Bold, maxLines = 2, lineHeight = 34.sp)
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("🕐 ${evento.hora}", color = AppColors.GoldBright, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(16.dp))
                    Text("📅 ${evento.fecha}", color = AppColors.TextSecondary, fontSize = 14.sp)
                    Spacer(Modifier.width(16.dp))
                    Text("📺 ${evento.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 14.sp)
                }
                Spacer(Modifier.height(16.dp))
                BotonVerAhora(focused, false)
            }
        }
    }
}

@Composable
private fun BadgeMini(texto: String, bg: Color, fg: Color) {
    Box(Modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 8.dp, vertical = 3.dp)) {
        Text(texto, color = fg, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, maxLines = 1)
    }
}

@Composable
private fun BotonVerAhora(focused: Boolean, fullWidth: Boolean) {
    val mod = if (fullWidth) Modifier.fillMaxWidth() else Modifier
    Box(
        mod.clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold)
            .padding(horizontal = 22.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("▶", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(8.dp))
            Text("VER AHORA", color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 1)
        }
    }
}

@Composable
private fun HeaderCategoria(titulo: String, total: Int, esMobileVertical: Boolean) {
    val color = AppColors.fuenteColor(titulo)
    val icono = AppColors.fuenteIcono(titulo)
    val padH = if (esMobileVertical) 14.dp else 40.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = padH, vertical = 4.dp).fadeInOnLoad(400, delayMs = 150),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(4.dp).height(if (esMobileVertical) 22.dp else 30.dp).clip(RoundedCornerShape(2.dp)).background(color))
        Spacer(Modifier.width(10.dp))
        Text(icono, fontSize = if (esMobileVertical) 18.sp else 24.sp)
        Spacer(Modifier.width(6.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = if (esMobileVertical) 17.sp else 24.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.width(8.dp))
        Box(Modifier.clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.2f)).padding(horizontal = 8.dp, vertical = 2.dp)) {
            Text("$total", color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    esTV: Boolean, esVertical: Boolean, esMobileVertical: Boolean
) {
    val ancho = anchoCardPorDispositivo(esTV, esVertical)
    val padH = if (esMobileVertical) 14.dp else 40.dp
    LazyRow(
        contentPadding = PaddingValues(horizontal = padH, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        itemsIndexed(items = lista, key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }) { index, ev ->
            Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 150 + index * 50, slideFromDp = 20f)) {
                EventoCardPro(ev, ancho, esTV, esMobileVertical) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun EventoCardPro(ev: Evento, ancho: Dp, esTV: Boolean, esMobileVertical: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val estaLive = estaEnVivo(ev)
    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cbw")
    val borderColor by animateColorAsState(
        when { estaLive -> Color(0xFFFF3B30); focused -> AppColors.GoldBright; else -> color.copy(alpha = 0.3f) },
        tween(180), label = "cbc"
    )
    val bgColor by animateColorAsState(if (focused) AppColors.CardFocus else AppColors.Card, tween(180), label = "cbg")
    val alturaImg = when { esTV -> 170.dp; esMobileVertical -> 100.dp; else -> 140.dp }
    val fontSizeTitulo = when { esMobileVertical -> 13.sp; esTV -> 15.sp; else -> 14.sp }

    Column(
        Modifier.width(ancho)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)
            .onFocusChanged { focused = it.isFocused }
            .focusable().clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bgColor)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(if (esMobileVertical) 10.dp else 14.dp)
    ) {
        Box(Modifier.fillMaxWidth().height(alturaImg).clip(RoundedCornerShape(10.dp))
            .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) AsyncImage(ev.imagen, null, contentScale = ContentScale.Fit, modifier = Modifier.size(if (esMobileVertical) 70.dp else 100.dp))
            else Text("⚽", fontSize = if (esMobileVertical) 36.sp else 50.sp)

            if (estaLive) {
                Box(Modifier.align(Alignment.TopStart).padding(6.dp).clip(RoundedCornerShape(5.dp))
                    .background(Color(0xFFFF3B30)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                    Text("● LIVE", color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Black)
                }
            }
            Box(Modifier.align(Alignment.TopEnd).padding(6.dp).clip(RoundedCornerShape(5.dp))
                .background(AppColors.Gold).padding(horizontal = 6.dp, vertical = 2.dp)) {
                Text(ev.hora, color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(ev.descripcion, color = AppColors.TextPrimary, fontSize = fontSizeTitulo,
            fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = (fontSizeTitulo.value + 3).sp,
            modifier = Modifier.height((fontSizeTitulo.value * 2.6f).dp), overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(5.dp).clip(CircleShape).background(AppColors.Gold))
            Spacer(Modifier.width(5.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 11.sp, maxLines = 1)
            Spacer(Modifier.weight(1f))
            Text(if (focused) "▶" else "→",
                color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ Home responsive mobile OK"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
