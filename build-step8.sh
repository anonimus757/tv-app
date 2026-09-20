#!/bin/bash
set -e

echo "📁 Paso 8: Detalle + Reproductor..."

# ========== app/build.gradle.kts (con Media3) ==========
cat > app/build.gradle.kts << 'GRADLEEOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.anonimus757.tvapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.anonimus757.tvapp"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")

    implementation(platform("androidx.compose:compose-bom:2024.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.tv:tv-material:1.0.0")

    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
GRADLEEOF

# ========== Screen.kt (navegación) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/Screen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen
    data class Detail(val evento: Evento) : Screen
    data class Player(val evento: Evento, val embed: Embed) : Screen
}
KTEOF

# ========== MainActivity.kt (navegación) ==========
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
                    onEventoClick = { screen = Screen.Detail(it) }
                )
                is Screen.Detail -> EventDetailScreen(
                    evento = s.evento,
                    onCanalClick = { screen = Screen.Player(s.evento, it) },
                    onBack = { screen = Screen.Home }
                )
                is Screen.Player -> PlayerScreen(
                    evento = s.evento,
                    embed = s.embed,
                    onBack = { screen = Screen.Detail(s.evento) }
                )
            }
        }
    }
}
KTEOF

# ========== HomeScreen.kt (clickeable) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento

private val BG = Color(0xFF0A0F1E)
private val CARD = Color(0xFF1E293B)
private val CARD_FOCUS = Color(0xFF334155)
private val ACENTO = Color(0xFF38BDF8)
private val TEXTO = Color(0xFFE2E8F0)
private val GRIS = Color(0xFF94A3B8)

@Composable
fun HomeScreen(onEventoClick: (Evento) -> Unit) {
    var eventos by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("Cargando eventos...") }

    LaunchedEffect(Unit) {
        try {
            eventos = EventRepository.obtenerTodosLosEventos { msg -> status = msg }
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargando = false
    }

    Box(Modifier.fillMaxSize().background(BG)) {
        Column(Modifier.fillMaxSize().padding(24.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(bottom = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🎛️ TV App", color = ACENTO, fontSize = 32.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(20.dp))
                Text("Eventos de hoy", color = GRIS, fontSize = 18.sp)
                Spacer(Modifier.weight(1f))
                Text("${eventos.size} eventos", color = GRIS, fontSize = 14.sp)
            }

            if (cargando) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = ACENTO)
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = GRIS, fontSize = 16.sp)
                    }
                }
            } else if (eventos.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(status, color = GRIS, fontSize = 18.sp)
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    contentPadding = PaddingValues(bottom = 24.dp)
                ) {
                    items(eventos, key = { "${it.fuente}_${it.hora}_${it.descripcion}" }) { ev ->
                        EventoCard(ev) { onEventoClick(ev) }
                    }
                }
            }
        }
    }
}

