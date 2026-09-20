#!/bin/bash
set -e

echo "📁 Paso 13: Pantalla de detalle intermedia..."

# ========== Screen.kt ==========
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
                            VolverA.Player -> Screen.Player(
                                s.evento, s.evento.embeds.first(), s.todos
                            )
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
                                // Al cambiar de evento desde el panel, mostramos sus canales
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

# ========== EventDetailScreen.kt (nuevo, bonito) ==========
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

private val BG = Color(0xFF0A0F1E)
private val CARD = Color(0xFF1E293B)
private val CARD_FOCUS = Color(0xFF334155)
private val ACENTO = Color(0xFF38BDF8)
private val TEXTO = Color(0xFFE2E8F0)
private val GRIS = Color(0xFF94A3B8)
private val VERDE = Color(0xFF4ADE80)

@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    Box(Modifier.fillMaxSize().background(BG)) {
        Column(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 32.dp)) {

            // Header con info del evento
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(90.dp).clip(RoundedCornerShape(12.dp)).background(Color(0xFF0F172A)),
                    contentAlignment = Alignment.Center
                ) {
                    AsyncImage(
                        model = evento.imagen,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(70.dp)
                    )
                }
                Spacer(Modifier.width(22.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        evento.descripcion,
                        color = TEXTO,
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "${evento.hora} · ${evento.fuente} · ${evento.groupTitle}",
                        color = GRIS,
                        fontSize = 15.sp
                    )
                }
            }

            Spacer(Modifier.height(36.dp))

            Text(
                "🎬 Elige un canal para reproducir",
                color = ACENTO,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.height(16.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(evento.embeds, key = { it.url }) { embed ->
                    CanalCard(embed) { onCanalClick(embed) }
                }
            }
        }
    }
}

@Composable
private fun CanalCard(embed: Embed, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) CARD_FOCUS else CARD)
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(46.dp)
                .clip(CircleShape)
                .background(if (focused) VERDE else ACENTO),
            contentAlignment = Alignment.Center
        ) {
            Text("▶", color = Color.Black, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.width(18.dp))
        Text(
            embed.nombre,
            color = TEXTO,
            fontSize = 19.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f)
        )
        Text(
            if (focused) "▶ Reproducir" else "OK para reproducir",
            color = if (focused) VERDE else GRIS,
            fontSize = 14.sp
        )
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 13 completo"
find app/src/main/java -type f