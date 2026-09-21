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
    // FIRESTORE
    // ═══════════════════════════════════════════════════════════

    suspend fun obtenerEventosFirestore(): List<Evento> = withContext(Dispatchers.IO) {
        try {
            val db = FirebaseFirestore.getInstance()
            DebugLog.log("🔍 Consultando Firestore...")

            // Traer TODOS los docs sin filtro para poder diagnosticar
            val snap = db.collection("eventos").get().await()
            val totalDocs = snap.size()
            DebugLog.log("📊 Docs en 'eventos': $totalDocs")

            // Log del primer doc para ver estructura real
            snap.documents.firstOrNull()?.let { doc ->
                val keys = doc.data?.keys?.joinToString(", ") ?: "(sin data)"
                DebugLog.log("📄 Campos: $keys")
                val activo = doc.get("activo")
                DebugLog.log("🔎 activo=$activo (${activo?.javaClass?.simpleName})")
                val embedsVal = doc.get("embeds")
                DebugLog.log("🔎 embeds tipo: ${embedsVal?.javaClass?.simpleName}")
            }

            // Filtro: activo==true o activo==null (tolerante)
            val filtrados = snap.documents.filter { doc ->
                val activo = doc.get("activo")
                activo == null || activo == true
            }
            DebugLog.log("✅ Post-filtro activo: ${filtrados.size}")

            val lista = filtrados.mapNotNull { doc ->
                val ev = parsearEventoFirestore(doc)
                if (ev == null) DebugLog.log("⚠️ Doc descartado: ${doc.getString("descripcion")}")
                ev
            }

            val conFixture = lista.count { it.fixtureId != null }
            DebugLog.log("✅ Firestore eventos OK: ${lista.size} (con fixtureId: $conFixture)")
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos ($totalDocs docs)")
            lista
        } catch (e: Exception) {
            DebugLog.log("❌ Firestore fail: ${e.message}")
            Log.e(TAG, "❌ Firestore fail: ${e.message}", e)
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

            // Fecha obligatoria para eventos de Firebase.
            // Si no existe o está vacía → descartamos el evento.
            val fecha = doc.getString("fecha")?.trim() ?: ""
            if (fecha.isEmpty()) {
                DebugLog.log("⚠️ '${descripcion}' sin fecha → descartado")
                return null
            }

            // Campos API-Sports: primero Firestore, si no → parsear de la descripción
            var equipoLocal = doc.getString("equipo_local")?.trim() ?: ""
            var equipoVisitante = doc.getString("equipo_visitante")?.trim() ?: ""
            if (equipoLocal.isBlank() || equipoVisitante.isBlank()) {
                val parsed = parsearEquiposDeDescripcion(descripcion)
                if (equipoLocal.isBlank()) equipoLocal = parsed.first
                if (equipoVisitante.isBlank()) equipoVisitante = parsed.second
            }
            val liga = doc.getString("liga")?.trim()?.takeIf { it.isNotBlank() } ?: categoria
            val fixtureId = doc.getLong("fixture_id")?.toInt()
            // Duración automática: 150 minutos (2h 30min) para todos los eventos
            val duracionMinutos = 150
            val videoFinalizado = doc.getString("video_finalizado")?.trim() ?: ""
            val videoProximo = doc.getString("video_proximo")?.trim() ?: ""

            // Tolerante: acepta array de maps O un solo map
            val embedsRawAny = doc.get("embeds")
            val embedsList: List<Map<String, Any?>> = when (embedsRawAny) {
                is List<*> -> embedsRawAny.mapNotNull { it as? Map<String, Any?> }
                is Map<*, *> -> listOf(embedsRawAny as Map<String, Any?>)
                else -> emptyList()
            }

            val embeds = embedsList.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                val logo = (m["logo"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim(), logo.trim())
            }

            if (embeds.isEmpty()) return null

            Evento(
                fuente = fuente,
                groupTitle = categoria,
                descripcion = descripcion,
                hora = hora,
                imagen = imagen,
                embeds = embeds,
                fecha = fecha,
                equipoLocal = equipoLocal,
                equipoVisitante = equipoVisitante,
                liga = liga,
                fixtureId = fixtureId,
                duracionMinutos = duracionMinutos,
                videoFinalizado = videoFinalizado,
                videoProximo = videoProximo
            )
        } catch (e: Exception) {
            Log.e(TAG, "parsear fail: ${e.message}")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // SCRAPING
    // ═══════════════════════════════════════════════════════════

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
            DebugLog.log("✅ Scraping: ${resultado.size} eventos")
            resultado
        }

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
                eventos.add(Evento(fuente.nombre, fuente.groupTitle, desc, hora, img, embeds, FechaHelper.hoy()))
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
                eventos.add(Evento(fuente.nombre, fuente.groupTitle, titulo, hora, img, embeds, FechaHelper.hoy()))
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

    /**
     * Parsea equipos desde la descripción tipo "AUCAS vs MACARA" o "Boca vs River".
     * Devuelve Pair(local, visitante). Si no puede parsear, devuelve ("", "").
     */
    private fun parsearEquiposDeDescripcion(desc: String): Pair<String, String> {
        return try {
            val regex = Regex("""\s+(?:vs\.?|v\.?|-)\s+""", RegexOption.IGNORE_CASE)
            val partes = desc.split(regex).map { it.trim() }.filter { it.isNotBlank() }
            if (partes.size >= 2) Pair(partes[0], partes[1]) else Pair("", "")
        } catch (e: Exception) {
            Pair("", "")
        }
    }

}
