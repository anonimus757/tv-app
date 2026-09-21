#!/bin/bash
set -e

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
BACKUP="${HOME_FILE}.bak.$(date +%s)"

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
    } catch (e: Exception) {
        false
    }
}

private fun diaRelativo(fechaStr: String): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(fechaStr) ?: return "PRÓXIMOS"

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis

        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
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
    } catch (e: Exception) {
        "PRÓXIMOS"
    }
}

private fun agruparEventos(eventos: List<Evento>): Pair<List<Evento>, List<Pair<String, List<Evento>>>> {
    val enVivo = mutableListOf<Evento>()
    val porDia = mutableMapOf<String, MutableList<Evento>>()

    eventos.forEach { ev ->
        if (estaEnVivo(ev)) {
            enVivo.add(ev)
        } else {
            val dia = diaRelativo(ev.fecha)
            porDia.getOrPut(dia) { mutableListOf() }.add(ev)
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

private fun anchoCardPorDispositivo(esTV: Boolean, esVertical: Boolean): Dp = when {
    esTV -> 360.dp
    esVertical -> 180.dp
    else -> 260.dp
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

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var cargandoScraping by remember { mutableStateOf(false) }
    var scrapingCargado by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Conectando...") }
    var tabSeleccionado by remember { mutableStateOf(0) }

    // Cargar SOLO Firestore al inicio
    LaunchedEffect(Unit) {
        try {
            status = "Cargando eventos..."
            eventosFirebase = EventRepository.obtenerEventosFirestore()
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargando = false

        try {
            EventNotifScheduler.reagendar(context, eventosFirebase)
        } catch (_: Exception) {}
    }

    // Scraping lazy: solo cuando el user entra al tab
    LaunchedEffect(tabSeleccionado) {
        if (tabSeleccionado == 1 && !scrapingCargado && eventosScraping.isEmpty()) {
            cargandoScraping = true
            try {
                status = "Cargando agendas..."
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
                scrapingCargado = true
                EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping)
            } catch (e: Exception) {
                status = "Error: ${e.message}"
            }
            cargandoScraping = false
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, AppColors.BackgroundGradient)
                )
            )
    ) {
        if (cargando) {
            SkeletonHome(status)
        } else {
            Column(Modifier.fillMaxSize()) {
                Spacer(Modifier.height(24.dp))
                HeaderFutTV(
                    totalEventos = eventosFirebase.size + eventosScraping.size,
                    totalCanales = (eventosFirebase + eventosScraping).sumOf { it.embeds.size }
                )

                if (config.mensajeSistema.isNotBlank()) {
                    Spacer(Modifier.height(16.dp))
                    BannerSistema(config.mensajeSistema)
                }

                Spacer(Modifier.height(18.dp))
                TabsSelector(
                    seleccionado = tabSeleccionado,
                    onSeleccion = { tabSeleccionado = it }
                )
                Spacer(Modifier.height(8.dp))

                when (tabSeleccionado) {
                    0 -> ContenidoMisEventos(
                        eventos = eventosFirebase,
                        esTV = esTV,
                        esVertical = esVertical,
                        onEventoClick = onEventoClick
                    )
                    1 -> ContenidoAgendasWeb(
                        eventos = eventosScraping,
                        cargando = cargandoScraping,
                        mostrarScraping = config.mostrarScraping,
                        esTV = esTV,
                        esVertical = esVertical,
                        status = status,
                        onEventoClick = onEventoClick
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// TABS
// ═══════════════════════════════════════════════════════════

@Composable
private fun TabsSelector(seleccionado: Int, onSeleccion: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        TabChip(
            titulo = "🎯 MIS EVENTOS",
            activo = seleccionado == 0,
            onClick = { onSeleccion(0) },
            modifier = Modifier.weight(1f)
        )
        TabChip(
            titulo = "🌐 AGENDAS WEB",
            activo = seleccionado == 1,
            onClick = { onSeleccion(1) },
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun TabChip(titulo: String, activo: Boolean, onClick: () -> Unit, modifier: Modifier) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        targetValue = when {
            focused -> AppColors.GoldBright.copy(alpha = 0.25f)
            activo -> AppColors.Gold.copy(alpha = 0.15f)
            else -> AppColors.Card
        },
        animationSpec = tween(180), label = "tabBg"
    )
    val border by animateColorAsState(
        targetValue = when {
            focused -> AppColors.GoldBright
            activo -> AppColors.Gold
            else -> AppColors.SurfaceLight
        },
        animationSpec = tween(180), label = "tabBorder"
    )
    val textColor = when {
        focused || activo -> AppColors.GoldBright
        else -> AppColors.TextSecondary
    }

    Box(
        modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (focused) 2.dp else 1.dp, border, RoundedCornerShape(12.dp))
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            titulo,
            color = textColor,
            fontSize = 16.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 1.sp
        )
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: MIS EVENTOS (Firestore) agrupado por fecha
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoMisEventos(
    eventos: List<Evento>,
    esTV: Boolean,
    esVertical: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (eventos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("📭", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Sin eventos programados", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Cargá eventos desde el panel de Sheets", color = AppColors.TextSecondary, fontSize = 14.sp)
            }
        }
        return
    }

    val (enVivo, gruposPorDia) = remember(eventos) { agruparEventos(eventos) }
    val destacado = enVivo.firstOrNull() ?: gruposPorDia.firstOrNull()?.second?.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 48.dp)
    ) {
        if (destacado != null) {
            item(key = "hero") {
                Spacer(Modifier.height(12.dp))
                HeroEvento(destacado) {
                    val listaHero = if (enVivo.isNotEmpty()) enVivo else (gruposPorDia.firstOrNull()?.second ?: listOf(destacado))
                    onEventoClick(destacado, listaHero)
                }
                Spacer(Modifier.height(28.dp))
            }
        }

        if (enVivo.isNotEmpty()) {
            item(key = "sep_live") {
                SeparadorSeccion(
                    titulo = "🔴 EN VIVO AHORA",
                    subtitulo = "${enVivo.size} evento(s) en curso",
                    color = Color(0xFFFF3B30)
                )
            }
            item(key = "row_live") {
                FilaEventos(enVivo, onEventoClick, esTV, esVertical)
            }
            item(key = "sp_live") { Spacer(Modifier.height(24.dp)) }
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
            var expandido by remember(dia) { mutableStateOf(!colapsable) }

            item(key = "head_$dia") {
                HeaderFechaColapsable(
                    titulo = icono,
                    total = lista.size,
                    color = color,
                    colapsable = colapsable,
                    expandido = expandido,
                    onToggle = { expandido = !expandido }
                )
            }

            if (expandido) {
                item(key = "row_$dia") {
                    FilaEventos(lista, onEventoClick, esTV, esVertical)
                }
            }

            item(key = "sp_$dia") { Spacer(Modifier.height(20.dp)) }
        }

        item(key = "footer") {
            Spacer(Modifier.height(40.dp))
            Text(
                "FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = AppColors.TextMuted,
                fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp)
            )
        }
    }
}

@Composable
private fun HeaderFechaColapsable(
    titulo: String,
    total: Int,
    color: Color,
    colapsable: Boolean,
    expandido: Boolean,
    onToggle: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }

    val modifierBase = Modifier
        .fillMaxWidth()
        .padding(horizontal = 40.dp, vertical = 4.dp)
        .fadeInOnLoad(durationMs = 400, delayMs = 150)

    val modifierInteractivo = if (colapsable) {
        modifierBase
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onToggle() }
    } else modifierBase

    Row(modifierInteractivo, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(5.dp).height(30.dp).clip(RoundedCornerShape(3.dp)).background(color))
        Spacer(Modifier.width(14.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier.clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.2f))
                .padding(horizontal = 10.dp, vertical = 3.dp)
        ) {
            Text("$total", color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
        if (colapsable) {
            Spacer(Modifier.weight(1f))
            Text(
                if (expandido) "▲" else "▼",
                color = if (focused) AppColors.GoldBright else AppColors.TextSecondary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// CONTENIDO: AGENDAS WEB (scraping)
// ═══════════════════════════════════════════════════════════

@Composable
private fun ContenidoAgendasWeb(
    eventos: List<Evento>,
    cargando: Boolean,
    mostrarScraping: Boolean,
    esTV: Boolean,
    esVertical: Boolean,
    status: String,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    if (!mostrarScraping) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("🌐", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Agendas deshabilitadas", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("El panel deshabilitó el scraping", color = AppColors.TextSecondary, fontSize = 14.sp)
            }
        }
        return
    }

    if (cargando) {
        SkeletonAgendas(status)
        return
    }

    if (eventos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("🌐", fontSize = 60.sp)
                Spacer(Modifier.height(16.dp))
                Text("Sin agendas disponibles", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Probá de nuevo en unos minutos", color = AppColors.TextSecondary, fontSize = 14.sp)
            }
        }
        return
    }

    val grupos = remember(eventos) { eventos.groupBy { it.groupTitle } }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 48.dp)
    ) {
        item(key = "sc_intro") {
            Spacer(Modifier.height(14.dp))
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🌐", fontSize = 22.sp)
                Spacer(Modifier.width(10.dp))
                Text(
                    "${eventos.size} eventos scrapeados en vivo",
                    color = AppColors.TextSecondary,
                    fontSize = 14.sp
                )
            }
            Spacer(Modifier.height(18.dp))
        }

        grupos.forEach { (titulo, lista) ->
            item(key = "sc_head_$titulo") { HeaderCategoria(titulo, lista.size) }
            item(key = "sc_row_$titulo") { FilaEventos(lista, onEventoClick, esTV, esVertical) }
            item(key = "sc_sp_$titulo") { Spacer(Modifier.height(24.dp)) }
        }

        item(key = "footer") {
            Spacer(Modifier.height(40.dp))
            Text(
                "FutTV · v${com.anonimus757.tvapp.BuildConfig.VERSION_NAME}",
                color = AppColors.TextMuted,
                fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp)
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// SKELETONS
// ═══════════════════════════════════════════════════════════

@Composable
private fun SkeletonHome(status: String) {
    Column(Modifier.fillMaxSize().padding(top = 32.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(350),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("⚽", fontSize = 32.sp)
            Spacer(Modifier.width(10.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = 34.sp,
                fontWeight = FontWeight.Black, letterSpacing = 3.sp)
            Spacer(Modifier.width(20.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
        }
        Spacer(Modifier.height(24.dp))
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 40.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(Modifier.weight(1f).height(50.dp).shimmer(RoundedCornerShape(12.dp)))
            Box(Modifier.weight(1f).height(50.dp).shimmer(RoundedCornerShape(12.dp)))
        }
        Spacer(Modifier.height(24.dp))
        Box(Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(200.dp).shimmer(RoundedCornerShape(20.dp)))
        Spacer(Modifier.height(40.dp))
        repeat(2) {
            Box(Modifier.padding(horizontal = 40.dp).width(260.dp).height(30.dp).shimmer(RoundedCornerShape(8.dp)))
            Spacer(Modifier.height(14.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 40.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                userScrollEnabled = false
            ) {
                repeat(4) {
                    item {
                        Box(Modifier.width(260.dp).height(240.dp).shimmer(RoundedCornerShape(14.dp)))
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun SkeletonAgendas(status: String) {
    Column(Modifier.fillMaxSize().padding(top = 24.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(350),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("🌐", fontSize = 26.sp)
            Spacer(Modifier.width(10.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
        }
        Spacer(Modifier.height(24.dp))
        repeat(3) {
            Box(Modifier.padding(horizontal = 40.dp).width(260.dp).height(28.dp).shimmer(RoundedCornerShape(8.dp)))
            Spacer(Modifier.height(14.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 40.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                userScrollEnabled = false
            ) {
                repeat(4) {
                    item {
                        Box(Modifier.width(260.dp).height(240.dp).shimmer(RoundedCornerShape(14.dp)))
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

// ═══════════════════════════════════════════════════════════
// COMPONENTES REUTILIZABLES
// ═══════════════════════════════════════════════════════════

@Composable
private fun SeparadorSeccion(titulo: String, subtitulo: String, color: Color) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp).fadeInOnLoad(400)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(32.dp).clip(RoundedCornerShape(3.dp)).background(color))
            Spacer(Modifier.width(14.dp))
            Text(
                titulo,
                color = color,
                fontSize = 26.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            subtitulo,
            color = AppColors.TextSecondary,
            fontSize = 13.sp,
            modifier = Modifier.padding(start = 20.dp)
        )
    }
}

@Composable
private fun BannerSistema(mensaje: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        AppColors.Gold.copy(alpha = 0.25f),
                        AppColors.Gold.copy(alpha = 0.08f)
                    )
                )
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📢", fontSize = 22.sp)
        Spacer(Modifier.width(14.dp))
        Text(
            mensaje,
            color = AppColors.GoldBright,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 18.sp
        )
    }
}

@Composable
private fun HeaderFutTV(totalEventos: Int, totalCanales: Int) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(durationMs = 400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = 32.sp)
            Spacer(Modifier.width(10.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = 34.sp,
                fontWeight = FontWeight.Black, letterSpacing = 3.sp)
        }
        Spacer(Modifier.width(20.dp))
        Box(
            Modifier
                .alpha(pulse)
                .clip(RoundedCornerShape(8.dp))
                .background(AppColors.Gold.copy(alpha = 0.15f))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        ) {
            Text("● EN VIVO", color = AppColors.Gold, fontSize = 11.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        }
        Spacer(Modifier.weight(1f))
        Text("$totalEventos eventos · $totalCanales canales",
            color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun HeroEvento(evento: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(evento.groupTitle)
    val estaLive = estaEnVivo(evento)

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180), label = "heroBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
        animationSpec = tween(180), label = "heroBorderColor"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .fadeInOnLoad(durationMs = 500, delayMs = 100)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.02f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface)))
            .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
            .padding(24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(140.dp).clip(RoundedCornerShape(16.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (evento.imagen.isNotBlank()) {
                AsyncImage(
                    model = evento.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(110.dp)
                )
            } else {
                Text("⚽", fontSize = 60.sp)
            }
        }
        Spacer(Modifier.width(28.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (estaLive) {
                    Box(
                        Modifier.clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFFFF3B30))
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                    ) {
                        Text("🔴 EN VIVO", color = Color.White, fontSize = 11.sp,
                            fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    }
                } else {
                    Box(
                        Modifier.clip(RoundedCornerShape(6.dp)).background(AppColors.Gold)
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                    ) {
                        Text("⭐ DESTACADO", color = Color.Black, fontSize = 11.sp,
                            fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    }
                }
                Spacer(Modifier.width(10.dp))
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                        color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(14.dp))
            Text(evento.descripcion, color = AppColors.TextPrimary, fontSize = 32.sp,
                fontWeight = FontWeight.Bold, maxLines = 2, lineHeight = 38.sp)
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐", fontSize = 14.sp)
                Spacer(Modifier.width(6.dp))
                Text(evento.hora, color = AppColors.GoldBright, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(16.dp))
                Text("📅 ${evento.fecha}", color = AppColors.TextSecondary, fontSize = 14.sp)
                Spacer(Modifier.width(16.dp))
                Text("📺 ${evento.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 14.sp)
            }
            Spacer(Modifier.height(16.dp))
            Box(
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                    .padding(horizontal = 22.dp, vertical = 12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("▶", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    Text("VER AHORA", color = Color.Black, fontSize = 14.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                }
            }
        }
    }
}

@Composable
private fun HeaderCategoria(titulo: String, total: Int) {
    val color = AppColors.fuenteColor(titulo)
    val icono = AppColors.fuenteIcono(titulo)

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 4.dp)
            .fadeInOnLoad(durationMs = 400, delayMs = 150),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(5.dp).height(30.dp).clip(RoundedCornerShape(3.dp)).background(color))
        Spacer(Modifier.width(14.dp))
        Text(icono, fontSize = 24.sp)
        Spacer(Modifier.width(8.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier.clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.2f))
                .padding(horizontal = 10.dp, vertical = 3.dp)
        ) {
            Text("$total", color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    esTV: Boolean,
    esVertical: Boolean
) {
    val ancho = anchoCardPorDispositivo(esTV, esVertical)

    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
            Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 200 + index * 60, slideFromDp = 20f)) {
                EventoCardPro(ev, ancho, esTV) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun EventoCardPro(ev: Evento, ancho: Dp, esTV: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val estaLive = estaEnVivo(ev)

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180), label = "cardBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = when {
            estaLive -> Color(0xFFFF3B30)
            focused -> AppColors.GoldBright
            else -> color.copy(alpha = 0.3f)
        },
        animationSpec = tween(180), label = "cardBorderColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (focused) AppColors.CardFocus else AppColors.Card,
        animationSpec = tween(180), label = "cardBg"
    )

    val alturaImg = if (esTV) 180.dp else 150.dp

    Column(
        Modifier
            .width(ancho)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bgColor)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(14.dp)
    ) {
        Box(
            Modifier.fillMaxWidth().height(alturaImg).clip(RoundedCornerShape(10.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(105.dp)
                )
            } else {
                Text("⚽", fontSize = 50.sp)
            }
            if (estaLive) {
                Box(
                    Modifier.align(Alignment.TopStart).padding(8.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFFF3B30))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text("● LIVE", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                }
            }
            Box(
                Modifier.align(Alignment.TopEnd).padding(8.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(AppColors.Gold)
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(ev.hora, color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Black)
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(
            ev.descripcion, color = AppColors.TextPrimary, fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = 19.sp,
            modifier = Modifier.height(38.dp)
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(AppColors.Gold))
            Spacer(Modifier.width(6.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            Text(
                if (focused) "▶" else "→",
                color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                fontSize = 14.sp, fontWeight = FontWeight.Bold
            )
        }
    }
}
KOTLIN_EOF

echo ""
echo "✅✅✅ Home v2 completo: tabs + agrupación por fecha + detección dispositivo"
echo ""
echo "📋 Próximos pasos:"
echo "  1. ./gradlew clean"
echo "  2. ./gradlew assembleDebug --no-daemon --max-workers=1"
echo ""
echo "Backup: $BACKUP"
