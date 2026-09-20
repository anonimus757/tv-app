#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
mkdir -p "$PKG_DIR/data" "$PKG_DIR/ui"

# ─────────────────────────────────────────────────────────────
# 1) AjustesStore.kt (preferencias locales)
# ─────────────────────────────────────────────────────────────
echo "📝 Creando AjustesStore.kt..."

cat > "$PKG_DIR/data/AjustesStore.kt" << 'EOF'
package com.anonimus757.tvapp.data

import android.content.Context

/**
 * Preferencias locales del usuario (por dispositivo).
 * NO van a Firestore: cada celu/TV tiene las suyas.
 */
object AjustesStore {

    private const val PREFS = "futtv_ajustes"
    private const val KEY_CALIDAD = "calidad"
    private const val KEY_AUTOREFRESH = "autorefresh"

    /** auto | sd | hd */
    fun obtenerCalidad(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_CALIDAD, "auto") ?: "auto"

    fun guardarCalidad(context: Context, calidad: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_CALIDAD, calidad).apply()
    }

    /** Si está activado el auto-refresh local (además del global de Firestore). */
    fun obtenerAutoRefresh(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_AUTOREFRESH, true)

    fun guardarAutoRefresh(context: Context, activo: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_AUTOREFRESH, activo).apply()
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 2) SplashScreen.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando SplashScreen.kt..."

cat > "$PKG_DIR/ui/SplashScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.ui.theme.AppColors
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(onTerminado: () -> Unit) {
    var visible by remember { mutableStateOf(false) }
    var saliendo by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        delay(100)
        visible = true
        delay(1400)
        saliendo = true
        delay(400)
        onTerminado()
    }

    val alpha by animateFloatAsState(
        targetValue = if (saliendo) 0f else if (visible) 1f else 0f,
        animationSpec = tween(if (saliendo) 400 else 600),
        label = "splashAlpha"
    )
    val scale by animateFloatAsState(
        targetValue = if (visible && !saliendo) 1f else 0.85f,
        animationSpec = tween(700),
        label = "splashScale"
    )

    // Glow pulsante en el logo
    val transition = rememberInfiniteTransition(label = "glow")
    val glow by transition.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "glowPulse"
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, Color(0xFF0A0A0A), AppColors.Background)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.alpha(alpha).scale(scale)
        ) {
            Text(
                "⚽",
                fontSize = 90.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(16.dp))
            Text(
                "FutTV",
                color = AppColors.GoldBright,
                fontSize = 56.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 6.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "EN VIVO · IPTV PREMIUM",
                color = AppColors.TextSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 3.sp
            )
            Spacer(Modifier.height(40.dp))
            Box(
                Modifier
                    .width(80.dp)
                    .height(2.dp)
                    .background(
                        Brush.horizontalGradient(
                            listOf(Color.Transparent, AppColors.Gold, Color.Transparent)
                        )
                    )
            )
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 3) Screen.kt (agregar Ajustes y Busqueda)
# ─────────────────────────────────────────────────────────────
echo "📝 Actualizando Screen.kt..."

cat > "$PKG_DIR/ui/Screen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen
    data class Detail(val evento: Evento, val todos: List<Evento>, val volverA: VolverA) : Screen
    data class Player(val evento: Evento, val embed: Embed, val todos: List<Evento>) : Screen
    data object Ajustes : Screen
    data object Busqueda : Screen
}

enum class VolverA { Home, Player }
EOF

# ─────────────────────────────────────────────────────────────
# 4) AjustesScreen.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando AjustesScreen.kt..."

cat > "$PKG_DIR/ui/AjustesScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.BuildConfig
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import kotlinx.coroutines.delay
import java.io.File

