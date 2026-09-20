#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
mkdir -p "$PKG_DIR/ui"

echo "📝 Reescribiendo HomeScreen.kt con orden por hora..."

cat > "$PKG_DIR/ui/HomeScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.animations.shimmer
import com.anonimus757.tvapp.ui.theme.AppColors

/**
 * Convierte un string de hora a minutos desde las 00:00.
 * Acepta formatos: "20:30", "20:30 hs", "Hoy 20:30", "20:30 - 22:00".
 * Si no puede parsear, devuelve Int.MAX_VALUE (van al final).
 */
private fun horaAMinutos(hora: String): Int {
    val match = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return Int.MAX_VALUE
    val h = match.groupValues[1].toIntOrNull() ?: return Int.MAX_VALUE
    val m = match.groupValues[2].toIntOrNull() ?: return Int.MAX_VALUE
    if (h !in 0..23 || m !in 0..59) return Int.MAX_VALUE
    return h * 60 + m
}

@Composable
fun HomeScreen(onEventoClick: (Evento, List<Evento>) -> Unit) {
    var eventos by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("Conectando...") }

    LaunchedEffect(Unit) {
        try {
            eventos = EventRepository.obtenerTodosLosEventos { msg -> status = msg }
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargando = false
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
            cargando -> SkeletonHome(status)
            eventos.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📭", fontSize = 60.sp)
                    Spacer(Modifier.height(16.dp))
                    Text("Sin eventos", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
                }
            }
            else -> ContenidoHome(eventos, onEventoClick)
        }
    }
}

@Composable
private fun SkeletonHome(status: String) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(top = 32.dp)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(350),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("⚽", fontSize = 32.sp)
            Spacer(Modifier.width(10.dp))
            Text(
                "FutTV",
                color = AppColors.GoldBright,
                fontSize = 34.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 3.sp
            )
            Spacer(Modifier.width(20.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
        }

        Spacer(Modifier.height(36.dp))

        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 40.dp)
                .height(200.dp)
                .shimmer(RoundedCornerShape(20.dp))
        )

        Spacer(Modifier.height(40.dp))

        repeat(2) {
            Box(
                Modifier
                    .padding(horizontal = 40.dp)
                    .width(260.dp)
                    .height(30.dp)
                    .shimmer(RoundedCornerShape(8.dp))
            )
            Spacer(Modifier.height(14.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 40.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                userScrollEnabled = false
            ) {
                repeat(4) {
                    item {
                        Box(
                            Modifier
                                .width(260.dp)
                                .height(240.dp)
                                .shimmer(RoundedCornerShape(14.dp))
                        )
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun ContenidoHome(
    eventos: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    // ── PASO 21: orden por hora ascendente ─────────────────
    // Ordeno global (para el hero y los callbacks) y ordeno
    // cada grupo por separado (para las filas horizontales).
    val eventosOrdenados = remember(eventos) {
        eventos.sortedBy { horaAMinutos(it.hora) }
    }
    val grupos = remember(eventosOrdenados) {
        eventosOrdenados
            .groupBy { it.groupTitle }
            .mapValues { (_, lista) -> lista.sortedBy { horaAMinutos(it.hora) } }
    }
    val totalCanales = eventosOrdenados.sumOf { it.embeds.size }
    val destacado = eventosOrdenados.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp)
    ) {
        item(key = "header") {
            HeaderFutTV(eventosOrdenados.size, totalCanales)
        }

        if (destacado != null) {
            item(key = "hero") {
                Spacer(Modifier.height(20.dp))
                HeroEvento(destacado) { onEventoClick(destacado, eventosOrdenados) }
                Spacer(Modifier.height(30.dp))
            }
        }

        grupos.forEach { (titulo, lista) ->
            item(key = "header_$titulo") { HeaderCategoria(titulo, lista.size) }
            item(key = "row_$titulo") { FilaEventos(lista, onEventoClick) }
            item(key = "space_$titulo") { Spacer(Modifier.height(28.dp)) }
        }
    }
}

@Composable
private fun HeaderFutTV(totalEventos: Int, totalCanales: Int) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .fadeInOnLoad(durationMs = 400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = 32.sp)
            Spacer(Modifier.width(10.dp))
            Text(
                "FutTV",
                color = AppColors.GoldBright,
                fontSize = 34.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 3.sp
            )
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
            Text("● EN VIVO", color = AppColors.Gold, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        }
        Spacer(Modifier.weight(1f))
        Text("$totalEventos eventos · $totalCanales canales", color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun HeroEvento(evento: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(evento.groupTitle)
    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180),
        label = "heroBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
        animationSpec = tween(180),
        label = "heroBorderColor"
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
            .background(
                Brush.horizontalGradient(
                    listOf(
                        AppColors.SurfaceLight,
                        AppColors.Surface
                    )
                )
            )
            .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
            .padding(24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(140.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(AppColors.SurfaceLight, AppColors.Surface)
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(110.dp)
            )
        }

        Spacer(Modifier.width(28.dp))

        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(AppColors.Gold)
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("⭐ DESTACADO", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
                Spacer(Modifier.width(10.dp))
                Box(
                    Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}", color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(Modifier.height(14.dp))

            Text(
                evento.descripcion,
                color = AppColors.TextPrimary,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = 38.sp
            )

            Spacer(Modifier.height(10.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐", fontSize = 14.sp)
                Spacer(Modifier.width(6.dp))
                Text(evento.hora, color = AppColors.GoldBright, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(16.dp))
                Text("📡 ${evento.fuente}", color = AppColors.TextSecondary, fontSize = 14.sp)
                Spacer(Modifier.width(16.dp))
                Text("📺 ${evento.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 14.sp)
            }

            Spacer(Modifier.height(16.dp))

            Box(
                Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                    .padding(horizontal = 22.dp, vertical = 12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("▶", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(8.dp))
                    Text("VER AHORA", color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
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
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp, vertical = 4.dp)
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
private fun FilaEventos(lista: List<Evento>, onEventoClick: (Evento, List<Evento>) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
            Box(
                Modifier.fadeInOnLoad(
                    durationMs = 400,
                    delayMs = 200 + index * 60,
                    slideFromDp = 20f
                )
            ) {
                EventoCardPro(ev) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun EventoCardPro(ev: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180),
        label = "cardBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        animationSpec = tween(180),
        label = "cardBorderColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (focused) AppColors.CardFocus else AppColors.Card,
        animationSpec = tween(180),
        label = "cardBg"
    )

    Column(
        Modifier
            .width(260.dp)
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
            Modifier.fillMaxWidth().height(150.dp).clip(RoundedCornerShape(10.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = ev.imagen,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(105.dp)
            )

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
            ev.descripcion,
            color = AppColors.TextPrimary,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            lineHeight = 19.sp,
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
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}
EOF

echo ""
echo "🔎 Verificando archivo..."
ls -la "$PKG_DIR/ui/HomeScreen.kt"

echo ""
echo "✅✅✅ Paso 21 completo — eventos ordenados por hora ascendente"
echo ""
echo "🚀 Ahora compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"