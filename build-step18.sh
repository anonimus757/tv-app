#!/bin/bash
set -e

echo "📁 Paso 18: FutTV + UI premium (solo eventos)..."

# ========== Nombre de la app ==========
cat > app/src/main/res/values/strings.xml << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FutTV</string>
</resources>
XMLEOF

# ========== Eliminar archivos de canales ==========
rm -f app/src/main/java/com/anonimus757/tvapp/ui/LiveChannelsScreen.kt
rm -f app/src/main/java/com/anonimus757/tvapp/ui/PlayerCanalScreen.kt
rm -f app/src/main/java/com/anonimus757/tvapp/data/ChannelRepository.kt

echo "🗑️ Archivos de canales eliminados"

# ========== Screen.kt (limpio) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/Screen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen

    data class Detail(
        val evento: Evento,
        val todos: List<Evento>,
        val volverA: VolverA = VolverA.Home
    ) : Screen

    data class Player(
        val evento: Evento,
        val embed: Embed,
        val todos: List<Evento>
    ) : Screen
}

enum class VolverA { Home, Player }
KTEOF

# ========== MainActivity.kt ==========
cat > app/src/main/java/com/anonimus757/tvapp/MainActivity.kt << 'KTEOF'
package com.anonimus757.tvapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import com.anonimus757.tvapp.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            var screen by remember { mutableStateOf<Screen>(Screen.Home) }

            when (val s = screen) {
                is Screen.Home -> HomeScreen(
                    onEventoClick = { evento, todos ->
                        screen = Screen.Detail(evento, todos, VolverA.Home)
                    }
                )

                is Screen.Detail -> EventDetailScreen(
                    evento = s.evento,
                    onCanalClick = { embed ->
                        screen = Screen.Player(s.evento, embed, s.todos)
                    },
                    onBack = {
                        screen = when (s.volverA) {
                            VolverA.Home -> Screen.Home
                            VolverA.Player -> Screen.Player(s.evento, s.evento.embeds.first(), s.todos)
                        }
                    }
                )

                is Screen.Player -> {
                    key(s.evento.descripcion + "|" + s.embed.url) {
                        PlayerScreen(
                            evento = s.evento,
                            embedInicial = s.embed,
                            todosEventos = s.todos,
                            onBack = { screen = Screen.Home },
                            onEventoChange = { nuevo ->
                                screen = Screen.Detail(nuevo, s.todos, VolverA.Player)
                            }
                        )
                    }
                }
            }
        }
    }
}
KTEOF

# ========== Theme.kt (premium dorado) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/theme/Theme.kt << 'KTEOF'
package com.anonimus757.tvapp.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    // Fondos
    val Background = Color(0xFF050505)
    val BackgroundGradient = Color(0xFF0F0F0F)
    val Surface = Color(0xFF121212)
    val SurfaceLight = Color(0xFF1A1A1A)
    val SurfaceFocus = Color(0xFF2A2A2A)
    val Card = Color(0xFF111111)
    val CardFocus = Color(0xFF1C1C1C)

    // Dorados
    val Gold = Color(0xFFD4AF37)
    val GoldBright = Color(0xFFFFD700)
    val GoldDim = Color(0xFF8B6914)
    val GoldGlow = Color(0x33FFD700)

    // Acentos
    val AccentGreen = Color(0xFF4ADE80)
    val AccentRed = Color(0xFFEF4444)
    val AccentYellow = Color(0xFFFACC15)

    // Texto
    val TextPrimary = Color(0xFFF5F5F5)
    val TextSecondary = Color(0xFFA0A0A0)
    val TextMuted = Color(0xFF606060)

    fun fuenteColor(groupTitle: String): Color = when {
        groupTitle.contains("EVENTOS 2") -> Color(0xFFE8A020)
        groupTitle.contains("EVENTOS 3") -> Color(0xFFB8860B)
        else -> Gold
    }

    fun fuenteIcono(groupTitle: String): String = when {
        groupTitle.contains("EVENTOS 2") -> "⚽"
        groupTitle.contains("EVENTOS 3") -> "🏆"
        else -> "🎯"
    }
}
KTEOF

# ========== HomeScreen.kt (con hero destacado + UI premium) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
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
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = AppColors.Gold, strokeWidth = 3.dp)
                    Spacer(Modifier.height(24.dp))
                    Text("FutTV", color = AppColors.Gold, fontSize = 44.sp, fontWeight = FontWeight.Black, letterSpacing = 4.sp)
                    Spacer(Modifier.height(12.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 16.sp)
                }
            }
        } else if (eventos.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📭", fontSize = 60.sp)
                    Spacer(Modifier.height(16.dp))
                    Text("Sin eventos", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
                }
            }
        } else {
            ContenidoHome(eventos, onEventoClick)
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
    val destacado = eventos.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp)
    ) {
        // Header con logo FutTV
        item(key = "header") {
            HeaderFutTV(eventos.size, totalCanales)
        }

        // Hero destacado
        if (destacado != null) {
            item(key = "hero") {
                Spacer(Modifier.height(20.dp))
                HeroEvento(destacado) { onEventoClick(destacado, eventos) }
                Spacer(Modifier.height(30.dp))
            }
        }

        // Filas por categoría
        grupos.forEach { (titulo, lista) ->
            item(key = "header_$titulo") { HeaderCategoria(titulo, lista.size) }
            item(key = "row_$titulo") { FilaEventos(lista, onEventoClick) }
            item(key = "space_$titulo") { Spacer(Modifier.height(28.dp)) }
        }
    }
}

@Composable
private fun HeaderFutTV(totalEventos: Int, totalCanales: Int) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp),
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

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
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
            .border(
                width = if (focused) 3.dp else 1.dp,
                color = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
                shape = RoundedCornerShape(20.dp)
            )
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
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 4.dp),
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
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(
                width = if (focused) 3.dp else 1.dp,
                color = if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
                shape = RoundedCornerShape(14.dp)
            )
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
KTEOF

echo ""
echo "✅✅✅ Paso 18 completo — FutTV"
find app/src/main/java/com/anonimus757/tvapp -type fs