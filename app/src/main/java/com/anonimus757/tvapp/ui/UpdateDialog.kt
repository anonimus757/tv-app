package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.anonimus757.tvapp.data.ApkDownloader
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

@Composable
fun UpdateDialog(
    versionNueva: String,
    notasVersion: String,
    urlDescarga: String,
    obligatorio: Boolean,
    onCerrar: () -> Unit
) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val esVertical = configuration.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT

    // Ancho adaptativo: en vertical → casi full, en horizontal → 520dp
    val anchoDialog = if (esVertical) {
        configuration.screenWidthDp.dp - 32.dp
    } else {
        520.dp
    }

    // Estado de la descarga
    val estadoDescarga by ApkDownloader.estado.collectAsState()

    // Al terminar de descargar → abrir instalador automáticamente
    LaunchedEffect(estadoDescarga.listoParaInstalar) {
        if (estadoDescarga.listoParaInstalar) {
            ApkDownloader.instalar(context, versionNueva)
        }
    }

    Dialog(
        onDismissRequest = { if (!obligatorio && !estadoDescarga.descargando) onCerrar() },
        properties = DialogProperties(
            dismissOnBackPress = !obligatorio && !estadoDescarga.descargando,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false
        )
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color(0xDD000000)),
            contentAlignment = Alignment.Center
        ) {
            Column(
                Modifier
                    .width(anchoDialog)
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.verticalGradient(
                            listOf(AppColors.SurfaceLight, AppColors.Surface)
                        )
                    )
                    .border(2.dp, AppColors.Gold, RoundedCornerShape(24.dp))
                    .padding(if (esVertical) 24.dp else 32.dp)
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("🚀", fontSize = if (esVertical) 52.sp else 64.sp)
                Spacer(Modifier.height(if (esVertical) 10.dp else 16.dp))

                Text(
                    "Nueva versión disponible",
                    color = AppColors.GoldBright,
                    fontSize = if (esVertical) 20.sp else 24.sp,
                    fontWeight = FontWeight.Black,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )

                Spacer(Modifier.height(6.dp))

                Text(
                    "v$versionNueva",
                    color = AppColors.TextSecondary,
                    fontSize = if (esVertical) 14.sp else 16.sp,
                    fontWeight = FontWeight.Bold
                )

                if (notasVersion.isNotBlank()) {
                    Spacer(Modifier.height(if (esVertical) 16.dp else 20.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color(0x33D4AF37))
                            .padding(if (esVertical) 12.dp else 16.dp)
                    ) {
                        Column {
                            Text(
                                "¿Qué hay nuevo?",
                                color = AppColors.Gold,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 1.sp
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                notasVersion,
                                color = AppColors.TextPrimary,
                                fontSize = if (esVertical) 13.sp else 14.sp,
                                lineHeight = 20.sp
                            )
                        }
                    }
                }

                if (obligatorio) {
                    Spacer(Modifier.height(14.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0x33EF4444))
                            .padding(12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = AppIcons.advertencia,
                                contentDescription = null,
                                tint = Color(0xFFEF4444),
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Esta actualización es obligatoria",
                                color = Color(0xFFEF4444),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }

                Spacer(Modifier.height(if (esVertical) 20.dp else 28.dp))

                // Si está descargando → mostrar progreso
                if (estadoDescarga.descargando) {
                    CircularProgressIndicator(
                        color = AppColors.GoldBright,
                        strokeWidth = 3.dp,
                        modifier = Modifier.size(48.dp),
                        progress = { estadoDescarga.progreso / 100f }
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Descargando... ${estadoDescarga.progreso}%",
                        color = AppColors.GoldBright,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                } else if (estadoDescarga.error != null) {
                    Text(
                        "❌ ${estadoDescarga.error}",
                        color = Color(0xFFEF4444),
                        fontSize = 13.sp
                    )
                    Spacer(Modifier.height(12.dp))
                    BotonUpdate(
                        texto = "Reintentar",
                        esPrimario = true,
                        onClick = {
                            ApkDownloader.reset()
                            ApkDownloader.descargar(context, urlDescarga, versionNueva)
                        }
                    )
                } else if (estadoDescarga.listoParaInstalar) {
                    Text(
                        "✅ Descarga completa",
                        color = Color(0xFF4ADE80),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(12.dp))
                    BotonUpdate(
                        texto = "Instalar ahora",
                        esPrimario = true,
                        onClick = { ApkDownloader.instalar(context, versionNueva) }
                    )
                } else {
                    BotonUpdate(
                        texto = "Actualizar ahora",
                        esPrimario = true,
                        onClick = {
                            ApkDownloader.descargar(context, urlDescarga, versionNueva)
                        }
                    )

                    if (!obligatorio) {
                        Spacer(Modifier.height(12.dp))
                        BotonUpdate(
                            texto = "Después",
                            esPrimario = false,
                            onClick = {
                                ApkDownloader.reset()
                                onCerrar()
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BotonUpdate(
    texto: String,
    esPrimario: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg = when {
        esPrimario && focused -> AppColors.GoldBright
        esPrimario -> AppColors.Gold
        focused -> AppColors.CardFocus
        else -> AppColors.Surface
    }
    val color = when {
        esPrimario -> Color.Black
        focused -> AppColors.GoldBright
        else -> AppColors.TextSecondary
    }

    Box(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.02f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else Color.Transparent,
                RoundedCornerShape(14.dp)
            )
            .clickable { onClick() }
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            texto,
            color = color,
            fontSize = 16.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 1.sp
        )
    }
}
