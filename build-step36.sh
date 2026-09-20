#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

echo "📝 Reescribiendo AjustesScreen.kt con iconos Material..."
cp "$PKG_DIR/AjustesScreen.kt" "$PKG_DIR/AjustesScreen.kt.bak36" 2>/dev/null || true

cat > "$PKG_DIR/AjustesScreen.kt" << 'EOF'
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
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.BuildConfig
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import kotlinx.coroutines.delay

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
                Icon(
                    imageVector = AppIcons.ajustes,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(34.dp)
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    "Ajustes",
                    color = AppColors.GoldBright,
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Black
                )
                Spacer(Modifier.weight(1f))
                BotonAjuste(texto = "Volver", icono = AppIcons.volver, onClick = onBack)
            }

            Spacer(Modifier.height(36.dp))

            // Sección: CALIDAD
            SeccionTitulo(icono = AppIcons.calidad, texto = "CALIDAD DE VIDEO")
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
            SeccionTitulo(icono = AppIcons.refrescar, texto = "ACTUALIZACIÓN AUTOMÁTICA")
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
            SeccionTitulo(icono = AppIcons.cache, texto = "ALMACENAMIENTO")
            Spacer(Modifier.height(12.dp))
            FilaAccion(
                icono = AppIcons.borrar,
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
                    mensajeCache = "Caché limpiada"
                }
            )
            if (mensajeCache != null) {
                Spacer(Modifier.height(10.dp))
                Row(
                    Modifier.padding(start = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = AppIcons.okCirculo,
                        contentDescription = null,
                        tint = AppColors.AccentGreen,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        mensajeCache ?: "",
                        color = AppColors.AccentGreen,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Spacer(Modifier.height(32.dp))

            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")
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
private fun SeccionTitulo(icono: ImageVector, texto: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            imageVector = icono,
            contentDescription = null,
            tint = AppColors.Gold,
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(10.dp))
        Text(
            texto,
            color = AppColors.Gold,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 2.sp
        )
    }
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = AppIcons.ok,
                    contentDescription = null,
                    tint = AppColors.AccentGreen,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text("ACTIVO", color = AppColors.AccentGreen, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
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
private fun FilaAccion(
    icono: ImageVector,
    titulo: String,
    subtitulo: String,
    onClick: () -> Unit
) {
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
        Icon(
            imageVector = icono,
            contentDescription = null,
            tint = if (focused) AppColors.GoldBright else AppColors.Gold,
            modifier = Modifier.size(22.dp)
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(titulo, color = AppColors.TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(2.dp))
            Text(subtitulo, color = AppColors.TextSecondary, fontSize = 12.sp)
        }
        Icon(
            imageVector = AppIcons.adelante,
            contentDescription = null,
            tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            modifier = Modifier.size(20.dp)
        )
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
private fun BotonAjuste(texto: String, icono: ImageVector, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(2.dp, if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .clickable { onClick() }
            .padding(horizontal = 18.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icono,
            contentDescription = null,
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(6.dp))
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

echo "📝 Reescribiendo BusquedaScreen.kt con iconos Material..."
cp "$PKG_DIR/BusquedaScreen.kt" "$PKG_DIR/BusquedaScreen.kt.bak36" 2>/dev/null || true

cat > "$PKG_DIR/BusquedaScreen.kt" << 'EOF'
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
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

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
                Icon(
                    imageVector = AppIcons.buscar,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(34.dp)
                )
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
                leadingIcon = {
                    Icon(
                        imageVector = AppIcons.buscar,
                        contentDescription = null,
                        tint = AppColors.Gold,
                        modifier = Modifier.size(20.dp)
                    )
                },
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
                        Icon(
                            imageVector = AppIcons.buscarLupa,
                            contentDescription = null,
                            tint = AppColors.TextMuted,
                            modifier = Modifier.size(72.dp)
                        )
                        Spacer(Modifier.height(14.dp))
                        Text("Escribí algo para buscar", color = AppColors.TextSecondary, fontSize = 15.sp)
                    }
                }
                resultados.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = AppIcons.sinResultados,
                            contentDescription = null,
                            tint = AppColors.TextMuted,
                            modifier = Modifier.size(72.dp)
                        )
                        Spacer(Modifier.height(14.dp))
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
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = AppIcons.reloj,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text(FechaHelper.badgeCard(ev.fecha, ev.hora), color = AppColors.GoldBright, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(12.dp))
                Icon(
                    imageVector = AppIcons.senal,
                    contentDescription = null,
                    tint = AppColors.TextSecondary,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text(ev.fuente, color = AppColors.TextSecondary, fontSize = 12.sp)
                Spacer(Modifier.width(12.dp))
                Icon(
                    imageVector = AppIcons.canales,
                    contentDescription = null,
                    tint = AppColors.TextSecondary,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text("${ev.embeds.size}", color = AppColors.TextSecondary, fontSize = 12.sp)
            }
        }
        Icon(
            imageVector = if (focused) AppIcons.play else AppIcons.adelante,
            contentDescription = null,
            tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun BotonVolver(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(2.dp, if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
            .clickable { onClick() }
            .padding(horizontal = 18.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = null,
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(6.dp))
        Text("Volver", color = if (focused) Color.Black else AppColors.Gold, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}
EOF

echo "📝 Reescribiendo EventDetailScreen.kt con iconos Material..."
cp "$PKG_DIR/EventDetailScreen.kt" "$PKG_DIR/EventDetailScreen.kt.bak36" 2>/dev/null || true

cat > "$PKG_DIR/EventDetailScreen.kt" << 'EOF'
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
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
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

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
                Brush.verticalGradient(listOf(AppColors.Background, AppColors.BackgroundGradient))
            )
    ) {
        Column(Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 36.dp)) {

            Row(
                Modifier.fadeInOnLoad(durationMs = 450),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier.size(110.dp).clip(RoundedCornerShape(16.dp))
                        .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                    contentAlignment = Alignment.Center
                ) {
                    if (evento.imagen.isNotBlank()) {
                        AsyncImage(
                            model = evento.imagen,
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.size(80.dp)
                        )
                    } else {
                        Text("⚽", fontSize = 46.sp)
                    }
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
                            Modifier.clip(RoundedCornerShape(6.dp))
                                .background(color.copy(alpha = 0.2f))
                                .padding(horizontal = 10.dp, vertical = 4.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                                    color = color,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                        Spacer(Modifier.width(10.dp))
                        Icon(
                            imageVector = AppIcons.reloj,
                            contentDescription = null,
                            tint = AppColors.GoldBright,
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            FechaHelper.badgeCard(evento.fecha, evento.hora),
                            color = AppColors.GoldBright,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("·", color = AppColors.TextMuted, fontSize = 14.sp)
                        Spacer(Modifier.width(10.dp))
                        Text(
                            evento.fuente,
                            color = AppColors.TextSecondary,
                            fontSize = 14.sp
                        )
                    }
                }
            }

            Spacer(Modifier.height(44.dp))

            Row(
                Modifier.fadeInOnLoad(durationMs = 450, delayMs = 100),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = AppIcons.canales,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(22.dp)
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    "Elige un canal para reproducir",
                    color = AppColors.TextPrimary,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.width(12.dp))
                Box(
                    Modifier.clip(RoundedCornerShape(10.dp))
                        .background(AppColors.Gold.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("${evento.embeds.size}", color = AppColors.Gold, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(20.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                itemsIndexed(
                    items = evento.embeds,
                    key = { _, it -> it.url }
                ) { index, embed ->
                    Box(
                        Modifier.fadeInOnLoad(
                            durationMs = 400,
                            delayMs = 150 + index * 50,
                            slideFromDp = 16f
                        )
                    ) {
                        CanalCardPro(embed) { onCanalClick(embed) }
                    }
                }
            }
        }
    }
}

@Composable
private fun CanalCardPro(embed: Embed, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 2.dp else 1.dp,
        animationSpec = tween(180),
        label = "canalBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.2f),
        animationSpec = tween(180),
        label = "canalBorderColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (focused) AppColors.CardFocus else AppColors.Card,
        animationSpec = tween(180),
        label = "canalBg"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.02f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bgColor)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(50.dp).clip(CircleShape)
                .background(if (focused) AppColors.GoldBright else AppColors.Gold),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color.Black,
                modifier = Modifier.size(26.dp)
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
            if (focused) "Reproducir" else "OK para reproducir",
            color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            fontSize = 14.sp,
            fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -q "import com.anonimus757.tvapp.ui.theme.AppIcons" "$PKG_DIR/AjustesScreen.kt" && echo "  ✓ AppIcons en AjustesScreen"
grep -q "import com.anonimus757.tvapp.ui.theme.AppIcons" "$PKG_DIR/BusquedaScreen.kt" && echo "  ✓ AppIcons en BusquedaScreen"
grep -q "import com.anonimus757.tvapp.ui.theme.AppIcons" "$PKG_DIR/EventDetailScreen.kt" && echo "  ✓ AppIcons en EventDetailScreen"

echo ""
echo "✅✅✅ Paso 36 completo — Ajustes + Búsqueda + Detail con iconos"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"