@Composable
fun AjustesScreen(onBack: () -> Unit) {
    val context = LocalContext.current

    var calidad by remember { mutableStateOf(AjustesStore.obtenerCalidad(context)) }
    var autoRefresh by remember { mutableStateOf(AjustesStore.obtenerAutoRefresh(context)) }
    var tamanioCache by remember { mutableStateOf(calcularCache(context)) }
    var mensajeCache by remember { mutableStateOf<String?>(null) }

    val primerFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        delay(200)
        try { primerFocus.requestFocus() } catch (_: Exception) {}
    }

    BackHandler { onBack() }

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, AppColors.BackgroundGradient)
                )
            )
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 48.dp, vertical = 36.dp)
                .verticalScroll(rememberScrollState())
        ) {
            // Header
            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("⚙️", fontSize = 32.sp)
                Spacer(Modifier.width(12.dp))
                Text(
                    "Ajustes",
                    color = AppColors.GoldBright,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Black
                )
                Spacer(Modifier.weight(1f))
                BotonAjuste(texto = "← Volver", onClick = onBack)
            }

            Spacer(Modifier.height(36.dp))

            // Sección: CALIDAD
            SeccionTitulo("🎞 CALIDAD DE VIDEO")
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OpcionCalidad(
                    titulo = "Auto",
                    subtitulo = "Se adapta a tu red",
                    seleccionado = calidad == "auto",
                    modifier = Modifier.focusRequester(primerFocus),
                    onClick = {
                        calidad = "auto"
                        AjustesStore.guardarCalidad(context, "auto")
                    }
                )
                OpcionCalidad(
                    titulo = "SD",
                    subtitulo = "480p · menos datos",
                    seleccionado = calidad == "sd",
                    onClick = {
                        calidad = "sd"
                        AjustesStore.guardarCalidad(context, "sd")
                    }
                )
                OpcionCalidad(
                    titulo = "HD",
                    subtitulo = "1080p · más calidad",
                    seleccionado = calidad == "hd",
                    onClick = {
                        calidad = "hd"
                        AjustesStore.guardarCalidad(context, "hd")
                    }
                )
            }

            Spacer(Modifier.height(32.dp))

            // Sección: AUTO-REFRESH
            SeccionTitulo("🔄 ACTUALIZACIÓN AUTOMÁTICA")
            Spacer(Modifier.height(12.dp))
            FilaOpcion(
                titulo = "Refrescar eventos automáticamente",
                subtitulo = "Cada ${com.anonimus757.tvapp.data.RemoteConfigRepository.config.value.minutosAutoRefresh} minutos",
                activo = autoRefresh,
                onClick = {
                    autoRefresh = !autoRefresh
                    AjustesStore.guardarAutoRefresh(context, autoRefresh)
                }
            )

            Spacer(Modifier.height(32.dp))

            // Sección: CACHÉ
            SeccionTitulo("💾 ALMACENAMIENTO")
            Spacer(Modifier.height(12.dp))
            FilaAccion(
                titulo = "Limpiar caché",
                subtitulo = "Ocupando $tamanioCache",
                onClick = {
                    context.cacheDir.deleteRecursively()
                    context.filesDir.listFiles()?.forEach { f ->
                        if (f.name.startsWith("coil") || f.name.startsWith("image")) {
                            f.deleteRecursively()
                        }
                    }
                    tamanioCache = calcularCache(context)
                    mensajeCache = "✅ Caché limpiada"
                }
            )
            if (mensajeCache != null) {
                Spacer(Modifier.height(8.dp))
                Text(
                    mensajeCache ?: "",
                    color = AppColors.AccentGreen,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }

            Spacer(Modifier.height(32.dp))

            // Sección: INFO
            SeccionTitulo("ℹ️ INFORMACIÓN")
            Spacer(Modifier.height(12.dp))
            FilaInfo("Versión", "v${BuildConfig.VERSION_NAME}")
            Spacer(Modifier.height(8.dp))
            FilaInfo("Desarrollador", "FutTV")
            Spacer(Modifier.height(8.dp))
            FilaInfo("Proyecto", "github.com/anonimus757/tv-app")

            Spacer(Modifier.height(60.dp))
        }
    }
}

@Composable
private fun SeccionTitulo(texto: String) {
    Text(
        texto,
        color = AppColors.Gold,
        fontSize = 13.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 2.sp
    )
}

