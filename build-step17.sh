#!/bin/bash
set -e

echo "📁 Paso 17: Tema dorado/negro + Canales en Vivo M3U..."

# ========== Theme.kt (Dorado + Negro premium) ==========
mkdir -p app/src/main/java/com/anonimus757/tvapp/ui/theme
cat > app/src/main/java/com/anonimus757/tvapp/ui/theme/Theme.kt << 'KTEOF'
package com.anonimus757.tvapp.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    // Fondos
    val Background = Color(0xFF000000)
    val BackgroundGradient = Color(0xFF0A0A0A)
    val Surface = Color(0xFF121212)
    val SurfaceLight = Color(0xFF1A1A1A)
    val SurfaceFocus = Color(0xFF2A2A2A)
    val Card = Color(0xFF141414)
    val CardFocus = Color(0xFF1F1F1F)

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

    // Colores por fuente
    fun fuenteColor(groupTitle: String): Color = when {
        groupTitle.contains("EVENTOS 2") -> Color(0xFFE8A020)   // Ámbar
        groupTitle.contains("EVENTOS 3") -> Color(0xFFB8860B)   // Oscuro dorado
        else -> Gold                                              // Dorado
    }

    fun fuenteIcono(groupTitle: String): String = when {
        groupTitle.contains("EVENTOS 2") -> "⚽"
        groupTitle.contains("EVENTOS 3") -> "🏆"
        else -> "🎯"
    }
}
KTEOF

# ========== Models.kt (añadir Canal) ==========
cat > app/src/main/java/com/anonimus757/tvapp/data/Models.kt << 'KTEOF'
package com.anonimus757.tvapp.data

data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>
)

data class Embed(
    val nombre: String,
    val url: String,
    val referer: String
)

data class Fuente(
    val id: String,
    val nombre: String,
    val groupTitle: String,
    val base: String,
    val agenda: String,
    val imgBase: String,
    val imgDefault: String,
    val flagsBase: String?,
    val tipo: String
)

data class Canal(
    val id: String,
    val nombre: String,
    val url: String,
    val logo: String,
    val grupo: String,
    val tvgId: String
)

data class GrupoCanales(
    val nombre: String,
    val canales: List<Canal>
)
KTEOF

