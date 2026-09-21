#!/bin/bash
set -e

echo "🔧 Aplicando mejoras de TV..."

# ═══════════════════════════════════════════════════════════
# 1. MODELS.KT: agregar campo logo a Embed
# ═══════════════════════════════════════════════════════════
MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
cp "$MODELS" "${MODELS}.bak.logos.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Actualizar data class Embed
viejo = '''data class Embed(
    val nombre: String,
    val url: String,
    val referer: String
)'''

nuevo = '''data class Embed(
    val nombre: String,
    val url: String,
    val referer: String,
    val logo: String = ""  // URL del logo del canal (opcional)
)'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ Embed extendido con campo 'logo'")
else:
    print("⚠️ No matcheó Embed (puede que ya esté actualizado)")
PYEOF

# ═══════════════════════════════════════════════════════════
# 2. EVENTREPOSITORY.KT: parsear logo
# ═══════════════════════════════════════════════════════════
REPO="app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
cp "$REPO" "${REPO}.bak.logos.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

viejo = '''            val embeds = embedsList.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim())
            }'''

nuevo = '''            val embeds = embedsList.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                val logo = (m["logo"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim(), logo.trim())
            }'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ EventRepository parsea logo")
else:
    print("⚠️ No matcheó el bloque de embeds en EventRepository")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3. EVENTDETAILSCREEN.KT: rediseño completo
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
cp "$DETAIL" "${DETAIL}.bak.tvmejoras.$(date +%s)"

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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.theme.AppColors
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
                Modifier.fillMaxWidth().padding(horizontal = padH, vertical = if (esTV) 16.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BotonVolverCompact(onBack, esTV)
            }

            // Hero compacto (250dp TV / 180dp celu)
            HeroEventoCompacto(evento, esTV, esMovil, estado, minutosHasta(evento))

            Spacer(Modifier.height(if (esTV) 20.dp else 14.dp))

            // Panel de info del evento (info rica)
            PanelInfoEvento(evento, estado, esTV, esMovil)

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
// BOTÓN VOLVER
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
            .clip(RoundedCornerShape(12.dp))
            .background(
                if (focused) Color(0xFFFFD700)
                else Color.White.copy(alpha = 0.08f)
            )
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) Color(0xFFFFD700) else Color.White.copy(alpha = 0.15f),
                RoundedCornerShape(12.dp)
            )
            .padding(horizontal = if (esTV) 16.dp else 12.dp, vertical = if (esTV) 10.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else Color.White,
            modifier = Modifier.size(if (esTV) 20.dp else 16.dp)
        )
        Spacer(Modifier.width(if (esTV) 8.dp else 6.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else Color.White,
            fontSize = if (esTV) 14.sp else 13.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

// ═══════════════════════════════════════════════════════════
// HERO COMPACTO (250dp TV / 180dp celu)
// ═══════════════════════════════════════════════════════════

@Composable
private fun HeroEventoCompacto(
    evento: Evento, esTV: Boolean, esMovil: Boolean,
    estado: EstadoEvento, minsHasta: Int?
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val altura = if (esTV) 220.dp else if (esMovil) 140.dp else 180.dp
    val tituloSize = if (esTV) 30.sp else if (esMovil) 20.sp else 24.sp

    Box(Modifier.fillMaxWidth().height(altura)) {
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen, contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    listOf(
                        Color(0xFF0A0A0F),
                        Color(0xFF0A0A0F).copy(alpha = 0.85f),
                        Color(0xFF0A0A0F).copy(alpha = 0.3f),
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
            Modifier.fillMaxSize().padding(horizontal = padH).padding(bottom = if (esTV) 20.dp else 12.dp),
            verticalArrangement = Arrangement.Bottom
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (estado) {
                    EstadoEvento.EN_VIVO -> BadgePulse("● EN VIVO", Color(0xFFFF3B30), Color.White, esTV)
                    EstadoEvento.FINALIZADO -> BadgeEstado("✓ FINALIZADO", Color.White.copy(alpha = 0.15f), Color.White, esTV)
                    EstadoEvento.PROXIMO -> {
                        if (minsHasta != null && minsHasta <= 60) {
                            BadgeEstado("⏰ EN ${minsHasta}MIN", Color(0xFFFFA500), Color.Black, esTV)
                        } else {
                            BadgeEstado("🕐 PRÓXIMO", Color(0xFFFFD700), Color.Black, esTV)
                        }
                    }
                }
            }
            Spacer(Modifier.height(if (esTV) 12.dp else 8.dp))
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
        }
    }
}

@Composable
private fun BadgePulse(texto: String, bg: Color, fg: Color, esTV: Boolean) {
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 900)
    Box(
        Modifier.alpha(pulse).clip(RoundedCornerShape(6.dp)).background(bg)
            .padding(horizontal = if (esTV) 12.dp else 9.dp, vertical = if (esTV) 5.dp else 4.dp)
    ) {
        Text(texto, color = fg,
            fontSize = if (esTV) 12.sp else 10.sp,
            fontWeight = FontWeight.Black, letterSpacing = 0.8.sp)
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
            fontWeight = FontWeight.Black, letterSpacing = 0.8.sp, maxLines = 1)
    }
}