@Composable
private fun OpcionCalidad(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val borderWidth by animateDpAsState(if (focused || seleccionado) 2.dp else 1.dp, tween(180), label = "ow")
    val borderColor by animateColorAsState(
        when {
            focused -> AppColors.GoldBright
            seleccionado -> AppColors.Gold
            else -> AppColors.Gold.copy(alpha = 0.25f)
        },
        tween(180), label = "oc"
    )
    val bg by animateColorAsState(
        when {
            seleccionado -> AppColors.Gold.copy(alpha = 0.18f)
            focused -> AppColors.CardFocus
            else -> AppColors.Card
        },
        tween(180), label = "ob"
    )

    Column(
        modifier
            .width(200.dp)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(horizontal = 20.dp, vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            titulo,
            color = if (seleccionado || focused) AppColors.GoldBright else AppColors.TextPrimary,
            fontSize = 22.sp,
            fontWeight = FontWeight.Black
        )
        Spacer(Modifier.height(4.dp))
        Text(
            subtitulo,
            color = AppColors.TextSecondary,
            fontSize = 12.sp
        )
        if (seleccionado) {
            Spacer(Modifier.height(8.dp))
            Text("✓ ACTIVO", color = AppColors.AccentGreen, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun FilaOpcion(
    titulo: String,
    subtitulo: String,
    activo: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.01f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.25f),
                RoundedCornerShape(14.dp)
            )
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(titulo, color = AppColors.TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(2.dp))
            Text(subtitulo, color = AppColors.TextSecondary, fontSize = 12.sp)
        }
        Box(
            Modifier
                .width(56.dp)
                .height(30.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(if (activo) AppColors.Gold else AppColors.SurfaceLight)
        ) {
            Box(
                Modifier
                    .align(if (activo) Alignment.CenterEnd else Alignment.CenterStart)
                    .padding(horizontal = 3.dp)
                    .size(24.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (activo) Color.Black else AppColors.TextMuted)
            )
        }
    }
}

@Composable
private fun FilaAccion(titulo: String, subtitulo: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.25f),
                RoundedCornerShape(14.dp)
            )
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(titulo, color = AppColors.TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(2.dp))
            Text(subtitulo, color = AppColors.TextSecondary, fontSize = 12.sp)
        }
        Text("→", color = if (focused) AppColors.GoldBright else AppColors.TextMuted, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun FilaInfo(label: String, valor: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = AppColors.TextSecondary, fontSize = 14.sp)
        Spacer(Modifier.weight(1f))
        Text(valor, color = AppColors.TextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun BotonAjuste(texto: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(2.dp, if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .clickable { onClick() }
            .padding(horizontal = 18.dp, vertical = 10.dp)
    ) {
        Text(texto, color = if (focused) Color.Black else AppColors.Gold, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}

private fun calcularCache(context: Context): String {
    return try {
        val bytes = context.cacheDir.walkTopDown().filter { it.isFile }.map { it.length() }.sum()
        when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> "${bytes / 1024} KB"
            else -> "%.1f MB".format(bytes / 1024.0 / 1024.0)
        }
    } catch (_: Exception) { "—" }
}
EOF

# ─────────────────────────────────────────────────────────────
# 5) BusquedaScreen.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando BusquedaScreen.kt..."

cat > "$PKG_DIR/ui/BusquedaScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.theme.AppColors

@Composable
fun BusquedaScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()

    var query by remember { mutableStateOf("") }
    var todos by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        try {
            val fb = EventRepository.obtenerEventosFirestore()
            val sc = if (config.mostrarScraping) EventRepository.obtenerEventosScraping() else emptyList()
            todos = fb + sc
        } catch (_: Exception) {}
        cargando = false
    }

    BackHandler { onBack() }

    val resultados = remember(query, todos) {
        if (query.isBlank()) emptyList()
        else {
            val q = query.trim().lowercase()
            todos.filter { ev ->
                ev.descripcion.lowercase().contains(q) ||
                ev.categoria.lowercase().contains(q) ||
                ev.groupTitle.lowercase().contains(q) ||
                ev.fuente.lowercase().contains(q)
            }
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
        Column(
            Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 36.dp)
        ) {
            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🔍", fontSize = 32.sp)
                Spacer(Modifier.width(12.dp))
                Text("Buscar eventos", color = AppColors.GoldBright, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                BotonVolver(onBack)
            }

            Spacer(Modifier.height(24.dp))

            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(60) },
                placeholder = { Text("Boca, River, ESPN, Pelota Libre...", color = AppColors.TextMuted) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = TextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = AppColors.SurfaceLight,
                    unfocusedContainerColor = AppColors.SurfaceLight,
                    cursorColor = AppColors.Gold,
                    focusedIndicatorColor = AppColors.Gold,
                    unfocusedIndicatorColor = AppColors.TextMuted,
                    focusedPlaceholderColor = AppColors.TextMuted,
                    unfocusedPlaceholderColor = AppColors.TextMuted
                )
            )

            Spacer(Modifier.height(20.dp))

            when {
                cargando -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Cargando eventos...", color = AppColors.TextSecondary, fontSize = 14.sp)
                }
                query.isBlank() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("🔎", fontSize = 60.sp)
                        Spacer(Modifier.height(12.dp))
                        Text("Escribí algo para buscar", color = AppColors.TextSecondary, fontSize = 15.sp)
                    }
                }
                resultados.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("😕", fontSize = 60.sp)
                        Spacer(Modifier.height(12.dp))
                        Text("Sin resultados para \"$query\"", color = AppColors.TextSecondary, fontSize = 15.sp)
                    }
                }
                else -> {
                    Text(
                        "${resultados.size} resultados",
                        color = AppColors.Gold,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(bottom = 12.dp)
                    )
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(resultados, key = { "${it.fuente}_${it.hora}_${it.descripcion}" }) { ev ->
                            ResultadoCard(ev) { onEventoClick(ev, resultados) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultadoCard(ev: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(
                if (focused) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else color.copy(alpha = 0.25f),
                RoundedCornerShape(12.dp)
            )
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(60.dp).clip(RoundedCornerShape(10.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(48.dp)
                )
            } else {
                Text("⚽", fontSize = 28.sp)
            }
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(ev.descripcion, color = AppColors.TextPrimary, fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold, maxLines = 2)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🕐", fontSize = 11.sp)
                Spacer(Modifier.width(4.dp))
                Text(ev.hora, color = AppColors.GoldBright, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(10.dp))
                Text("📡 ${ev.fuente}", color = AppColors.TextSecondary, fontSize = 12.sp)
                Spacer(Modifier.width(10.dp))
                Text("📺 ${ev.embeds.size}", color = AppColors.TextSecondary, fontSize = 12.sp)
            }
        }
        Text(
            if (focused) "▶" else "→",
            color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            fontSize = 20.sp, fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun BotonVolver(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(2.dp, if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .clickable { onClick() }
            .padding(horizontal = 18.dp, vertical = 10.dp)
    ) {
        Text("← Volver", color = if (focused) Color.Black else AppColors.Gold, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 6) HomeScreen.kt (reescritura con botones + auto-refresh)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo HomeScreen.kt con botones + auto-refresh..."

cat > "$PKG_DIR/ui/HomeScreen.kt" << 'EOF'
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.data.DebugLog
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.notifications.EventNotifScheduler
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.animations.shimmer
import com.anonimus757.tvapp.ui.theme.AppColors
import kotlinx.coroutines.delay

private fun horaAMinutos(hora: String): Int {
    val match = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return Int.MAX_VALUE
    val h = match.groupValues[1].toIntOrNull() ?: return Int.MAX_VALUE
    val m = match.groupValues[2].toIntOrNull() ?: return Int.MAX_VALUE
    if (h !in 0..23 || m !in 0..59) return Int.MAX_VALUE
    return h * 60 + m
}

@Composable
fun HomeScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onIrAAjustes: () -> Unit = {},
    onIrABusqueda: () -> Unit = {}
) {
    val context = LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()
    val autoRefreshLocal = AjustesStore.obtenerAutoRefresh(context)

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargandoInicial by remember { mutableStateOf(true) }
    var refrescando by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Conectando...") }
    var mostrarDebug by remember { mutableStateOf(false) }
    var refreshTrigger by remember { mutableIntStateOf(0) }

    // Carga inicial
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

    // Refresh manual o auto
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

    // Auto-refresh
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
            eventosFirebase.isEmpty() && eventosScraping.isEmpty() ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("📭", fontSize = 60.sp)
                        Spacer(Modifier.height(16.dp))
                        Text("Sin eventos", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
                    }
                }
            else -> ContenidoHome(
                mostrarDebug = mostrarDebug,
                onMostrarDebugChange = { mostrarDebug = it },
                eventosFirebase = eventosFirebase,
                eventosScraping = eventosScraping,
                textoBienvenida = config.textoBienvenida,
                mensajeSistema = config.mensajeSistema,
                mostrarScraping = config.mostrarScraping,
                refrescando = refrescando,
                onRefrescar = { refreshTrigger++ },
                onIrAAjustes = onIrAAjustes,
                onIrABusqueda = onIrABusqueda,
                onEventoClick = onEventoClick
            )
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
                    item { Box(Modifier.width(260.dp).height(240.dp).shimmer(RoundedCornerShape(14.dp))) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun ContenidoHome(
    mostrarDebug: Boolean,
    onMostrarDebugChange: (Boolean) -> Unit,
    eventosFirebase: List<Evento>,
    eventosScraping: List<Evento>,
    textoBienvenida: String,
    mensajeSistema: String,
    mostrarScraping: Boolean,
    refrescando: Boolean,
    onRefrescar: () -> Unit,
    onIrAAjustes: () -> Unit,
    onIrABusqueda: () -> Unit,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val fbOrdenados = remember(eventosFirebase) { eventosFirebase.sortedBy { horaAMinutos(it.hora) } }
    val scOrdenados = remember(eventosScraping) { eventosScraping.sortedBy { horaAMinutos(it.hora) } }
    val gruposFb = remember(fbOrdenados) { fbOrdenados.groupBy { it.groupTitle } }
    val gruposSc = remember(scOrdenados) { scOrdenados.groupBy { it.groupTitle } }

    val totalCanales = (fbOrdenados + scOrdenados).sumOf { it.embeds.size }
    val totalEventos = fbOrdenados.size + scOrdenados.size
    val destacado = fbOrdenados.firstOrNull() ?: scOrdenados.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp)
    ) {
        item(key = "header") {
            Box(
                Modifier.pointerInput(Unit) {
                    detectTapGestures(onLongPress = { onMostrarDebugChange(!mostrarDebug) })
                }
            ) {
                HeaderFutTV(
                    textoBienvenida = textoBienvenida,
                    totalEventos = totalEventos,
                    totalCanales = totalCanales,
                    refrescando = refrescando,
                    onRefrescar = onRefrescar,
                    onIrAAjustes = onIrAAjustes,
                    onIrABusqueda = onIrABusqueda
                )
            }
        }

        if (mensajeSistema.isNotBlank()) {
            item(key = "banner") {
                Spacer(Modifier.height(16.dp))
                BannerSistema(mensajeSistema)
            }
        }

        if (fbOrdenados.isNotEmpty()) {
            item(key = "sep_fb") {
                Spacer(Modifier.height(24.dp))
                SeparadorSeccion(
                    titulo = "🔥 TUS EVENTOS",
                    subtitulo = "${fbOrdenados.size} en vivo · ${fbOrdenados.sumOf { it.embeds.size }} canales",
                    color = AppColors.GoldBright
                )
            }
            destacado?.let { ev ->
                item(key = "hero") {
                    Spacer(Modifier.height(20.dp))
                    HeroEvento(ev) { onEventoClick(ev, fbOrdenados) }
                    Spacer(Modifier.height(30.dp))
                }
            }
            gruposFb.forEach { (titulo, lista) ->
                item(key = "fb_header_$titulo") { HeaderCategoria(titulo, lista.size) }
                item(key = "fb_row_$titulo") { FilaEventos(lista, onEventoClick) }
                item(key = "fb_space_$titulo") { Spacer(Modifier.height(24.dp)) }
            }
        }

        if (mostrarScraping && scOrdenados.isNotEmpty()) {
            item(key = "sep_sc") {
                Spacer(Modifier.height(12.dp))
                SeparadorSeccion(
                    titulo = "🌐 AGENDAS EXTERNAS",
                    subtitulo = "${scOrdenados.size} eventos · scraping en vivo",
                    color = AppColors.TextSecondary
                )
            }
            gruposSc.forEach { (titulo, lista) ->
                item(key = "sc_header_$titulo") { HeaderCategoria(titulo, lista.size) }
                item(key = "sc_row_$titulo") { FilaEventos(lista, onEventoClick) }
                item(key = "sc_space_$titulo") { Spacer(Modifier.height(24.dp)) }
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

@Composable
private fun SeparadorSeccion(titulo: String, subtitulo: String, color: Color) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp).fadeInOnLoad(400)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(32.dp).clip(RoundedCornerShape(3.dp)).background(color))
            Spacer(Modifier.width(14.dp))
            Text(titulo, color = color, fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        }
        Spacer(Modifier.height(4.dp))
        Text(subtitulo, color = AppColors.TextSecondary, fontSize = 13.sp,
            modifier = Modifier.padding(start = 20.dp))
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
        Text("📢", fontSize = 22.sp)
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
        Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(durationMs = 400),
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
            Text("● EN VIVO", color = AppColors.Gold, fontSize = 11.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        }
        Spacer(Modifier.weight(1f))
        Text("$totalEventos eventos · $totalCanales canales",
            color = AppColors.TextSecondary, fontSize = 12.sp)
        Spacer(Modifier.width(16.dp))

        BotonHeader(icono = "🔍", onClick = onIrABusqueda)
        Spacer(Modifier.width(8.dp))
        BotonHeader(icono = "⚙️", onClick = onIrAAjustes)
        Spacer(Modifier.width(8.dp))
        BotonHeader(
            icono = if (refrescando) "⏳" else "🔄",
            onClick = { if (!refrescando) onRefrescar() }
        )
    }
}

@Composable
private fun BotonHeader(icono: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .size(42.dp)
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
        Text(icono, fontSize = 20.sp)
    }
}

@Composable
private fun HeroEvento(evento: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(evento.groupTitle)
    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "hw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
        tween(180), label = "hc"
    )

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp)
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
                AsyncImage(model = evento.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(110.dp))
            } else Text("⚽", fontSize = 60.sp)
        }
        Spacer(Modifier.width(28.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.clip(RoundedCornerShape(6.dp)).background(AppColors.Gold)
                    .padding(horizontal = 10.dp, vertical = 3.dp)) {
                    Text("⭐ DESTACADO", color = Color.Black, fontSize = 11.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
                Spacer(Modifier.width(10.dp))
                Box(Modifier.clip(RoundedCornerShape(6.dp))
                    .background(color.copy(alpha = 0.2f))
                    .padding(horizontal = 10.dp, vertical = 3.dp)) {
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
                Text("📡 ${evento.fuente}", color = AppColors.TextSecondary, fontSize = 14.sp)
                Spacer(Modifier.width(16.dp))
                Text("📺 ${evento.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 14.sp)
            }
            Spacer(Modifier.height(16.dp))
            Box(Modifier.clip(RoundedCornerShape(10.dp))
                .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                .padding(horizontal = 22.dp, vertical = 12.dp)) {
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
        Box(Modifier.clip(RoundedCornerShape(10.dp))
            .background(color.copy(alpha = 0.2f))
            .padding(horizontal = 10.dp, vertical = 3.dp)) {
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
        itemsIndexed(items = lista, key = { _, it -> "${it.fuente}_${it.hora}_${it.descripcion}" }) { index, ev ->
            Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 200 + index * 60, slideFromDp = 20f)) {
                EventoCardPro(ev) { onEventoClick(ev, lista) }
            }
        }
    }
}

@Composable
private fun EventoCardPro(ev: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "cc"
    )
    val bgColor by animateColorAsState(
        if (focused) AppColors.CardFocus else AppColors.Card,
        tween(180), label = "cbg"
    )

    Column(
        Modifier.width(260.dp)
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
            if (ev.imagen.isNotBlank()) {
                AsyncImage(model = ev.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(105.dp))
            } else Text("⚽", fontSize = 50.sp)
            Box(Modifier.align(Alignment.TopEnd).padding(8.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(AppColors.Gold)
                .padding(horizontal = 8.dp, vertical = 3.dp)) {
                Text(ev.hora, color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Black)
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(ev.descripcion, color = AppColors.TextPrimary, fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = 19.sp,
            modifier = Modifier.height(38.dp))
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(AppColors.Gold))
            Spacer(Modifier.width(6.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            Text(if (focused) "▶" else "→",
                color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
    }
}

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
                Text("🔍 DEBUG", color = Color(0xFF4ADE80), fontSize = 16.sp, fontWeight = FontWeight.Black)
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

# ─────────────────────────────────────────────────────────────
# 7) MainActivity.kt (splash + rutas nuevas)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo MainActivity.kt con splash + rutas..."

cat > "$PKG_DIR/MainActivity.kt" << 'EOF'
package com.anonimus757.tvapp

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.lifecycleScope
import com.anonimus757.tvapp.data.FirebaseManager
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.notifications.NotificationHelper
import com.anonimus757.tvapp.ui.*
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        lifecycleScope.launch {
            FirebaseManager.init()
        }

        setContent {
            InicializarFirebaseCompose()

            var mostrarSplash by remember { mutableStateOf(true) }
            var screen by remember { mutableStateOf<Screen>(Screen.Home) }

            if (mostrarSplash) {
                SplashScreen(onTerminado = { mostrarSplash = false })
            } else {
                when (val s = screen) {
                    is Screen.Home -> HomeScreen(
                        onEventoClick = { evento, todos ->
                            screen = Screen.Detail(evento, todos, VolverA.Home)
                        },
                        onIrAAjustes = { screen = Screen.Ajustes },
                        onIrABusqueda = { screen = Screen.Busqueda }
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

                    is Screen.Ajustes -> AjustesScreen(
                        onBack = { screen = Screen.Home }
                    )

                    is Screen.Busqueda -> BusquedaScreen(
                        onEventoClick = { evento, todos ->
                            screen = Screen.Detail(evento, todos, VolverA.Home)
                        },
                        onBack = { screen = Screen.Home }
                    )
                }
            }
        }
    }
}

@Composable
private fun InicializarFirebaseCompose() {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    LaunchedEffect(Unit) {
        NotificationHelper.crearCanales(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!NotificationHelper.tienePermiso(context)) {
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        RemoteConfigRepository.iniciar(context)
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 8) PlayerScreen.kt → aplicar calidad desde AjustesStore
# ─────────────────────────────────────────────────────────────
echo "📝 Parcheando PlayerScreen.kt para leer calidad de ajustes..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f: content = f.read()

# Agregar import si no está
if "import com.anonimus757.tvapp.data.AjustesStore" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.Embed",
        "import com.anonimus757.tvapp.data.AjustesStore\nimport com.anonimus757.tvapp.data.Embed"
    )

# Cambiar la construcción del trackSelector para leer la calidad
old = '''        val trackSelector = DefaultTrackSelector(context).apply {
            setParameters(
                buildUponParameters()
                    .setMaxVideoSizeSd()
                    .setAllowVideoMixedMimeTypeAdaptiveness(true)
                    .setAllowVideoNonSeamlessAdaptiveness(true)
            )
        }'''

new = '''        val calidad = AjustesStore.obtenerCalidad(context)
        val trackSelector = DefaultTrackSelector(context).apply {
            val params = when (calidad) {
                "sd" -> buildUponParameters().setMaxVideoSizeSd()
                "hd" -> buildUponParameters().setMaxVideoSize(1920, 1080)
                else -> buildUponParameters() // auto: sin límite, adaptativo
            }
            params
                .setAllowVideoMixedMimeTypeAdaptiveness(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
            setParameters(params)
        }'''

if old in content:
    content = content.replace(old, new)
    print("✅ PlayerScreen: trackSelector lee calidad")
else:
    print("⚠️  No encontré el bloque de trackSelector")

with open(file_path, "w") as f: f.write(content)
PYEOF

# ─────────────────────────────────────────────────────────────
# 9) Verificación final
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando:"
[ -f "$PKG_DIR/data/AjustesStore.kt" ] && echo "  ✓ AjustesStore.kt"
[ -f "$PKG_DIR/ui/SplashScreen.kt" ] && echo "  ✓ SplashScreen.kt"
[ -f "$PKG_DIR/ui/AjustesScreen.kt" ] && echo "  ✓ AjustesScreen.kt"
[ -f "$PKG_DIR/ui/BusquedaScreen.kt" ] && echo "  ✓ BusquedaScreen.kt"
grep -q "Ajustes" "$PKG_DIR/ui/Screen.kt" && echo "  ✓ Screen.kt con Ajustes/Busqueda"
grep -q "SplashScreen" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity con splash"
grep -q "BotonHeader" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ HomeScreen con botones header"
grep -q "Auto-refresh" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ Auto-refresh configurado"
grep -q "AjustesStore.obtenerCalidad" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ PlayerScreen lee calidad"

echo ""
echo "✅✅✅ Paso 29 completo — Splash + Auto-refresh + Ajustes + Búsqueda"
echo ""
echo "📌 Lo que ganaste:"
echo "   🎬 Splash animado con logo FutTV"
echo "   🔄 Auto-refresh cada X min (config de Firestore)"
echo "   🔄 Botón manual 🔄 en el header"
echo "   ⚙️ Pantalla Ajustes (calidad SD/HD/Auto + limpiar caché + versión)"
echo "   🔍 Pantalla Búsqueda (filtra por descripción/categoría/fuente)"
echo "   🎞 Calidad aplicada al reproductor"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"