# ========== ChannelRepository.kt (cargar y parsear M3U) ==========
cat > app/src/main/java/com/anonimus757/tvapp/data/ChannelRepository.kt << 'KTEOF'
package com.anonimus757.tvapp.data

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object ChannelRepository {

    private const val TAG = "ChannelRepo"
    const val M3U_URL = "https://raw.githack.com/anonimus757/dev-config-backup/main/tv.m3u"

    private val client: OkHttpClient by lazy {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(c: Array<X509Certificate>, a: String) {}
            override fun checkServerTrusted(c: Array<X509Certificate>, a: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val ssl = SSLContext.getInstance("TLS").apply { init(null, trustAll, java.security.SecureRandom()) }
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .sslSocketFactory(ssl.socketFactory, trustAll[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    suspend fun cargarCanales(onProgreso: (String) -> Unit = {}): List<GrupoCanales> =
        withContext(Dispatchers.IO) {
            try {
                onProgreso("Descargando lista M3U...")
                val body = httpGet(M3U_URL) ?: return@withContext emptyList()

                onProgreso("Parseando canales...")
                val canales = parsearM3U(body)

                onProgreso("Agrupando ${canales.size} canales...")
                val grupos = canales.groupBy { it.grupo }
                    .map { (nombre, lista) ->
                        GrupoCanales(
                            nombre = nombre.ifBlank { "Sin categoría" },
                            canales = lista.sortedBy { it.nombre }
                        )
                    }
                    .sortedBy { it.nombre }

                Log.d(TAG, "✅ ${canales.size} canales en ${grupos.size} grupos")
                grupos
            } catch (e: Exception) {
                Log.e(TAG, "Error: ${e.message}")
                emptyList()
            }
        }

    private fun parsearM3U(contenido: String): List<Canal> {
        val canales = mutableListOf<Canal>()
        val lineas = contenido.split("\n")
        var i = 0
        var contador = 0

        while (i < lineas.size) {
            val linea = lineas[i].trim()

            if (linea.startsWith("#EXTINF")) {
                // Parsear atributos
                val tvgId = extraerAtributo(linea, "tvg-id")
                val tvgLogo = extraerAtributo(linea, "tvg-logo")
                val groupTitle = extraerAtributo(linea, "group-title")

                // Nombre del canal (después de la última coma)
                val coma = linea.lastIndexOf(",")
                val nombre = if (coma > 0) linea.substring(coma + 1).trim() else "Canal"

                // La URL está en la siguiente línea no vacía y no comentario
                var j = i + 1
                while (j < lineas.size && (lineas[j].isBlank() || lineas[j].trim().startsWith("#"))) {
                    j++
                }

                if (j < lineas.size) {
                    val url = lineas[j].trim()
                    if (url.startsWith("http")) {
                        canales.add(
                            Canal(
                                id = "ch_${contador++}",
                                nombre = nombre,
                                url = url,
                                logo = tvgLogo,
                                grupo = groupTitle,
                                tvgId = tvgId
                            )
                        )
                    }
                    i = j + 1
                    continue
                }
            }
            i++
        }
        return canales
    }

    private fun extraerAtributo(linea: String, nombre: String): String {
        val regex = Regex("""$nombre="([^"]*)"""")
        return regex.find(linea)?.groupValues?.get(1) ?: ""
    }

    private fun httpGet(url: String): String? {
        return try {
            val req = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36")
                .build()
            client.newCall(req).execute().use { it.body?.string() }
        } catch (e: Exception) {
            Log.e(TAG, "GET fail: ${e.message}")
            null
        }
    }
}
KTEOF

# ========== LiveChannelsScreen.kt (Canales en vivo) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/LiveChannelsScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
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
import com.anonimus757.tvapp.data.Canal
import com.anonimus757.tvapp.data.ChannelRepository
import com.anonimus757.tvapp.data.GrupoCanales
import com.anonimus757.tvapp.ui.theme.AppColors

@Composable
fun LiveChannelsScreen(onCanalClick: (Canal) -> Unit) {
    var grupos by remember { mutableStateOf<List<GrupoCanales>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("Conectando...") }

    LaunchedEffect(Unit) {
        grupos = ChannelRepository.cargarCanales { status = it }
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
                    Spacer(Modifier.height(20.dp))
                    Text("📡 Canales en Vivo", color = AppColors.Gold, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 16.sp)
                }
            }
        } else if (grupos.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📭", fontSize = 60.sp)
                    Spacer(Modifier.height(16.dp))
                    Text("No hay canales", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
                }
            }
        } else {
            ContenidoCanales(grupos, onCanalClick)
        }
    }
}

@Composable
private fun ContenidoCanales(grupos: List<GrupoCanales>, onCanalClick: (Canal) -> Unit) {
    val totalCanales = grupos.sumOf { it.canales.size }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 28.dp, bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item(key = "header") {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("📡", fontSize = 30.sp)
                Spacer(Modifier.width(12.dp))
                Text("Canales en Vivo", color = AppColors.Gold, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(16.dp))
                Text("En directo", color = AppColors.GoldBright, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.weight(1f))
                Text("$totalCanales canales · ${grupos.size} categorías", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
        }

        item(key = "space1") { Spacer(Modifier.height(16.dp)) }

        grupos.forEach { grupo ->
            item(key = "header_${grupo.nombre}") {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        Modifier.width(5.dp).height(28.dp).clip(RoundedCornerShape(3.dp))
                            .background(AppColors.Gold)
                    )
                    Spacer(Modifier.width(14.dp))
                    Text("📺", fontSize = 22.sp)
                    Spacer(Modifier.width(8.dp))
                    Text(grupo.nombre, color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(12.dp))
                    Box(
                        Modifier.clip(RoundedCornerShape(10.dp))
                            .background(AppColors.Gold.copy(alpha = 0.2f))
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                    ) {
                        Text("${grupo.canales.size}", color = AppColors.Gold, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }

            item(key = "row_${grupo.nombre}") {
                FilaCanales(grupo.canales, onCanalClick)
            }

            item(key = "space_${grupo.nombre}") { Spacer(Modifier.height(28.dp)) }
        }
    }
}

@Composable
private fun FilaCanales(lista: List<Canal>, onCanalClick: (Canal) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        items(lista, key = { it.id }) { canal ->
            CanalCardPro(canal) { onCanalClick(canal) }
        }
    }
}

@Composable
private fun CanalCardPro(canal: Canal, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Column(
        Modifier
            .width(220.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            Modifier
                .size(90.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(
                    Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))
                ),
            contentAlignment = Alignment.Center
        ) {
            if (canal.logo.isNotBlank()) {
                AsyncImage(
                    model = canal.logo,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(70.dp)
                )
            } else {
                Text("📺", fontSize = 36.sp)
            }
        }

        Spacer(Modifier.height(10.dp))

        Text(
            canal.nombre,
            color = AppColors.TextPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            lineHeight = 17.sp
        )

        Spacer(Modifier.height(8.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(6.dp).clip(CircleShape)
                    .background(if (focused) AppColors.AccentGreen else AppColors.TextMuted)
            )
            Spacer(Modifier.width(6.dp))
            Text(
                if (focused) "▶ Reproducir" else "En vivo",
                color = if (focused) AppColors.AccentGreen else AppColors.TextMuted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}
KTEOF

# ========== HomeScreen.kt (Premium dorado/negro) ==========
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
fun HomeScreen(
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onCanalesVivoClick: () -> Unit
) {
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
                    Spacer(Modifier.height(20.dp))
                    Text("🎛️ TV App", color = AppColors.Gold, fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 16.sp)
                }
            }
        } else if (eventos.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📭", fontSize = 60.sp)
                    Spacer(Modifier.height(16.dp))
                    Text("No hay eventos", color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(status, color = AppColors.TextSecondary, fontSize = 14.sp)
                }
            }
        } else {
            ContenidoHome(eventos, onEventoClick, onCanalesVivoClick)
        }
    }
}

