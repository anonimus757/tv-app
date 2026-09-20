#!/bin/bash
set -e

echo "📁 Paso 16: UI estilo Netflix/IPTV pro..."

# ========== Theme.kt (colores globales) ==========
mkdir -p app/src/main/java/com/anonimus757/tvapp/ui/theme
cat > app/src/main/java/com/anonimus757/tvapp/ui/theme/Theme.kt << 'KTEOF'
package com.anonimus757.tvapp.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    val Background = Color(0xFF0A0E1A)
    val BackgroundGradient = Color(0xFF0F172A)
    val Surface = Color(0xFF151B2E)
    val SurfaceLight = Color(0xFF1E293B)
    val SurfaceFocus = Color(0xFF2D3B55)
    val Card = Color(0xFF1A2236)

    val Primary = Color(0xFF3B82F6)
    val Accent = Color(0xFF38BDF8)
    val AccentGreen = Color(0xFF4ADE80)
    val AccentYellow = Color(0xFFFACC15)
    val AccentRed = Color(0xFFEF4444)
    val AccentPurple = Color(0xFFA78BFA)

    val TextPrimary = Color(0xFFF1F5F9)
    val TextSecondary = Color(0xFF94A3B8)
    val TextMuted = Color(0xFF64748B)

    // Colores por fuente (para headers)
    fun fuenteColor(groupTitle: String): Color = when {
        groupTitle.contains("EVENTOS 2") -> Color(0xFFF59E0B)   // Naranja
        groupTitle.contains("EVENTOS 3") -> Color(0xFFA78BFA)   // Púrpura
        else -> Color(0xFF38BDF8)                                // Azul (Eventos 1)
    }

    fun fuenteIcono(groupTitle: String): String = when {
        groupTitle.contains("EVENTOS 2") -> "⚽"
        groupTitle.contains("EVENTOS 3") -> "🏆"
        else -> "🎯"
    }
}
KTEOF

# ========== HomeScreen.kt (estilo Netflix) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.ui.theme.AppColors

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
        if (cargando) {
            CargandoEstado(status)
        } else if (eventos.isEmpty()) {
            VacioEstado(status)
        } else {
            ContenidoHome(eventos, onEventoClick)
        }
    }
}

@Composable
private fun CargandoEstado(status: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = AppColors.Accent, strokeWidth = 3.dp)
            Spacer(Modifier.height(20.dp))
            Text("🎛️ TV App", color = AppColors.Accent, fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 16.sp)
        }
    }
}

@Composable
private fun VacioEstado(status: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("📭", fontSize = 60.sp)
            Spacer(Modifier.height(16.dp))
            Text("No hay eventos", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(8.dp))
            Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
        }
    }
}

@Composable
private fun ContenidoHome(
    eventos: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val grupos = eventos.groupBy { it.groupTitle }
    val totalCanales = eventos.sumOf { it.embeds.size }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 28.dp, bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Header de la app
        item(key = "app_header") {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🎛️", fontSize = 30.sp)
                Spacer(Modifier.width(12.dp))
                Text(
                    "TV App",
                    color = AppColors.TextPrimary,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.width(16.dp))
                Text("En vivo", color = AppColors.Accent, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("📅", fontSize = 14.sp)
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "${eventos.size} eventos · $totalCanales canales",
                        color = AppColors.TextSecondary,
                        fontSize = 13.sp
                    )
                }
            }
        }

        item(key = "space_1") { Spacer(Modifier.height(16.dp)) }

        // Una fila horizontal por cada fuente
        grupos.forEach { (titulo, lista) ->
            item(key = "header_$titulo") {
                HeaderCategoria(titulo, lista.size)
            }

            item(key = "row_$titulo") {
                FilaEventos(lista, onEventoClick)
            }

            item(key = "space_$titulo") { Spacer(Modifier.height(28.dp)) }
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
            .padding(horizontal = 40.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .width(5.dp)
                .height(28.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(color)
        )
        Spacer(Modifier.width(14.dp))
        Text(icono, fontSize = 22.sp)
        Spacer(Modifier.width(8.dp))
        Text(
            titulo,
            color = AppColors.TextPrimary,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.2f))
                .padding(horizontal = 10.dp, vertical = 3.dp)
        ) {
            Text(
                "$total",
                color = color,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val listState = rememberLazyListState()

    LazyRow(
        state = listState,
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        items(lista, key = { "${it.fuente}_${it.hora}_${it.descripcion}" }) { ev ->
            EventoCardPro(ev) { onEventoClick(ev, lista) }
        }
    }
}

@Composable
private fun EventoCardPro(ev: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)

    Column(
        Modifier
            .width(260.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(if (focused) AppColors.SurfaceFocus else AppColors.Card)
            .padding(14.dp)
    ) {
        // Imagen/logo del evento
        Box(
            Modifier
                .fillMaxWidth()
                .height(140.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(
                            AppColors.SurfaceLight,
                            AppColors.Surface
                        )
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = ev.imagen,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(100.dp)
            )

            // Hora arriba a la derecha
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(color.copy(alpha = 0.9f))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    ev.hora,
                    color = Color.Black,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        Spacer(Modifier.height(12.dp))

        // Título
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

        // Footer con canales
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(AppColors.AccentGreen)
            )
            Spacer(Modifier.width(6.dp))
            Text(
                "${ev.embeds.size} canales",
                color = AppColors.TextSecondary,
                fontSize = 12.sp
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (focused) "▶" else "→",
                color = if (focused) AppColors.AccentGreen else AppColors.TextMuted,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}
KTEOF

# ========== EventDetailScreen.kt (más visual) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.ui.theme.AppColors

@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    val color = AppColors.fuenteColor(evento.groupTitle)

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, AppColors.BackgroundGradient)
                )
            )
    ) {
        Column(Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 36.dp)) {

            // Header con info del evento
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(110.dp)
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
                        modifier = Modifier.size(80.dp)
                    )
                }
                Spacer(Modifier.width(26.dp))
                Column(Modifier.weight(1f)) {
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
                        Box(
                            Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(color.copy(alpha = 0.2f))
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Text(
                                "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                                color = color,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "${evento.hora} · ${evento.fuente}",
                            color = AppColors.TextSecondary,
                            fontSize = 14.sp
                        )
                    }
                }
            }

            Spacer(Modifier.height(44.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🎬", fontSize = 20.sp)
                Spacer(Modifier.width(8.dp))
                Text(
                    "Elige un canal para reproducir",
                    color = AppColors.TextPrimary,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.width(12.dp))
                Box(
                    Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(AppColors.Accent.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text(
                        "${evento.embeds.size}",
                        color = AppColors.Accent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            Spacer(Modifier.height(20.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(evento.embeds, key = { it.url }) { embed ->
                    CanalCardPro(embed) { onCanalClick(embed) }
                }
            }
        }
    }
}

@Composable
private fun CanalCardPro(embed: Embed, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(if (focused) AppColors.SurfaceFocus else AppColors.Card)
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(50.dp)
                .clip(CircleShape)
                .background(
                    if (focused) AppColors.AccentGreen else AppColors.Accent
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "▶",
                color = Color.Black,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(Modifier.width(20.dp))
        Text(
            embed.nombre,
            color = AppColors.TextPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f)
        )
        Text(
            if (focused) "▶ Reproducir" else "OK para reproducir",
            color = if (focused) AppColors.AccentGreen else AppColors.TextMuted,
            fontSize = 14.sp,
            fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 16 completo — UI estilo Netflix lista"
find app/src/main/java/com/anonimus757/tvapp/ui -type f