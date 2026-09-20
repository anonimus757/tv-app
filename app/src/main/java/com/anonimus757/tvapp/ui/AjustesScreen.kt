package com.anonimus757.tvapp.ui

import android.content.Context
import android.content.pm.ActivityInfo
import android.content.Intent
import android.net.Uri
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
import androidx.compose.material3.CircularProgressIndicator
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
import com.anonimus757.tvapp.data.ApkDownloader
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.data.VersionChecker
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.findActivity
import com.anonimus757.tvapp.ui.util.rememberEsTV
import kotlinx.coroutines.delay

@Composable
fun AjustesScreen(onBack: () -> Unit) {
    val context = LocalContext.current

    var calidad by remember { mutableStateOf(AjustesStore.obtenerCalidad(context)) }
    var autoRefresh by remember { mutableStateOf(AjustesStore.obtenerAutoRefresh(context)) }
    var orientacion by remember { mutableStateOf(AjustesStore.obtenerOrientacion(context)) }
    val esTV = rememberEsTV()
    // 🆕 Estado de versión + update
    val config by RemoteConfigRepository.config.collectAsState()
    val estadoDescarga by ApkDownloader.estado.collectAsState()
    val hayUpdate = VersionChecker.hayUpdate(config)
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
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                OpcionCalidad(
                    titulo = "Auto",
                    subtitulo = "Se adapta",
                    seleccionado = calidad == "auto",
                    modifier = Modifier.weight(1f).focusRequester(primerFocus),
                    onClick = {
                        calidad = "auto"
                        AjustesStore.guardarCalidad(context, "auto")
                    }
                )
                OpcionCalidad(
                    titulo = "SD",
                    subtitulo = "480p · datos",
                    seleccionado = calidad == "sd",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        calidad = "sd"
                        AjustesStore.guardarCalidad(context, "sd")
                    }
                )
                OpcionCalidad(
                    titulo = "HD",
                    subtitulo = "1080p · calidad",
                    seleccionado = calidad == "hd",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        calidad = "hd"
                        AjustesStore.guardarCalidad(context, "hd")
                    }
                )
            }

            // Sección: ORIENTACIÓN (solo en celu/tablet)
            if (!esTV) {
                Spacer(Modifier.height(32.dp))
                SeccionTitulo(icono = AppIcons.calidad, texto = "ORIENTACIÓN DE PANTALLA")
                Spacer(Modifier.height(12.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OpcionOrientacion(
                        titulo = "Auto",
                        subtitulo = "Sigue al celu",
                        seleccionado = orientacion == "auto",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "auto"
                            AjustesStore.guardarOrientacion(context, "auto")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Vertical",
                        subtitulo = "Celular parado",
                        seleccionado = orientacion == "vertical",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "vertical"
                            AjustesStore.guardarOrientacion(context, "vertical")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Horizontal",
                        subtitulo = "Celular acostado",
                        seleccionado = orientacion == "horizontal",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "horizontal"
                            AjustesStore.guardarOrientacion(context, "horizontal")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                            } catch (_: Exception) {}
                        }
                    )
                }
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

            // Sección: SOPORTE
            SeccionTitulo(icono = AppIcons.grupos, texto = "SOPORTE")
            Spacer(Modifier.height(12.dp))
            FilaAccion(
                icono = AppIcons.grupos,
                titulo = "Comunidad en Telegram",
                subtitulo = "Ayuda, soporte y novedades · t.me/futtvsoporte",
                onClick = {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/futtvsoporte"))
                        context.startActivity(intent)
                    } catch (_: Exception) {}
                }
            )

            Spacer(Modifier.height(32.dp))

            // Sección: ACTUALIZACIÓN
            SeccionTitulo(icono = AppIcons.refrescar, texto = "ACTUALIZACIÓN")
            Spacer(Modifier.height(12.dp))

            // Card de estado de versión
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(
                        if (hayUpdate) AppColors.Gold.copy(alpha = 0.12f)
                        else AppColors.AccentGreen.copy(alpha = 0.10f)
                    )
                    .border(
                        1.dp,
                        if (hayUpdate) AppColors.Gold.copy(alpha = 0.5f)
                        else AppColors.AccentGreen.copy(alpha = 0.5f),
                        RoundedCornerShape(14.dp)
                    )
                    .padding(16.dp)
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = if (hayUpdate) AppIcons.refrescar else AppIcons.okCirculo,
                            contentDescription = null,
                            tint = if (hayUpdate) AppColors.GoldBright else AppColors.AccentGreen,
                            modifier = Modifier.size(22.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            if (hayUpdate) "Nueva versión disponible" else "Estás al día",
                            color = if (hayUpdate) AppColors.GoldBright else AppColors.AccentGreen,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Versión instalada: ${BuildConfig.VERSION_NAME}",
                        color = AppColors.TextPrimary,
                        fontSize = 13.sp
                    )
                    if (hayUpdate) {
                        Spacer(Modifier.height(2.dp))
                        Text(
                            "Última versión: ${config.versionActual}",
                            color = AppColors.Gold,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )

                        if (config.notasVersion.isNotBlank()) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                config.notasVersion,
                                color = AppColors.TextSecondary,
                                fontSize = 12.sp,
                                lineHeight = 16.sp
                            )
                        }

                        Spacer(Modifier.height(14.dp))

                        // Estado de la descarga
                        when {
                            estadoDescarga.descargando -> {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    CircularProgressIndicator(
                                        color = AppColors.GoldBright,
                                        strokeWidth = 2.dp,
                                        modifier = Modifier.size(20.dp),
                                        progress = { estadoDescarga.progreso / 100f }
                                    )
                                    Spacer(Modifier.width(10.dp))
                                    Text(
                                        "Descargando ${estadoDescarga.progreso}%",
                                        color = AppColors.GoldBright,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }
                            estadoDescarga.error != null -> {
                                Column {
                                    Text(
                                        "❌ ${estadoDescarga.error}",
                                        color = Color(0xFFEF4444),
                                        fontSize = 12.sp
                                    )
                                    Spacer(Modifier.height(8.dp))
                                    BotonDescargarVersion(
                                        texto = "Reintentar",
                                        onClick = {
                                            ApkDownloader.reset()
                                            ApkDownloader.descargar(context, config.urlDescarga, config.versionActual)
                                        }
                                    )
                                }
                            }
                            estadoDescarga.listoParaInstalar -> {
                                BotonDescargarVersion(
                                    texto = "Instalar ahora",
                                    onClick = {
                                        ApkDownloader.instalar(context, config.versionActual)
                                    }
                                )
                            }
                            else -> {
                                BotonDescargarVersion(
                                    texto = "Actualizar ahora",
                                    onClick = {
                                        ApkDownloader.descargar(context, config.urlDescarga, config.versionActual)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(32.dp))

            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")
            Spacer(Modifier.height(12.dp))
            FilaInfo("Versión", "v${BuildConfig.VERSION_NAME}")
            Spacer(Modifier.height(8.dp))
            FilaInfo("Desarrollador", "FutTV")


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
            .fillMaxWidth()
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

@Composable
private fun OpcionOrientacion(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val borderWidth by animateDpAsState(if (focused || seleccionado) 2.dp else 1.dp, tween(180), label = "oo")
    val borderColor by animateColorAsState(
        when {
            focused -> AppColors.GoldBright
            seleccionado -> AppColors.Gold
            else -> AppColors.Gold.copy(alpha = 0.25f)
        },
        tween(180), label = "ooc"
    )
    val bg by animateColorAsState(
        when {
            seleccionado -> AppColors.Gold.copy(alpha = 0.18f)
            focused -> AppColors.CardFocus
            else -> AppColors.Card
        },
        tween(180), label = "oob"
    )

    Column(
        modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            titulo,
            color = if (seleccionado || focused) AppColors.GoldBright else AppColors.TextPrimary,
            fontSize = 18.sp,
            fontWeight = FontWeight.Black
        )
        Spacer(Modifier.height(2.dp))
        Text(
            subtitulo,
            color = AppColors.TextSecondary,
            fontSize = 11.sp,
            maxLines = 1
        )
        if (seleccionado) {
            Spacer(Modifier.height(6.dp))
            Icon(
                imageVector = AppIcons.ok,
                contentDescription = null,
                tint = AppColors.AccentGreen,
                modifier = Modifier.size(14.dp)
            )
        }
    }
}



// ═══════════════════════════════════════════════════════════
// 🆕 Botón de descarga desde Ajustes (sin abrir navegador)
// ═══════════════════════════════════════════════════════════
@Composable
private fun BotonDescargarVersion(texto: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold)
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else Color.Transparent,
                RoundedCornerShape(10.dp)
            )
            .clickable { onClick() }
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.play,
            contentDescription = null,
            tint = Color.Black,
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            texto,
            color = Color.Black,
            fontSize = 14.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp
        )
    }
}
