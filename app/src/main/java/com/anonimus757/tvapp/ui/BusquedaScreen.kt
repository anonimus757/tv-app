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
import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts

@Composable
fun BusquedaScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()

    var query by remember { mutableStateOf("") }

    // ═══════════════════════════════════════════════════════════
    // 🎤 BÚSQUEDA POR VOZ
    // ═══════════════════════════════════════════════════════════
    val voiceLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val texto = result.data?.getStringArrayListExtra(
                RecognizerIntent.EXTRA_RESULTS
            )?.firstOrNull()
            if (!texto.isNullOrBlank()) {
                query = texto
            }
        }
    }

    val abrirVoz: () -> Unit = {
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-ES")
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Decí el equipo o evento")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            voiceLauncher.launch(intent)
        } catch (_: Exception) {}
    }
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
            val config = androidx.compose.ui.platform.LocalConfiguration.current
            val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT

            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = AppIcons.buscar,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(if (esVertical) 24.dp else 34.dp)
                )
                Spacer(Modifier.width(if (esVertical) 8.dp else 12.dp))
                Text(
                    if (esVertical) "Buscar" else "Buscar eventos",
                    color = AppColors.GoldBright,
                    fontSize = if (esVertical) 22.sp else 30.sp,
                    fontWeight = FontWeight.Black
                )
                Spacer(Modifier.weight(1f))
                BotonVolver(onBack)
            }

            Spacer(Modifier.height(24.dp))

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it.take(60) },
                    placeholder = { Text("Boca, River, ESPN...", color = AppColors.TextMuted) },
                    leadingIcon = {
                        Icon(
                            imageVector = AppIcons.buscar,
                            contentDescription = null,
                            tint = AppColors.Gold,
                            modifier = Modifier.size(20.dp)
                        )
                    },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
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
                Spacer(Modifier.width(10.dp))
                BotonVoz(onClick = abrirVoz)
            }

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

// ═══════════════════════════════════════════════════════════
// 🎤 BOTÓN DE BÚSQUEDA POR VOZ
// ═══════════════════════════════════════════════════════════
@Composable
private fun BotonVoz(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Box(
        Modifier
            .size(56.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(12.dp)
            )
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text("🎤", fontSize = 24.sp)
    }
}