@Composable
private fun EventoCard(ev: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) CARD_FOCUS else CARD)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(60.dp).clip(RoundedCornerShape(8.dp)).background(Color(0xFF0F172A)),
            contentAlignment = Alignment.Center
        ) {
            AsyncImage(
                model = ev.imagen,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(50.dp)
            )
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(ev.descripcion, color = TEXTO, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
            Spacer(Modifier.height(4.dp))
            Text("${ev.fuente} · ${ev.embeds.size} canales", color = GRIS, fontSize = 13.sp)
        }
        Spacer(Modifier.width(14.dp))
        Text(ev.hora, color = ACENTO, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}
KTEOF

# ========== EventDetailScreen.kt ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
fun EventDetailScreen(evento: Evento, onCanalClick: (Embed) -> Unit, onBack: () -> Unit) {
    Box(Modifier.fillMaxSize().background(BG)) {
        Column(Modifier.fillMaxSize().padding(28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(
                    model = evento.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(80.dp)
                )
                Spacer(Modifier.width(18.dp))
                Column(Modifier.weight(1f)) {
                    Text(evento.descripcion, color = TEXTO, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                    Spacer(Modifier.height(4.dp))
                    Text("${evento.hora} · ${evento.fuente}", color = GRIS, fontSize = 15.sp)
                }
            }

            Spacer(Modifier.height(28.dp))
            Text("Canales disponibles", color = ACENTO, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(14.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(evento.embeds) { embed ->
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
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) CARD_FOCUS else CARD)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(40.dp).clip(RoundedCornerShape(20.dp))
                .background(if (focused) VERDE else ACENTO),
            contentAlignment = Alignment.Center
        ) {
            Text("▶", color = Color.Black, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.width(16.dp))
        Text(embed.nombre, color = TEXTO, fontSize = 18.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Text("Reproducir →", color = ACENTO, fontSize = 14.sp)
    }
}
KTEOF

# ========== PlayerScreen.kt (WebView + ExoPlayer) ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.view.ViewGroup
import android.webkit.*
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
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import kotlinx.coroutines.delay

private const val USER_AGENT =
    "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun PlayerScreen(evento: Evento, embed: Embed, onBack: () -> Unit) {
    val context = LocalContext.current
    var m3u8Url by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("Resolviendo stream...") }
    var error by remember { mutableStateOf<String?>(null) }

    val exoPlayer = remember {
        ExoPlayer.Builder(context).build()
    }

    DisposableEffect(Unit) {
        onDispose { exoPlayer.release() }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        // Reproductor (visible cuando hay m3u8)
        if (m3u8Url != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = true
                        setShowNextButton(false)
                        setShowPreviousButton(false)
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        // Overlay superior con info del evento
        Column(
            Modifier
                .fillMaxWidth()
                .background(Color(0xCC000000))
                .padding(20.dp)
                .align(Alignment.TopStart)
        ) {
            Text(evento.descripcion, color = Color(0xFFE2E8F0), fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text("${embed.nombre} · ${evento.hora}", color = Color(0xFF94A3B8), fontSize = 13.sp)
        }

        // Spinner / Error
        if (m3u8Url == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (error == null) {
                        CircularProgressIndicator(color = Color(0xFF38BDF8))
                        Spacer(Modifier.height(16.dp))
                        Text(status, color = Color(0xFF94A3B8), fontSize = 16.sp)
                    } else {
                        Text("⚠️ ${error}", color = Color(0xFFEF4444), fontSize = 18.sp)
                        Spacer(Modifier.height(8.dp))
                        Text("Presiona atrás para volver", color = Color(0xFF94A3B8), fontSize = 14.sp)
                    }
                }
            }
        }

        // WebView invisible (1px) - carga el embed y captura el .m3u8
        if (m3u8Url == null && error == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        layoutParams = ViewGroup.LayoutParams(1, 1)
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.userAgentString = USER_AGENT
                        settings.mediaPlaybackRequiresUserGesture = false
                        settings.allowFileAccess = true
                        settings.loadsImagesAutomatically = true
                        setBackgroundColor(AndroidColor.TRANSPARENT)

                        var resolved = false

                        webViewClient = object : WebViewClient() {
                            override fun shouldInterceptRequest(
                                view: WebView?,
                                request: WebResourceRequest?
                            ): WebResourceResponse? {
                                val url = request?.url?.toString() ?: return null
                                if (!resolved && url.contains(".m3u8", ignoreCase = true)) {
                                    resolved = true
                                    m3u8Url = url
                                }
                                return super.shouldInterceptRequest(view, request)
                            }

                            override fun onReceivedError(
                                view: WebView?,
                                request: WebResourceRequest?,
                                errorResponse: WebResourceError?
                            ) {
                                // ignorar
                            }
                        }

                        loadUrl(embed.url, mapOf("Referer" to embed.referer))

                        // Timeout de 20s
                        postDelayed({
                            if (!resolved) {
                                error = "No se pudo extraer el stream (timeout)"
                            }
                        }, 20000)
                    }
                },
                modifier = Modifier.size(1.dp)
            )
        }
    }

    // Cuando tengamos m3u8, lo cargamos en ExoPlayer
    LaunchedEffect(m3u8Url) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando reproductor..."
            val dsFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(mapOf("Referer" to embed.referer))
                .setAllowCrossProtocolRedirects(true)

            val mediaSource = HlsMediaSource.Factory(dsFactory)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            exoPlayer.setMediaSource(mediaSource)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (e: Exception) {
            error = "Error reproductor: ${e.message}"
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 8 completo"
find app/src/main/java -type f