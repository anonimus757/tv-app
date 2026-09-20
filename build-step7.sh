#!/bin/bash
set -e

echo "📁 Paso 7: Lista de eventos real..."
mkdir -p app/src/main/java/com/anonimus757/tvapp/data
mkdir -p app/src/main/java/com/anonimus757/tvapp/ui

# ========== Models.kt ==========
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
KTEOF

# ========== Fuentes.kt ==========
cat > app/src/main/java/com/anonimus757/tvapp/data/Fuentes.kt << 'KTEOF'
package com.anonimus757.tvapp.data

val FUENTES = listOf(
    Fuente(
        id = "futbollibre",
        nombre = "Futbollibre",
        groupTitle = "EVENTOS 🗒️",
        base = "https://futbollibrevip.pe",
        agenda = "https://futbollibrevip.pe/agenda-data.php",
        imgBase = "https://img.futbollibrehd.com.pe",
        imgDefault = "https://img.futbollibrehd.com.pe/uploads/sin_imagen_d36205f0e8.png",
        flagsBase = null,
        tipo = "json"
    ),
    Fuente(
        id = "pelotalibrehd",
        nombre = "Pelota Libre HD",
        groupTitle = "EVENTOS 2 🗒️",
        base = "https://pelotalibrehd.cl",
        agenda = "https://pelotalibrehd.cl/agenda-data.php",
        imgBase = "https://img.futbollibrehd.com.pe",
        imgDefault = "https://img.futbollibrehd.com.pe/uploads/sin_imagen_d36205f0e8.png",
        flagsBase = null,
        tipo = "json"
    ),
    Fuente(
        id = "pelotalibretv2",
        nombre = "Pelota Libre TV2",
        groupTitle = "EVENTOS 3 🗒️",
        base = "https://pelotalibretv2.online",
        agenda = "https://pelotalibretv2.online/eventos.js",
        imgBase = "",
        imgDefault = "https://pelotalibretv2.online/img/favi.jpg",
        flagsBase = "https://pelotalibretv2.online/flags/",
        tipo = "js"
    ),
)

val MAPA_LOGOS = mapOf(
    "TUR" to "tr.webp", "ENG" to "en.webp", "ALE" to "de.webp", "FRA" to "fr.webp",
    "HOL" to "nl.webp", "POR" to "pt.webp", "MEX" to "mx.png", "ES" to "es.png",
    "IT" to "it.png", "BEL" to "be.webp", "COSTARICA" to "cr.webp", "ESC" to "sx.webp",
    "BOL" to "bo.png", "USA" to "us.png", "FUT" to "international.webp",
    "COL" to "co.webp", "ATP" to "atp.webp", "PARAG" to "py.webp", "AR" to "ar.webp",
    "PE" to "pe.webp", "PY" to "py.webp", "RUGBY" to "rugby-union.webp",
    "URU" to "uru.webp", "BRA" to "br.webp", "VEN" to "ven.webp", "ARA" to "ara.webp",
    "CH" to "ch.webp", "CHA" to "chaa.png", "ECUA" to "ec.webp",
    "MOTOGP" to "motogp.webp", "MOTO2" to "moto2.webp", "MOTO3" to "moto3.webp",
    "INDYCAR" to "indycar.webp", "WTA" to "wta.webp", "GRE" to "gr.png",
    "GOLF" to "golf.svg", "UCI" to "uci.png", "PADEL" to "padel.jpg",
    "HN" to "hn.png", "GT" to "gt.png", "NHL" to "nhl.png", "NBA" to "nba.png",
    "VNL" to "vnl.png", "WWE" to "wwe.png", "BOX" to "BOXEO.png",
    "AFCCUP" to "afccup.png", "AFCCHA" to "afccha.png",
    "KINGSLEAGUE" to "kingsleague.png", "EUROLEAGUEBASKET" to "euroleaguebasket.png",
    "LMB" to "lmb.png", "HANDBALL" to "handball.png", "ENDESA" to "endesa.png",
    "NBB" to "NBB.png", "UFC" to "UFC.png", "NFL" to "nfl.png",
    "UEFA_NATIONS" to "nationsleague.png", "EURO_COPA" to "eurocopa.png",
    "COPA_AMERICA" to "//futbol-libre-hd.com/flags/copa_america.png",
    "AEW" to "aewusa.jpg", "AFR" to "afr.png", "FIFA" to "fifa.webp",
    "COSQUIN" to "cosquin.png", "PREOLIMPICO" to "preolimpico.png",
    "LIB" to "lib.png", "UYL" to "uyl.png", "LCC" to "concachampions.png",
    "CONCACAF-F" to "concacaf-f.png", "SERIECARIBE" to "seriecaribe.png",
    "CICLISMO" to "ciclismo.png", "CAF" to "cafa.png", "NCAA" to "ncaa.webp",
    "UCL" to "conferecen.png", "UE" to "uelogo.png", "MFP" to "MFP.png",
    "GOLDCUP" to "COPAOROM.png", "RECOPA-SUD" to "sud.png",
    "FIBAAMERICA" to "fiba.png", "EUROBASKET" to "eurocopabaske.png",
    "OLIMPICOS" to "olimpicos2.png", "ELIMINATORIAS_CONMEBOL" to "sudamerica.png",
    "MLB" to "mlb.png", "NCAAMARCH" to "ncaamarchusa.png", "SUD" to "sud.png",
    "BASKET" to "basket.png", "MUNDIALCLUBES" to "mundialclubes2025.png",
    "F2" to "f2.png", "F3" to "f3.png", "F1" to "f1.png",
    "LEAGUESCUP" to "leaguescup.png", "OSCARS" to "oscars.png",
    "CONCACAFLIGAD" to "concachampions.png",
    "EUROELIMINATORIAS" to "eliminatoriaseuro.png", "MMA" to "mma.png",
    "WNBA" to "wnba1.webp", "UEFA_SUPERCOPA" to "uefasupercopa.png"
)
KTEOF

# ========== EventRepository.kt ==========
cat > app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt << 'KTEOF'
package com.anonimus757.tvapp.data

import kotlinx.coroutines.Dispatchers
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

    suspend fun obtenerTodosLosEventos(onProgreso: (String) -> Unit = {}): List<Evento> =
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
                    e.printStackTrace()
                }
            }
            resultado
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
KTEOF

# ========== HomeScreen.kt ==========
cat > app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt << 'KTEOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
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
private val ACENTO = Color(0xFF38BDF8)
private val TEXTO = Color(0xFFE2E8F0)
private val GRIS = Color(0xFF94A3B8)

@Composable
fun HomeScreen() {
    var eventos by remember { mutableStateOf<List<Evento>>(emptyList()) }
    var cargando by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("Cargando eventos...") }

    LaunchedEffect(Unit) {
        try {
            eventos = EventRepository.obtenerTodosLosEventos { msg ->
                status = msg
            }
        } catch (e: Exception) {
            status = "Error: ${e.message}"
        }
        cargando = false
    }

    Box(
        Modifier.fillMaxSize().background(BG)
    ) {
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
                        EventoCard(ev)
                    }
                }
            }
        }
    }
}

@Composable
private fun EventoCard(ev: Evento) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(CARD)
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

# ========== MainActivity.kt (actualizar) ==========
cat > app/src/main/java/com/anonimus757/tvapp/MainActivity.kt << 'KTEOF'
package com.anonimus757.tvapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.anonimus757.tvapp.ui.HomeScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            HomeScreen()
        }
    }
}
KTEOF

echo ""
echo "✅✅✅ Paso 7 completo"
find app/src/main/java -type f