// ═══════════════════════════════════════════════════════════
// PANEL DE INFO DEL EVENTO
// ═══════════════════════════════════════════════════════════

@Composable
private fun PanelInfoEvento(evento: Evento, estado: EstadoEvento, esTV: Boolean, esMovil: Boolean) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = padH)
            .fadeInOnLoad(400)
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        Color(0xFF15151C),
                        Color(0xFF0F0F15)
                    )
                )
            )
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
            .padding(horizontal = if (esTV) 24.dp else 16.dp, vertical = if (esTV) 16.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Hora
        InfoItem("🕐", "Hora", evento.hora, esTV, esMovil)
        DividerInfo(esTV)

        // Fecha
        InfoItem("📅", "Fecha", evento.fecha, esTV, esMovil)
        DividerInfo(esTV)

        // Categoría
        InfoItem("🏆", "Categoría", evento.groupTitle, esTV, esMovil)
        DividerInfo(esTV)

        // Canales
        InfoItem("📺", "Canales", "${evento.embeds.size}", esTV, esMovil)

        if (evento.fuente.isNotBlank() && evento.fuente != "Personalizado") {
            DividerInfo(esTV)
            InfoItem("📡", "Fuente", evento.fuente, esTV, esMovil)
        }
    }
}

@Composable
private fun InfoItem(emoji: String, label: String, valor: String, esTV: Boolean, esMovil: Boolean) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(emoji, fontSize = if (esTV) 12.sp else 10.sp)
            Spacer(Modifier.width(4.dp))
            Text(
                label.uppercase(),
                color = Color.White.copy(alpha = 0.4f),
                fontSize = if (esTV) 10.sp else 9.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.sp
            )
        }
        Spacer(Modifier.height(2.dp))
        Text(
            valor,
            color = Color.White,
            fontSize = if (esTV) 15.sp else 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun DividerInfo(esTV: Boolean) {
    Box(
        Modifier
            .padding(horizontal = if (esTV) 20.dp else 12.dp)
            .width(1.dp)
            .height(if (esTV) 30.dp else 22.dp)
            .background(Color.White.copy(alpha = 0.1f))
    )
}

// ═══════════════════════════════════════════════════════════
// SECCIÓN CANALES (GRID con logos)
// ═══════════════════════════════════════════════════════════

@Composable
private fun SeccionCanales(
    evento: Evento, esTV: Boolean, esMovil: Boolean, esVertical: Boolean,
    onCanalClick: (Embed) -> Unit
) {
    val padH = if (esTV) 44.dp else if (esMovil) 16.dp else 32.dp
    val columnas = when {
        esTV -> 3
        esMovil -> 1
        esVertical -> 2
        else -> 2
    }

    Column(Modifier.fillMaxSize()) {
        // Header
        Row(
            Modifier.fillMaxWidth().padding(horizontal = padH, vertical = if (esTV) 8.dp else 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("📺", fontSize = if (esTV) 18.sp else 14.sp)
            Spacer(Modifier.width(if (esTV) 8.dp else 6.dp))
            Text(
                "Elegí un canal",
                color = Color.White,
                fontSize = if (esTV) 18.sp else 15.sp,
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
                    fontSize = if (esTV) 11.sp else 10.sp,
                    fontWeight = FontWeight.Black)
            }
        }
        Spacer(Modifier.height(if (esTV) 12.dp else 8.dp))

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
                    CanalCardConLogo(embed, index + 1, esTV, esMovil) { onCanalClick(embed) }
                }
            }
        }
    }
}