@Composable
private fun ContenidoHome(
    eventos: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    onCanalesVivoClick: () -> Unit
) {
    val grupos = eventos.groupBy { it.groupTitle }
    val totalCanales = eventos.sumOf { it.embeds.size }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 28.dp, bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item(key = "header") {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🎛️", fontSize = 30.sp)
                Spacer(Modifier.width(12.dp))
                Text("TV App", color = AppColors.TextPrimary, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(16.dp))
                Text("En vivo", color = AppColors.Gold, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Spacer(Modifier.weight(1f))
                Text("${eventos.size} eventos · $totalCanales canales", color = AppColors.TextSecondary, fontSize = 13.sp)
            }
        }

        item(key = "menu_canales_vivo") {
            MenuCanalesVivo(onCanalesVivoClick)
        }

        item(key = "space1") { Spacer(Modifier.height(24.dp)) }

        grupos.forEach { (titulo, lista) ->
            item(key = "header_$titulo") { HeaderCategoria(titulo, lista.size) }
            item(key = "row_$titulo") { FilaEventos(lista, onEventoClick) }
            item(key = "space_$titulo") { Spacer(Modifier.height(28.dp)) }
        }
    }
}

@Composable
private fun MenuCanalesVivo(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp, vertical = 8.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(16.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        if (focused) AppColors.Gold.copy(alpha = 0.25f) else AppColors.Card,
                        if (focused) AppColors.Gold.copy(alpha = 0.1f) else AppColors.Card
                    )
                )
            )
            .border(
                width = if (focused) 2.dp else 1.dp,
                color = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.3f),
                shape = RoundedCornerShape(16.dp)
            )
            .padding(20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(60.dp).clip(CircleShape)
                .background(AppColors.Gold.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center
        ) {
            Text("📡", fontSize = 30.sp)
        }
        Spacer(Modifier.width(20.dp))
        Column(Modifier.weight(1f)) {
            Text("Canales en Vivo", color = AppColors.GoldBright, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text("Ver todos los canales IPTV · Deportes, Películas, Series y más", color = AppColors.TextSecondary, fontSize = 13.sp)
        }
        Text(if (focused) "▶" else "→", color = AppColors.GoldBright, fontSize = 20.sp, fontWeight = FontWeight.Bold)
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
        Box(
            Modifier.width(5.dp).height(28.dp).clip(RoundedCornerShape(3.dp)).background(color)
        )
        Spacer(Modifier.width(14.dp))
        Text(icono, fontSize = 22.sp)
        Spacer(Modifier.width(8.dp))
        Text(titulo, color = AppColors.TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(12.dp))
        Box(
            Modifier.clip(RoundedCornerShape(10.dp))
                .background(color.copy(alpha = 0.2f))
                .padding(horizontal = 10.dp, vertical = 3.dp)
        ) {
            Text("$total", color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
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
                width = if (focused) 2.dp else 1.dp,
                color = if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
                shape = RoundedCornerShape(14.dp)
            )
            .padding(14.dp)
    ) {
        Box(
            Modifier.fillMaxWidth().height(140.dp).clip(RoundedCornerShape(10.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = ev.imagen,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(100.dp)
            )

            Box(
                Modifier.align(Alignment.TopEnd).padding(8.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(color.copy(alpha = 0.9f))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(ev.hora, color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
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
            Box(Modifier.size(6.dp).clip(CircleShape).background(AppColors.AccentGreen))
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

# ========== EventDetailScreen.kt (con tema dorado) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
                Brush.verticalGradient(listOf(AppColors.Background, AppColors.BackgroundGradient))
            )
    ) {
        Column(Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 36.dp)) {

            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(110.dp).clip(RoundedCornerShape(16.dp))
                        .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
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
                            Modifier.clip(RoundedCornerShape(6.dp))
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
                    Modifier.clip(RoundedCornerShape(10.dp))
                        .background(AppColors.Gold.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("${evento.embeds.size}", color = AppColors.Gold, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
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
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(
                width = if (focused) 2.dp else 1.dp,
                color = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.2f),
                shape = RoundedCornerShape(14.dp)
            )
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(50.dp).clip(CircleShape)
                .background(if (focused) AppColors.GoldBright else AppColors.Gold),
            contentAlignment = Alignment.Center
        ) {
            Text("▶", color = Color.Black, fontSize = 24.sp, fontWeight = FontWeight.Bold)
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
            color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            fontSize = 14.sp,
            fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}
KTEOF

# ========== MainActivity.kt (navegación actualizada) ==========
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
                    },
                    onCanalesVivoClick = {
                        screen = Screen.CanalesVivo
                    }
                )

                is Screen.CanalesVivo -> LiveChannelsScreen(
                    onCanalClick = { canal ->
                        screen = Screen.PlayerCanal(canal)
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

                is Screen.PlayerCanal -> {
                    key(s.canal.id) {
                        PlayerCanalScreen(
                            canal = s.canal,
                            onBack = { screen = Screen.CanalesVivo }
                        )
                    }
                }
            }
        }
    }
}
KTEOF

# ========== Screen.kt (añadir pantallas nuevas) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/Screen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Canal
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen
    data object CanalesVivo : Screen

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

    data class PlayerCanal(val canal: Canal) : Screen
}

enum class VolverA { Home, Player }
KTEOF

# ========== PlayerCanalScreen.kt (reproductor simple para canales M3U) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/PlayerCanalScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.Canal
import kotlinx.coroutines.delay

private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

@SuppressLint("UnsafeOptInUsageError")
@Composable
fun PlayerCanalScreen(canal: Canal, onBack: () -> Unit) {
    val context = LocalContext.current
    var cargando by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    val exoPlayer = remember {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 20000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        val trackSelector = DefaultTrackSelector(context).apply {
            setParameters(buildUponParameters().setMaxVideoSizeSd())
        }
        ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .setTrackSelector(trackSelector)
            .build().apply {
                addListener(object : Player.Listener {
                    override fun onPlayerError(e: PlaybackException) {
                        error = "${e.errorCodeName}: ${e.message?.take(150)}"
                    }
                    override fun onPlaybackStateChanged(state: Int) {
                        if (state == Player.STATE_READY) {
                            cargando = false
                            error = null
                        }
                    }
                })
            }
    }

    DisposableEffect(Unit) {
        onDispose { exoPlayer.release() }
    }

    LaunchedEffect(canal.id) {
        try {
            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to "https://liontv.es/"
            )

            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)

            val src = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(true)
                .createMediaSource(MediaItem.fromUri(Uri.parse(canal.url)))

            exoPlayer.setMediaSource(src)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            error = "Init: ${e.message}"
        }
    }

    BackHandler { onBack() }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (error == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        Column(
            Modifier.fillMaxWidth().background(Color(0xCC000000)).padding(20.dp)
        ) {
            Text(canal.nombre, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(canal.grupo, color = Color(0xFFD4AF37), fontSize = 13.sp)
        }

        if (cargando || error != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(30.dp)) {
                    if (error == null) {
                        CircularProgressIndicator(color = Color(0xFFD4AF37))
                        Spacer(Modifier.height(16.dp))
                        Text("Cargando ${canal.nombre}...", color = Color(0xFFCCCCCC), fontSize = 16.sp)
                    } else {
                        Text("⚠️ $error", color = Color(0xFFEF4444), fontSize = 15.sp, maxLines = 4)
                        Spacer(Modifier.height(8.dp))
                        Text("Atrás para volver", color = Color(0xFF94A3B8), fontSize = 13.sp)
                    }
                }
            }
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 17 completo — Tema dorado/negro + Canales en Vivo"
find app/src/main/java/com/anonimus757/tvapp -type f