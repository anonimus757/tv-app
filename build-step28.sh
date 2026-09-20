#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

# ─────────────────────────────────────────────────────────────
# 1) EventRepository.kt → Firebase + scraping
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo EventRepository.kt (Firebase + scraping)..."

cat > "$PKG_DIR/data/EventRepository.kt" << 'EOF'
package com.anonimus757.tvapp.data

import android.util.Log
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object EventRepository {

    private const val TAG = "EventRepo"

    private const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"

    private val client: OkHttpClient by lazy {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(c: Array<X509Certificate>, a: String) {}
            override fun checkServerTrusted(c: Array<X509Certificate>, a: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslCtx = SSLContext.getInstance("SSL").apply { init(null, trustAll, java.security.SecureRandom()) }
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .sslSocketFactory(sslCtx.socketFactory, trustAll[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    // ═══════════════════════════════════════════════════════════
    // FIRESTORE (eventos personalizados)
    // ═══════════════════════════════════════════════════════════

    /** Lee todos los eventos activos de Firestore. */
    suspend fun obtenerEventosFirestore(): List<Evento> = withContext(Dispatchers.IO) {
        try {
            val db = FirebaseFirestore.getInstance()
            val snap = db.collection("eventos")
                .whereEqualTo("activo", true)
                .get()
                .await()
            val lista = snap.documents.mapNotNull { parsearEventoFirestore(it) }
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos")
            lista
        } catch (e: Exception) {
            Log.e(TAG, "❌ Firestore fail: ${e.message}")
            emptyList()
        }
    }

    private fun parsearEventoFirestore(doc: DocumentSnapshot): Evento? {
        return try {
            val descripcion = doc.getString("descripcion") ?: return null
            val hora = doc.getString("hora") ?: "--:--"
            val categoria = doc.getString("categoria") ?: "EVENTOS"
            val fuente = doc.getString("fuente") ?: "Personalizado"
            val imagen = doc.getString("imagen") ?: ""

            @Suppress("UNCHECKED_CAST")
            val embedsRaw = doc.get("embeds") as? List<Map<String, Any?>> ?: emptyList()

            val embeds = embedsRaw.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim())
            }

            if (embeds.isEmpty()) {
                Log.w(TAG, "⚠️ Evento '$descripcion' sin embeds, se omite")
                return null
            }

            Evento(
                fuente = fuente,
                groupTitle = categoria,
                descripcion = descripcion,
                hora = hora,
                imagen = imagen,
                embeds = embeds
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ parsear fail: ${e.message}")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // SCRAPING (agendas externas)
    // ═══════════════════════════════════════════════════════════

    /** Scraping de las 3 fuentes externas (Futbollibre, etc.). */
    suspend fun obtenerEventosScraping(onProgreso: (String) -> Unit = {}): List<Evento> =
        withContext(Dispatchers.IO) {
            val resultado = mutableListOf<Evento>()
            for (fuente in FUENTES) {
                try {
                    onProgreso("Cargando ${fuente.nombre}...")
                    val eventos = when (fuente.tipo) {
                        "json" -> obtenerEventosJson(fuente)
                        "js" -> obtenerEventosJs(fuente)
                        else -> emptyList()
                    }
                    resultado.addAll(eventos)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ ${fuente.nombre}: ${e.message}")
                }
            }
            Log.d(TAG, "✅ Scraping: ${resultado.size} eventos")
            resultado
        }

    /** Compat: combina Firestore + scraping (por si algún otro archivo lo usa). */
    suspend fun obtenerTodosLosEventos(onProgreso: (String) -> Unit = {}): List<Evento> {
        val fb = obtenerEventosFirestore()
        val sc = obtenerEventosScraping(onProgreso)
        return fb + sc
    }

    private fun obtenerEventosJson(fuente: Fuente): List<Evento> {
        val body = httpGet(fuente.agenda) ?: return emptyList()
        val data = JSONObject(body).optJSONArray("data") ?: return emptyList()
        val eventos = mutableListOf<Evento>()

        for (i in 0 until data.length()) {
            val ev = data.optJSONObject(i) ?: continue
            val attrs = ev.optJSONObject("attributes") ?: continue

            val desc = limpiar(attrs.optString("diary_description", "?"))
            var hora = limpiar(attrs.optString("diary_hour", "--:--"))
            if (hora.contains(":")) hora = hora.take(5)

            var img = fuente.imgDefault
            try {
                val ruta = attrs.getJSONObject("country").getJSONObject("data")
                    .getJSONObject("attributes").getJSONObject("image")
                    .getJSONObject("data").getJSONObject("attributes").getString("url")
                img = if (ruta.startsWith("http")) ruta else fuente.imgBase + ruta
            } catch (_: Exception) {}

            val embeds = mutableListOf<Embed>()
            val arr = attrs.optJSONObject("embeds")?.optJSONArray("data")
            if (arr != null) {
                for (j in 0 until arr.length()) {
                    val ea = arr.optJSONObject(j)?.optJSONObject("attributes") ?: continue
                    val nombre = limpiar(ea.optString("embed_name", "Canal"))
                    val url = adaptarUrl(ea.optString("embed_iframe", ""), fuente.base)
                    if (url != null) embeds.add(Embed(nombre, url, "${fuente.base}/"))
                }
            }

            if (embeds.isNotEmpty()) {
                eventos.add(Evento(fuente.nombre, fuente.groupTitle, desc, hora, img, embeds))
            }
        }
        return eventos
    }

    private fun obtenerEventosJs(fuente: Fuente): List<Evento> {
        val body = httpGet(fuente.agenda) ?: return emptyList()
        val regex = Regex("const\\s+EVENTOS_DATA\\s*=\\s*(\\[.*?\\]);", RegexOption.DOT_MATCHES_ALL)
        val match = regex.find(body) ?: return emptyList()
        val arr = JSONArray(match.groupValues[1])
        val eventos = mutableListOf<Evento>()

        for (i in 0 until arr.length()) {
            val ev = arr.optJSONObject(i) ?: continue
            val titulo = limpiar(ev.optString("titulo", "?"))
            val hora = limpiar(ev.optString("hora", "--:--"))
            val clase = ev.optString("clase", "")
            val canales = ev.optJSONArray("canales") ?: continue

            var img = fuente.imgDefault
            MAPA_LOGOS[clase]?.let { archivo ->
                img = if (archivo.startsWith("//")) "https:$archivo"
                else (fuente.flagsBase ?: "") + archivo
            }

            val embeds = mutableListOf<Embed>()
            for (j in 0 until canales.length()) {
                val c = canales.optJSONObject(j) ?: continue
                val url = adaptarUrl(c.optString("url", ""), fuente.base)
                if (url != null) {
                    embeds.add(Embed(limpiar(c.optString("nombre", "Canal")), url, "${fuente.base}/"))
                }
            }

            if (embeds.isNotEmpty()) {
                eventos.add(Evento(fuente.nombre, fuente.groupTitle, titulo, hora, img, embeds))
            }
        }
        return eventos
    }

    private fun httpGet(url: String): String? {
        val req = Request.Builder().url(url).header("User-Agent", USER_AGENT).build()
        return client.newCall(req).execute().use { it.body?.string() }
    }

    private fun limpiar(t: String): String = t.replace(Regex("\\s+"), " ").trim()

    private fun adaptarUrl(url: String, base: String): String? {
        if (url.isBlank()) return null
        var u = url.trim().replace("\\/", "/").replace("&amp;", "&")
        if (u.startsWith("//")) return "https:$u"
        if (u.startsWith("http")) return u
        return try { URL(URL(base), u).toString() } catch (e: Exception) { null }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 2) HomeScreen.kt → secciones Firebase + scraping separadas
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo HomeScreen.kt con secciones separadas..."

cat > "$PKG_DIR/ui/HomeScreen.kt" << 'EOF'
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.EventRepository
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.notifications.EventNotifScheduler
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.rememberPulseAlpha
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.animations.shimmer
import com.anonimus757.tvapp.ui.theme.AppColors

private fun horaAMinutos(hora: String): Int {
    val match = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return Int.MAX_VALUE
    val h = match.groupValues[1].toIntOrNull() ?: return Int.MAX_VALUE
    val m = match.groupValues[2].toIntOrNull() ?: return Int.MAX_VALUE
    if (h !in 0..23 || m !in 0..59) return Int.MAX_VALUE
    return h * 60 + m
}

@Composable
fun HomeScreen(onEventoClick: (Evento, List<Evento>) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val config by RemoteConfigRepository.config.collectAsState()

    var eventosFirebase by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var eventosScraping by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("Conectando...") }

    LaunchedEffect(Unit) {
        try {
            // 1) Firestore primero (rápido, son pocos docs)
            status = "Cargando eventos..."
            eventosFirebase = EventRepository.obtenerEventosFirestore()

            // 2) Scraping después (si está habilitado en config)
            if (config.mostrarScraping) {
                eventosScraping = EventRepository.obtenerEventosScraping { msg -> status = msg }
            }
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargando = false

        // Agendar notifs para todos los eventos (Firebase + scraping)
        try {
            EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping)
        } catch (_: Exception) {}
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
            cargando -> SkeletonHome(status)
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
                eventosFirebase = eventosFirebase,
                eventosScraping = eventosScraping,
                textoBienvenida = config.textoBienvenida,
                mensajeSistema = config.mensajeSistema,
                mostrarScraping = config.mostrarScraping,
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
                    item {
                        Box(Modifier.width(260.dp).height(240.dp).shimmer(RoundedCornerShape(14.dp)))
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun ContenidoHome(
    eventosFirebase: List<Evento>,
    eventosScraping: List<Evento>,
    textoBienvenida: String,
    mensajeSistema: String,
    mostrarScraping: Boolean,
    onEventoClick: (Evento, List<Evento>) -> Unit
) {
    val fbOrdenados = remember(eventosFirebase) {
        eventosFirebase.sortedBy { horaAMinutos(it.hora) }
    }
    val scOrdenados = remember(eventosScraping) {
        eventosScraping.sortedBy { horaAMinutos(it.hora) }
    }

    val gruposFb = remember(fbOrdenados) {
        fbOrdenados.groupBy { it.groupTitle }
    }
    val gruposSc = remember(scOrdenados) {
        scOrdenados.groupBy { it.groupTitle }
    }

    val totalCanales = (fbOrdenados + scOrdenados).sumOf { it.embeds.size }
    val totalEventos = fbOrdenados.size + scOrdenados.size
    val destacado = fbOrdenados.firstOrNull() ?: scOrdenados.firstOrNull()

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp)
    ) {
        // Header
        item(key = "header") {
            HeaderFutTV(textoBienvenida, totalEventos, totalCanales)
        }

        // Banner mensajeSistema
        if (mensajeSistema.isNotBlank()) {
            item(key = "banner") {
                Spacer(Modifier.height(16.dp))
                BannerSistema(mensajeSistema)
            }
        }

        // ── SECCIÓN FIREBASE ──────────────────────────────────
        if (fbOrdenados.isNotEmpty()) {
            item(key = "sep_fb") {
                Spacer(Modifier.height(24.dp))
                SeparadorSeccion(
                    titulo = "🔥 TUS EVENTOS",
                    subtitulo = "${fbOrdenados.size} en vivo · ${fbOrdenados.sumOf { it.embeds.size }} canales",
                    color = AppColors.GoldBright
                )
            }

            if (destacado != null && fbOrdenados.isNotEmpty()) {
                item(key = "hero") {
                    Spacer(Modifier.height(20.dp))
                    HeroEvento(destacado) { onEventoClick(destacado, fbOrdenados) }
                    Spacer(Modifier.height(30.dp))
                }
            }

            gruposFb.forEach { (titulo, lista) ->
                item(key = "fb_header_$titulo") { HeaderCategoria(titulo, lista.size) }
                item(key = "fb_row_$titulo") { FilaEventos(lista, onEventoClick) }
                item(key = "fb_space_$titulo") { Spacer(Modifier.height(24.dp)) }
            }
        }

        // ── SECCIÓN SCRAPING ──────────────────────────────────
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
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 8.dp).fadeInOnLoad(400)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(32.dp).clip(RoundedCornerShape(3.dp)).background(color))
            Spacer(Modifier.width(14.dp))
            Text(
                titulo,
                color = color,
                fontSize = 26.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            subtitulo,
            color = AppColors.TextSecondary,
            fontSize = 13.sp,
            modifier = Modifier.padding(start = 20.dp)
        )
    }
}

@Composable
private fun BannerSistema(mensaje: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
            .fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        AppColors.Gold.copy(alpha = 0.25f),
                        AppColors.Gold.copy(alpha = 0.08f)
                    )
                )
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📢", fontSize = 22.sp)
        Spacer(Modifier.width(14.dp))
        Text(
            mensaje,
            color = AppColors.GoldBright,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 18.sp
        )
    }
}

@Composable
private fun HeaderFutTV(textoBienvenida: String, totalEventos: Int, totalCanales: Int) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp).fadeInOnLoad(durationMs = 400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚽", fontSize = 32.sp)
            Spacer(Modifier.width(10.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = 34.sp,
                fontWeight = FontWeight.Black, letterSpacing = 3.sp)
        }
        Spacer(Modifier.width(20.dp))
        Box(
            Modifier
                .alpha(pulse)
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
            color = AppColors.TextSecondary, fontSize = 13.sp)
    }
}

