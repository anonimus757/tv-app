#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

echo "📝 Reescribiendo HomeScreen.kt con iconos Material..."
cp "$PKG_DIR/HomeScreen.kt" "$PKG_DIR/HomeScreen.kt.bak34b" 2>/dev/null || true

cat > "$PKG_DIR/HomeScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.data.DebugLog
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
import com.anonimus757.tvapp.ui.theme.AppIcons
import kotlinx.coroutines.delay
import java.util.Calendar

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

private fun horaAMinutos(hora: String): Int {
    val match = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return -1
    val h = match.groupValues[1].toIntOrNull() ?: return -1
    val m = match.groupValues[2].toIntOrNull() ?: return -1
    if (h !in 0..23 || m !in 0..59) return -1
    return h * 60 + m
}

private fun minutosAhora(): Int {
    val cal = Calendar.getInstance()
    return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
}

private fun estaEnVivo(hora: String): Boolean {
    val min = horaAMinutos(hora)
    if (min < 0) return false
    val ahora = minutosAhora()
    return ahora >= min && ahora < min + 180
}

private fun esProximo(hora: String): Boolean {
    val min = horaAMinutos(hora)
    if (min < 0) return false
    val ahora = minutosAhora()
    return min > ahora && min < ahora + 360
}

// ─────────────────────────────────────────────────────────────
// Selector de días
// ─────────────────────────────────────────────────────────────

data class DiaItem(
    val offset: Int,
    val fecha: String,
    val etiqueta: String,
    val esHoy: Boolean
)

private fun calcularDias(): List<DiaItem> {
    return (0..6).map { offset ->
        val fecha = FechaHelper.hoyMasDias(offset)
        DiaItem(
            offset = offset,
            fecha = fecha,
            etiqueta = FechaHelper.etiquetaCorta(fecha, offset),
            esHoy = offset == 0
        )
    }
}

// ─────────────────────────────────────────────────────────────
// HomeScreen principal
// ─────────────────────────────────────────────────────────────