@Composable
private fun CanalCardConLogo(
    embed: Embed, indice: Int,
    esTV: Boolean, esMovil: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, tween(200), label = "chScale")
    val borderColor by animateColorAsState(
        if (focused) Color(0xFFFFD700) else Color.White.copy(alpha = 0.08f),
        tween(150), label = "chBorder"
    )
    val bgColor by animateColorAsState(
        if (focused) Color(0xFF1E1E28) else Color(0xFF15151C),
        tween(150), label = "chBg"
    )
    val altura = if (esTV) 140.dp else if (esMovil) 110.dp else 130.dp

    Row(
        Modifier
            .fillMaxWidth()
            .height(altura)
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 16.dp else 12.dp))
            .background(bgColor)
            .border(
                if (focused) 3.dp else 1.dp,
                borderColor,
                RoundedCornerShape(if (esTV) 16.dp else 12.dp)
            )
            .padding(if (esTV) 14.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Logo o número
        Box(
            Modifier
                .size(if (esTV) 80.dp else 60.dp)
                .clip(RoundedCornerShape(if (esTV) 14.dp else 10.dp))
                .background(
                    Brush.linearGradient(
                        if (focused) listOf(Color(0xFFFFD700), Color(0xFFD4AF37))
                        else listOf(Color(0xFF2A2A33), Color(0xFF1A1A22))
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            if (embed.logo.isNotBlank()) {
                // Mostrar logo del canal
                AsyncImage(
                    model = embed.logo,
                    contentDescription = embed.nombre,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(if (esTV) 60.dp else 44.dp)
                )
            } else {
                // Fallback: número
                Text(
                    "$indice",
                    color = if (focused) Color.Black else Color.White,
                    fontSize = if (esTV) 28.sp else 22.sp,
                    fontWeight = FontWeight.Black
                )
            }
        }
        Spacer(Modifier.width(if (esTV) 16.dp else 12.dp))

        Column(Modifier.weight(1f)) {
            Text(
                embed.nombre,
                color = Color.White,
                fontSize = if (esTV) 18.sp else 14.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = if (esTV) 22.sp else 17.sp,
                overflow = TextOverflow.Ellipsis
            )
            if (esTV) {
                Spacer(Modifier.height(4.dp))
                Text(
                    if (focused) "Presioná OK para reproducir" else "Canal $indice",
                    color = if (focused) Color(0xFFFFD700) else Color.White.copy(alpha = 0.4f),
                    fontSize = 11.sp,
                    fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }

        // Ícono play que aparece al focus
        Box(
            Modifier
                .size(if (esTV) 40.dp else 32.dp)
                .clip(CircleShape)
                .background(if (focused) Color(0xFFFFD700) else Color.White.copy(alpha = 0.08f)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                if (focused) "▶" else "→",
                color = if (focused) Color.Black else Color.White.copy(alpha = 0.5f),
                fontSize = if (esTV) 16.sp else 13.sp,
                fontWeight = FontWeight.Black
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
    val altura = if (esTV) 340.dp else if (esMovil) 200.dp else 260.dp
    val video = if (esFinalizado) evento.videoFinalizado else evento.videoProximo

    Box(
        Modifier.fillMaxSize().padding(horizontal = padH),
        contentAlignment = Alignment.TopCenter
    ) {
        Box(
            Modifier.fillMaxWidth().height(altura)
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF15151C))
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(20.dp))
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
                        fontSize = if (esTV) 24.sp else 18.sp,
                        fontWeight = FontWeight.Black
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        if (esFinalizado) "Gracias por ver FutTV"
                        else "Los canales aparecerán cuando empiece",
                        color = Color.White.copy(alpha = 0.75f),
                        fontSize = if (esTV) 14.sp else 12.sp
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
                        fontSize = if (esTV) 22.sp else 17.sp,
                        fontWeight = FontWeight.Black
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        if (esFinalizado) "Gracias por ver FutTV" else "Volvé cuando empiece",
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
        Modifier.size(if (esTV) 56.dp else 44.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.1f))
            .border(1.5.dp, Color(0xFFFFD700).copy(alpha = 0.4f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            if (esFinalizado) "✓" else "⏰",
            fontSize = if (esTV) 24.sp else 20.sp,
            color = Color(0xFFFFD700),
            fontWeight = FontWeight.Black
        )
    }
}
KOTLIN_EOF

echo "✅ EventDetailScreen reescrito"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅✅✅ Mejoras TV aplicadas"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📋 IMPORTANTE — Actualizá tu Sheet:"
echo ""
echo "  Agregá UNA COLUMNA EXTRA por cada canal para el LOGO."
echo "  Estructura nueva: nombre, url, referer, logo"
echo ""
echo "  Ejemplo (canal 1):"
echo "    G=nombre  H=url  I=referer  J=logo"
echo "  Ejemplo (canal 2):"
echo "    K=nombre  L=url  M=referer  N=logo"
echo "  Y así sucesivamente..."
echo ""
echo "  Después actualizá el Apps Script (te lo paso aparte)"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