@Composable
private fun HeroEvento(evento: Evento, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(evento.groupTitle)
    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180), label = "heroBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.4f),
        animationSpec = tween(180), label = "heroBorderColor"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp)
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
                AsyncImage(
                    model = evento.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(110.dp)
                )
            } else {
                Text("⚽", fontSize = 60.sp)
            }
        }
        Spacer(Modifier.width(28.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp)).background(AppColors.Gold)
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text("⭐ DESTACADO", color = Color.Black, fontSize = 11.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
                Spacer(Modifier.width(10.dp))
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.2f))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
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
            Box(
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                    .padding(horizontal = 22.dp, vertical = 12.dp)
            ) {
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
        itemsIndexed(
            items = lista,
            key = { _, it -> "${it.fuente}_${it.hora}_${it.descripcion}" }
        ) { index, ev ->
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

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 3.dp else 1.dp,
        animationSpec = tween(180), label = "cardBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        animationSpec = tween(180), label = "cardBorderColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (focused) AppColors.CardFocus else AppColors.Card,
        animationSpec = tween(180), label = "cardBg"
    )

    Column(
        Modifier
            .width(260.dp)
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
                AsyncImage(
                    model = ev.imagen, contentDescription = null,
                    contentScale = ContentScale.Fit, modifier = Modifier.size(105.dp)
                )
            } else {
                Text("⚽", fontSize = 50.sp)
            }
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
            ev.descripcion, color = AppColors.TextPrimary, fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = 19.sp,
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
                fontSize = 14.sp, fontWeight = FontWeight.Bold
            )
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 3) Verificación final
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando:"
grep -q "obtenerEventosFirestore" "$PKG_DIR/data/EventRepository.kt" && echo "  ✓ EventRepository tiene obtenerEventosFirestore"
grep -q "obtenerEventosScraping" "$PKG_DIR/data/EventRepository.kt" && echo "  ✓ EventRepository tiene obtenerEventosScraping"
grep -q "TUS EVENTOS" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ HomeScreen tiene sección TUS EVENTOS"
grep -q "AGENDAS EXTERNAS" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ HomeScreen tiene sección AGENDAS EXTERNAS"
grep -q "BannerSistema" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ Banner de mensajeSistema"
grep -q "RemoteConfigRepository.config" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ Lee config de Firestore"

echo ""
echo "✅✅✅ Paso 28 completo — Home con Firebase + Agendas separadas"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"