@Composable
fun HomeScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onIrAAjustes: () -> Unit = {},
    onIrABusqueda: () -> Unit = {}
) {
    val context = LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()
    val autoRefreshLocal = AjustesStore.obtenerAutoRefresh(context)

    val dias = remember { calcularDias() }
    var diaSeleccionado by remember { mutableStateOf(FechaHelper.hoy()) }

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargandoInicial by remember { mutableStateOf(true) }
    var refrescando by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Conectando...") }
    var mostrarDebug by remember { mutableStateOf(false) }
    var refreshTrigger by remember { mutableIntStateOf(0) }

    LaunchedEffect(Unit) {
        try {
            eventosFirebase = EventRepository.obtenerEventosFirestore()
            if (config.mostrarScraping) {
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
            }
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargandoInicial = false
        try { EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping) } catch (_: Exception) {}
    }

    LaunchedEffect(refreshTrigger) {
        if (refreshTrigger == 0) return@LaunchedEffect
        refrescando = true
        try {
            eventosFirebase = EventRepository.obtenerEventosFirestore()
            if (config.mostrarScraping) {
                eventosScraping = EventRepository.obtenerEventosScraping()
            }
        } catch (_: Exception) {}
        delay(500)
        refrescando = false
    }

    LaunchedEffect(config.minutosAutoRefresh, autoRefreshLocal) {
        if (!autoRefreshLocal || config.minutosAutoRefresh <= 0) return@LaunchedEffect
        while (true) {
            delay(config.minutosAutoRefresh * 60 * 1000L)
            refreshTrigger++
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
        when {
            cargandoInicial -> SkeletonHome(status)
            else -> Column(Modifier.fillMaxSize()) {
                Box(
                    Modifier.pointerInput(Unit) {
                        detectTapGestures(onLongPress = { mostrarDebug = !mostrarDebug })
                    }
                ) {
                    HeaderFutTV(
                        textoBienvenida = config.textoBienvenida,
                        totalEventos = eventosFirebase.size + eventosScraping.size,
                        totalCanales = (eventosFirebase + eventosScraping).sumOf { it.embeds.size },
                        refrescando = refrescando,
                        onRefrescar = { refreshTrigger++ },
                        onIrAAjustes = onIrAAjustes,
                        onIrABusqueda = onIrABusqueda
                    )
                }

                Spacer(Modifier.height(14.dp))

                SelectorDias(
                    dias = dias,
                    seleccionado = diaSeleccionado,
                    onSeleccionar = { diaSeleccionado = it }
                )

                Spacer(Modifier.height(8.dp))

                ContenidoDia(
                    diaSeleccionado = diaSeleccionado,
                    mostrarDebug = mostrarDebug,
                    onMostrarDebugChange = { mostrarDebug = it },
                    eventosFirebase = eventosFirebase,
                    eventosScraping = eventosScraping,
                    mensajeSistema = config.mensajeSistema,
                    mostrarScraping = config.mostrarScraping,
                    onEventoClick = onEventoClick
                )
            }
        }
    }
}

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
        Spacer(Modifier.height(36.dp))
        Box(Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(260.dp).shimmer(RoundedCornerShape(20.dp)))
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
                    item { Box(Modifier.width(320.dp).height(260.dp).shimmer(RoundedCornerShape(14.dp))) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun ContenidoDia(
    diaSeleccionado: String,
    mostrarDebug: Boolean,
    onMostrarDebugChange: (Boolean) -> Unit,
    eventosFirebase: List<Evento>,
    eventosScraping: List<Evento>,
    mensajeSistema: String,
    mostrarScraping: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val esHoy = FechaHelper.esHoy(diaSeleccionado)

    val fbDelDia = remember(eventosFirebase, diaSeleccionado) {
        eventosFirebase
            .filter { it.fecha == diaSeleccionado }
            .sortedBy { horaAMinutos(it.hora) }
    }

    val scDelDia = remember(eventosScraping, diaSeleccionado, mostrarScraping) {
        if (!mostrarScraping || !esHoy) emptyList()
        else eventosScraping.sortedBy { horaAMinutos(it.hora) }
    }

    val fbEnVivo = if (esHoy) fbDelDia.filter { estaEnVivo(it.hora) } else emptyList()
    val fbProximos = if (esHoy) fbDelDia.filter { esProximo(it.hora) && !estaEnVivo(it.hora) } else emptyList()
    val fbResto = if (esHoy) fbDelDia.filter { !estaEnVivo(it.hora) && !esProximo(it.hora) } else fbDelDia

    val destacado = fbEnVivo.firstOrNull() ?: fbDelDia.firstOrNull() ?: scDelDia.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 48.dp)
    ) {
        if (mensajeSistema.isNotBlank()) {
            item(key = "banner") {
                Spacer(Modifier.height(8.dp))
                BannerSistema(mensajeSistema)
                Spacer(Modifier.height(8.dp))
            }
        }

        if (fbDelDia.isEmpty() && scDelDia.isEmpty()) {
            item(key = "empty") {
                Box(
                    Modifier.fillParentMaxSize().padding(bottom = 100.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = AppIcons.bandeja,
                            contentDescription = null,
                            tint = AppColors.TextMuted,
                            modifier = Modifier.size(72.dp)
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            if (esHoy) "Sin eventos para hoy" else "Sin eventos para este día",
                            color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            if (esHoy) "Probá agregar eventos en Firestore" else "Tocá HOY para ver los del día actual",
                            color = AppColors.TextSecondary, fontSize = 13.sp
                        )
                    }
                }
            }
        } else {
            destacado?.let { ev ->
                item(key = "hero") {
                    HeroCine(ev, esHoy = esHoy) {
                        onEventoClick(ev, fbDelDia.ifEmpty { scDelDia })
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }

            if (fbEnVivo.isNotEmpty()) {
                item(key = "sec_envivo") {
                    SeparadorSeccion(
                        icono = AppIcons.enVivo,
                        titulo = "EN VIVO AHORA",
                        subtitulo = "${fbEnVivo.size} partidos corriendo",
                        color = Color(0xFFEF4444)
                    )
                }
                item(key = "row_envivo") { FilaEventos(fbEnVivo, onEventoClick, enVivo = true) }
                item(key = "sp_envivo") { Spacer(Modifier.height(24.dp)) }
            }

            if (esHoy && fbProximos.isNotEmpty()) {
                item(key = "sec_prox") {
                    SeparadorSeccion(
                        icono = AppIcons.reloj,
                        titulo = "PRÓXIMOS",
                        subtitulo = "Arrancan en las próximas horas",
                        color = AppColors.Gold
                    )
                }
                item(key = "row_prox") { FilaEventos(fbProximos, onEventoClick) }
                item(key = "sp_prox") { Spacer(Modifier.height(24.dp)) }
            }

            if (fbResto.isNotEmpty()) {
                item(key = "sec_resto") {
                    SeparadorSeccion(
                        icono = AppIcons.calendario,
                        titulo = if (esHoy) "RESTO DEL DÍA" else "AGENDA DEL DÍA",
                        subtitulo = "${fbResto.size} eventos",
                        color = AppColors.GoldDim
                    )
                }
                item(key = "row_resto") { FilaEventos(fbResto, onEventoClick) }
                item(key = "sp_resto") { Spacer(Modifier.height(24.dp)) }
            }

            if (esHoy && scDelDia.isNotEmpty()) {
                item(key = "sec_sc") {
                    SeparadorSeccion(
                        icono = AppIcons.idioma,
                        titulo = "AGENDAS EXTERNAS",
                        subtitulo = "${scDelDia.size} eventos · scraping en vivo",
                        color = AppColors.TextSecondary
                    )
                }
                val gruposSc = scDelDia.groupBy { it.groupTitle }
                gruposSc.forEach { (titulo, lista) ->
                    item(key = "sc_h_$titulo") { HeaderCategoria(titulo, lista.size) }
                    item(key = "sc_r_$titulo") { FilaEventos(lista, onEventoClick) }
                    item(key = "sc_s_$titulo") { Spacer(Modifier.height(18.dp)) }
                }
            }
        }

        if (mostrarDebug) {
            item(key = "debug_overlay") {
                DebugOverlay { onMostrarDebugChange(false) }
            }
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

// ─────────────────────────────────────────────────────────────
// Selector de días
// ─────────────────────────────────────────────────────────────

@Composable
private fun SelectorDias(
    dias: List<DiaItem>,
    seleccionado: String,
    onSeleccionar: (String) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().fadeInOnLoad(400, delayMs = 100)
    ) {
        items(count = dias.size) { index ->
            val dia = dias[index]
            val activo = dia.fecha == seleccionado
            var focused by remember { mutableStateOf(false) }

            val bg by animateColorAsState(
                when {
                    activo -> AppColors.Gold
                    focused -> AppColors.CardFocus
                    else -> AppColors.Surface
                },
                tween(180), label = "diaBg"
            )
            val texto by animateColorAsState(
                when {
                    activo -> Color.Black
                    focused -> AppColors.GoldBright
                    else -> AppColors.TextSecondary
                },
                tween(180), label = "diaTxt"
            )
            val border by animateColorAsState(
                when {
                    activo -> AppColors.GoldBright
                    focused -> AppColors.GoldBright
                    else -> AppColors.Gold.copy(alpha = 0.2f)
                },
                tween(180), label = "diaBorder"
            )

            Box(
                Modifier
                    .onFocusChanged { focused = it.isFocused }
                    .focusable()
                    .clip(RoundedCornerShape(10.dp))
                    .background(bg)
                    .border(2.dp, border, RoundedCornerShape(10.dp))
                    .clickable { onSeleccionar(dia.fecha) }
                    .padding(horizontal = 18.dp, vertical = 10.dp)
            ) {
                Text(
                    dia.etiqueta,
                    color = texto,
                    fontSize = 13.sp,
                    fontWeight = if (activo) FontWeight.Black else FontWeight.SemiBold,
                    letterSpacing = if (activo) 1.sp else 0.sp
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// HERO cinematográfico
// ─────────────────────────────────────────────────────────────

@Composable
private fun HeroCine(evento: Evento, esHoy: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val pulse = rememberPulseAlpha(min = 0.4f, max = 1f, durationMs = 800)
    val enVivo = esHoy && estaEnVivo(evento.hora)

    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else Color.Transparent,
        tween(180), label = "heroBorder"
    )
    val borderWidth by animateDpAsState(if (focused) 3.dp else 0.dp, tween(180), label = "heroW")

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .fadeInOnLoad(durationMs = 500, delayMs = 150)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.01f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(20.dp))
            .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
            .height(300.dp)
    ) {
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }

        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color.Black.copy(alpha = 0.95f),
                        Color.Black.copy(alpha = 0.6f),
                        Color.Transparent
                    )
                )
            )
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                )
            )
        )

        Column(
            Modifier.fillMaxSize().padding(28.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (enVivo) {
                    Box(
                        Modifier.alpha(pulse)
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color(0xFFEF4444))
                            .padding(horizontal = 12.dp, vertical = 5.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = AppIcons.enVivo,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(10.dp)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text("EN VIVO", color = Color.White, fontSize = 12.sp,
                                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                        }
                    }
                    Spacer(Modifier.width(10.dp))
                } else {
                    Box(
                        Modifier.clip(RoundedCornerShape(8.dp))
                            .background(AppColors.Gold)
                            .padding(horizontal = 12.dp, vertical = 5.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = AppIcons.estrella,
                                contentDescription = null,
                                tint = Color.Black,
                                modifier = Modifier.size(14.dp)
                            )
                            Spacer(Modifier.width(5.dp))
                            Text("DESTACADO", color = Color.Black, fontSize = 12.sp,
                                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                        }
                    }
                    Spacer(Modifier.width(10.dp))
                }
                Box(
                    Modifier.clip(RoundedCornerShape(8.dp))
                        .background(Color(0xAA000000))
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                ) {
                    Text("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                        color = AppColors.Gold, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Column {
                Text(
                    evento.descripcion,
                    color = Color.White,
                    fontSize = 42.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    lineHeight = 46.sp
                )
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = AppIcons.reloj,
                        contentDescription = null,
                        tint = AppColors.GoldBright,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        FechaHelper.badgeCard(evento.fecha, evento.hora),
                        color = AppColors.GoldBright, fontSize = 18.sp, fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.width(18.dp))
                    Icon(
                        imageVector = AppIcons.senal,
                        contentDescription = null,
                        tint = Color(0xFFD1D5DB),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(evento.fuente, color = Color(0xFFD1D5DB), fontSize = 15.sp)
                    Spacer(Modifier.width(18.dp))
                    Icon(
                        imageVector = AppIcons.canales,
                        contentDescription = null,
                        tint = Color(0xFFD1D5DB),
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("${evento.embeds.size} canales", color = Color(0xFFD1D5DB), fontSize = 15.sp)
                }
                Spacer(Modifier.height(18.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                            .padding(horizontal = 24.dp, vertical = 12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = AppIcons.play,
                                contentDescription = null,
                                tint = Color.Black,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                if (enVivo) "VER AHORA" else "VER DETALLES",
                                color = Color.Black, fontSize = 15.sp,
                                fontWeight = FontWeight.Black, letterSpacing = 1.sp
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Secciones y headers
// ─────────────────────────────────────────────────────────────

@Composable
private fun SeparadorSeccion(
    icono: ImageVector,
    titulo: String,
    subtitulo: String,
    color: Color
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp).fadeInOnLoad(400)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(32.dp).clip(RoundedCornerShape(3.dp)).background(color))
            Spacer(Modifier.width(12.dp))
            Icon(
                imageVector = icono,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(10.dp))
            Text(titulo, color = color, fontSize = 24.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(4.dp))
        Text(subtitulo, color = AppColors.TextSecondary, fontSize = 13.sp,
            modifier = Modifier.padding(start = 34.dp))
    }
}

@Composable
private fun BannerSistema(mensaje: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp)
            .fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(Brush.horizontalGradient(listOf(
                AppColors.Gold.copy(alpha = 0.25f),
                AppColors.Gold.copy(alpha = 0.08f)
            )))
            .border(1.dp, AppColors.Gold.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.megafono,
            contentDescription = null,
            tint = AppColors.GoldBright,
            modifier = Modifier.size(24.dp)
        )
        Spacer(Modifier.width(14.dp))
        Text(mensaje, color = AppColors.GoldBright, fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold, lineHeight = 18.sp)
    }
}

@Composable
private fun HeaderFutTV(
    textoBienvenida: String,
    totalEventos: Int,
    totalCanales: Int,
    refrescando: Boolean,
    onRefrescar: () -> Unit,
    onIrAAjustes: () -> Unit,
    onIrABusqueda: () -> Unit
) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 24.dp).fadeInOnLoad(durationMs = 400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("⚽", fontSize = 32.sp)
        Spacer(Modifier.width(10.dp))
        Text("FutTV", color = AppColors.GoldBright, fontSize = 34.sp,
            fontWeight = FontWeight.Black, letterSpacing = 3.sp)
        Spacer(Modifier.width(16.dp))
        Box(
            Modifier.alpha(pulse)
                .clip(RoundedCornerShape(8.dp))
                .background(AppColors.Gold.copy(alpha = 0.15f))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = AppIcons.enVivo,
                    contentDescription = null,
                    tint = AppColors.Gold,
                    modifier = Modifier.size(8.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text("EN VIVO", color = AppColors.Gold, fontSize = 11.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
            }
        }
        Spacer(Modifier.weight(1f))
        Text("$totalEventos eventos · $totalCanales canales",
            color = AppColors.TextSecondary, fontSize = 12.sp)
        Spacer(Modifier.width(16.dp))

        BotonHeader(icono = AppIcons.buscar, onClick = onIrABusqueda, label = "Buscar")
        Spacer(Modifier.width(8.dp))
        BotonHeader(icono = AppIcons.ajustes, onClick = onIrAAjustes, label = "Ajustes")
        Spacer(Modifier.width(8.dp))
        BotonHeader(
            icono = if (refrescando) AppIcons.cargando else AppIcons.refrescar,
            onClick = { if (!refrescando) onRefrescar() },
            label = "Actualizar"
        )
    }
}

@Composable
private fun BotonHeader(icono: ImageVector, label: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .size(44.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.12f))
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
                RoundedCornerShape(10.dp)
            )
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icono,
            contentDescription = label,
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(22.dp)
        )
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
        Box(Modifier.width(5.dp).height(26.dp).clip(RoundedCornerShape(3.dp)).background(color))
        Spacer(Modifier.width(14.dp))
        Text(icono, fontSize = 20.sp)
        Spacer(Modifier.width(8.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.clip(RoundedCornerShape(10.dp))
            .background(color.copy(alpha = 0.2f))
            .padding(horizontal = 10.dp, vertical = 3.dp)) {
            Text("$total", color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Cards premium
// ─────────────────────────────────────────────────────────────

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    enVivo: Boolean = false
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        itemsIndexed(items = lista, key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }) { index, ev ->
            Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 200 + index * 60, slideFromDp = 20f)) {
                EventoCardPremium(ev, enVivo = enVivo) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun EventoCardPremium(ev: Evento, enVivo: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "cc"
    )

    Column(
        Modifier
            .width(320.dp)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(16.dp))
            .background(AppColors.Card)
            .border(borderWidth, borderColor, RoundedCornerShape(16.dp))
    ) {
        Box(
            Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().alpha(0.75f)
                )
            } else {
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Text("⚽", fontSize = 70.sp)
                }
            }

            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                    )
                )
            )

            if (enVivo || (FechaHelper.esHoy(ev.fecha) && estaEnVivo(ev.hora))) {
                Box(
                    Modifier.align(Alignment.TopStart).padding(10.dp).alpha(pulse)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFEF4444))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.enVivo,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(8.dp)
                        )
                        Spacer(Modifier.width(5.dp))
                        Text("LIVE", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    }
                }
            }

            Box(
                Modifier.align(Alignment.TopEnd).padding(10.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(AppColors.Gold)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text(
                    FechaHelper.badgeCard(ev.fecha, ev.hora),
                    color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black
                )
            }

            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 19.sp,
                modifier = Modifier.align(Alignment.BottomStart).padding(12.dp)
            )
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(color))
            Spacer(Modifier.width(6.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            Icon(
                imageVector = if (focused) AppIcons.play else AppIcons.adelante,
                contentDescription = null,
                tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────
// Debug overlay
// ─────────────────────────────────────────────────────────────

@Composable
private fun DebugOverlay(onCerrar: () -> Unit) {
    val lineas by DebugLog.lineas.collectAsState()
    Box(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 20.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xEE000000))
            .border(2.dp, Color(0xFF4ADE80), RoundedCornerShape(12.dp))
            .padding(16.dp)
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = AppIcons.buscarLupa,
                    contentDescription = null,
                    tint = Color(0xFF4ADE80),
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text("DEBUG", color = Color(0xFF4ADE80), fontSize = 16.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                Text("toque largo en ⚽ FutTV para cerrar", color = Color(0xFF94A3B8), fontSize = 11.sp)
            }
            Spacer(Modifier.height(10.dp))
            if (lineas.isEmpty()) {
                Text("Sin logs todavía", color = Color(0xFF94A3B8), fontSize = 12.sp)
            } else {
                lineas.forEach { l ->
                    Text(l, color = if (l.contains("❌")) Color(0xFFEF4444) else Color(0xFFE2E8F0),
                        fontSize = 11.sp, lineHeight = 15.sp,
                        modifier = Modifier.padding(vertical = 1.dp))
                }
            }
        }
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -q "import com.anonimus757.tvapp.ui.theme.AppIcons" "$PKG_DIR/HomeScreen.kt" && echo "  ✓ Import de AppIcons"
grep -q "Icons" "$PKG_DIR/HomeScreen.kt" || grep -q "AppIcons\." "$PKG_DIR/HomeScreen.kt" && echo "  ✓ Usa iconos Material"
grep -q "imageVector = AppIcons.buscar" "$PKG_DIR/HomeScreen.kt" && echo "  ✓ Botón buscar con icono"

echo ""
echo "✅✅✅ Paso 34b completo — HomeScreen con iconos Material"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"