package com.anonimus757.tvapp.data

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

object ApiSportsRepository {

    private const val TAG = "ApiSports"
    private const val BASE = "https://v3.football.api-sports.io"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val cacheFixtures = ConcurrentHashMap<String, Int>()
    private data class CacheLive(val partido: PartidoEnVivo, val timestamp: Long)
    private val cacheLive = ConcurrentHashMap<Int, CacheLive>()
    private const val LIVE_CACHE_MS = 60_000L

    @Volatile private var apiKey: String = ""

    fun setApiKey(key: String) {
        apiKey = key.trim()
        Log.d(TAG, "🔑 API key ${if (apiKey.isEmpty()) "VACÍA" else "configurada (${apiKey.take(6)}...)"}")
    }

    fun tieneApiKey(): Boolean = apiKey.isNotEmpty()

    private fun httpGet(path: String): JSONObject? {
        if (apiKey.isEmpty()) return null
        return try {
            val req = Request.Builder()
                .url("$BASE$path")
                .header("x-apisports-key", apiKey)
                .build()
            client.newCall(req).execute().use { resp ->
                val body = resp.body?.string()
                if (body.isNullOrBlank()) null else JSONObject(body)
            }
        } catch (e: Exception) {
            Log.e(TAG, "httpGet fail: $path → ${e.message}")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // RESOLVER FIXTURE ID
    // ═══════════════════════════════════════════════════════════

    suspend fun resolverFixtureId(
        equipoLocal: String,
        equipoVisitante: String,
        fechaYYYYMMDD: String,
        horaEvento: String = "",
        ligaHint: String = ""
    ): Int? {
        if (equipoLocal.isBlank() || equipoVisitante.isBlank()) return null

        ApiLogs.add("🔍 Buscando: '$equipoLocal' vs '$equipoVisitante'")
        ApiLogs.add("   Fecha: $fechaYYYYMMDD · Hora: $horaEvento · Liga: $ligaHint")

        // Buscar TODOS los partidos del día y filtrar por nombre
        return buscarPorFechaYNombre(
            local = equipoLocal,
            visitante = equipoVisitante,
            fecha = fechaYYYYMMDD,
            horaEvento = horaEvento,
            ligaHint = ligaHint
        )
    }

    private suspend fun buscarPorFechaYNombre(
        local: String,
        visitante: String,
        fecha: String,
        horaEvento: String,
        ligaHint: String
    ): Int? = withContext(Dispatchers.IO) {
        val cacheKey = "match::$fecha::${local.lowercase()}::${visitante.lowercase()}"
        cacheFixtures[cacheKey]?.let { 
            ApiLogs.add("📦 Cache: $it")
            return@withContext it 
        }

        val json = httpGet("/fixtures?date=$fecha") ?: run {
            ApiLogs.add("❌ No pude traer fixtures del $fecha")
            return@withContext null
        }
        val fixtures = json.optJSONArray("response") ?: return@withContext null
        ApiLogs.add("📅 ${fixtures.length()} partidos en la API el $fecha")

        val localNorm = normalizar(local)
        val visitanteNorm = normalizar(visitante)
        val ligaNorm = normalizar(ligaHint)
        val eventoEsEspecial = esCategoriaEspecial("$local $visitante $ligaHint")

        ApiLogs.add("🧪 Normalizado: '$localNorm' vs '$visitanteNorm'")

        var mejorFid: Int? = null
        var mejorScore = 0.0
        var mejorDesc = ""

        for (i in 0 until fixtures.length()) {
            val f = fixtures.optJSONObject(i) ?: continue
            val fixtureObj = f.optJSONObject("fixture") ?: continue
            val fid = fixtureObj.optInt("id", -1)
            if (fid <= 0) continue

            val teams = f.optJSONObject("teams") ?: continue
            val home = teams.optJSONObject("home")?.optString("name", "") ?: continue
            val away = teams.optJSONObject("away")?.optString("name", "") ?: continue

            val leagueObj = f.optJSONObject("league")
            val leagueName = leagueObj?.optString("name", "") ?: ""
            val round = leagueObj?.optString("round", "") ?: ""

            // ─── Filtrar categoría especial ───
            if (!eventoEsEspecial && esCategoriaEspecial("$home $away $leagueName $round")) {
                continue
            }

            val homeNorm = normalizar(home)
            val awayNorm = normalizar(away)

            // Similitud de nombres
            val sLocalHome = similitud(localNorm, homeNorm)
            val sVisitAway = similitud(visitanteNorm, awayNorm)
            val sLocalAway = similitud(localNorm, awayNorm)
            val sVisitHome = similitud(visitanteNorm, homeNorm)

            val normalOK = sLocalHome >= 0.65 && sVisitAway >= 0.65
            val invertOK = sLocalAway >= 0.65 && sVisitHome >= 0.65

            if (!normalOK && !invertOK) continue

            var score = maxOf(
                if (normalOK) sLocalHome + sVisitAway else 0.0,
                if (invertOK) sLocalAway + sVisitHome else 0.0
            )

            // Bonus hora
            val iso = fixtureObj.optString("date", "")
            val minFix = horaDeIso(iso)
            val minEv = horaAMinutos(horaEvento)
            if (minFix != null && minEv != null) {
                val diff1 = Math.abs(minFix - minEv)
                val diff = minOf(diff1, 1440 - diff1)
                when {
                    diff <= 15 -> score += 0.5
                    diff <= 60 -> score += 0.3
                    diff <= 180 -> score += 0.15
                    else -> score -= 0.5
                }
            }

            // Bonus liga
            if (ligaNorm.isNotBlank() && leagueName.isNotBlank()) {
                val simLiga = similitud(ligaNorm, normalizar(leagueName))
                if (simLiga >= 0.5) score += 0.3
            }

            ApiLogs.add("  📌 '$home vs $away' → score ${"%.2f".format(score)}")

            if (score > mejorScore) {
                mejorScore = score
                mejorFid = fid
                mejorDesc = "$home vs $away ($leagueName)"
            }
        }

        if (mejorFid != null && mejorScore >= 1.5) {
            ApiLogs.add("✅ MATCH: '$mejorDesc' → $mejorFid (score ${"%.2f".format(mejorScore)})")
            cacheFixtures[cacheKey] = mejorFid
            mejorFid
        } else {
            ApiLogs.add("❌ SIN MATCH confiable (mejor: ${"%.2f".format(mejorScore)} '$mejorDesc')")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // CATEGORÍA ESPECIAL
    // ═══════════════════════════════════════════════════════════

    private fun esCategoriaEspecial(texto: String): Boolean {
        if (texto.isBlank()) return false
        val t = texto.lowercase()

        // U17, U20, U21, U23, SUB-20, SUB 21, etc.
        if (Regex("\\bu\\s?-?\\s?\\d{2}\\b").containsMatchIn(t)) return true
        if (Regex("\\bsub\\s?-?\\s?\\d{2}\\b").containsMatchIn(t)) return true

        // Palabras específicas
        val palabras = listOf(
            "reserve", "reserves", "reservas",
            "juvenil", "juveniles", "cantera",
            "women", "femenino", "femenil", "wfc",
            "youth", "academy", "academia",
            "primavera"
        )
        return palabras.any { t.contains(it) }
    }

    // ═══════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════

    private fun normalizar(nombre: String): String {
        if (nombre.isBlank()) return ""
        var n = nombre.lowercase()
            .replace("á", "a").replace("é", "e").replace("í", "i")
            .replace("ó", "o").replace("ú", "u").replace("ñ", "n")
            .replace("ü", "u")
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        // Solo removemos sufijos muy genéricos
        val sufijos = setOf("fc", "cf", "sc", "sd", "ad", "cd", "cs", "sa", "srl", "the")
        n = n.split(" ").filter { it.isNotBlank() && it !in sufijos }.joinToString(" ")
        return n.trim()
    }

    private fun similitud(a: String, b: String): Double {
        if (a.isBlank() || b.isBlank()) return 0.0
        if (a == b) return 1.0
        if (a.contains(b) || b.contains(a)) return 0.95

        val tokensA = a.split(" ").filter { it.isNotBlank() }.toSet()
        val tokensB = b.split(" ").filter { it.isNotBlank() }.toSet()
        if (tokensA.isEmpty() || tokensB.isEmpty()) return 0.0

        // Si tienen el token más largo en común, score alto
        val masLargoA = tokensA.maxByOrNull { it.length } ?: ""
        val masLargoB = tokensB.maxByOrNull { it.length } ?: ""
        if (masLargoA.length >= 4 && masLargoA == masLargoB) return 0.9

        val inter = tokensA.intersect(tokensB).size.toDouble()
        val union = tokensA.union(tokensB).size.toDouble()
        return if (union > 0) inter / union else 0.0
    }

    private fun horaAMinutos(hora: String): Int? {
        if (hora.isBlank()) return null
        val match = Regex("(\\d{1,2}):(\\d{2})").find(hora) ?: return null
        val h = match.groupValues[1].toIntOrNull() ?: return null
        val m = match.groupValues[2].toIntOrNull() ?: return null
        if (h !in 0..23 || m !in 0..59) return null
        return h * 60 + m
    }

    private fun horaDeIso(iso: String): Int? {
        if (!iso.contains("T")) return null
        return try {
            val parte = iso.substringAfter("T")
            val h = parte.substringBefore(":").toIntOrNull() ?: return null
            val m = parte.substringAfter(":").substringBefore(":").toIntOrNull() ?: return null
            h * 60 + m
        } catch (e: Exception) { null }
    }

    // ═══════════════════════════════════════════════════════════
    // PARTIDO EN VIVO
    // ═══════════════════════════════════════════════════════════

    suspend fun obtenerPartidoEnVivo(fixtureId: Int, forzarRefresh: Boolean = false): PartidoEnVivo? =
        withContext(Dispatchers.IO) {
            val cached = cacheLive[fixtureId]
            if (!forzarRefresh && cached != null && (System.currentTimeMillis() - cached.timestamp) < LIVE_CACHE_MS) {
                return@withContext cached.partido
            }

            val jsonFixture = httpGet("/fixtures?id=$fixtureId") ?: return@withContext null
            val respFixture = jsonFixture.optJSONArray("response") ?: return@withContext null
            if (respFixture.length() == 0) return@withContext null

            val f = respFixture.optJSONObject(0) ?: return@withContext null
            val fixtureObj = f.optJSONObject("fixture") ?: return@withContext null
            val statusObj = fixtureObj.optJSONObject("status") ?: JSONObject()
            val teamsObj = f.optJSONObject("teams") ?: JSONObject()
            val goalsObj = f.optJSONObject("goals") ?: JSONObject()

            val eventos = obtenerEventosPartido(fixtureId)
            val stats = obtenerEstadisticasPartido(fixtureId)

            val partido = PartidoEnVivo(
                fixtureId = fixtureId,
                localNombre = teamsObj.optJSONObject("home")?.optString("name", "") ?: "",
                localLogo = teamsObj.optJSONObject("home")?.optString("logo", "") ?: "",
                visitanteNombre = teamsObj.optJSONObject("away")?.optString("name", "") ?: "",
                visitanteLogo = teamsObj.optJSONObject("away")?.optString("logo", "") ?: "",
                golesLocal = goalsObj.optInt("home", 0),
                golesVisitante = goalsObj.optInt("away", 0),
                minuto = statusObj.optInt("elapsed", 0),
                estado = statusObj.optString("long", ""),
                estadoCorto = statusObj.optString("short", "NS"),
                eventos = eventos,
                estadisticas = stats
            )

            cacheLive[fixtureId] = CacheLive(partido, System.currentTimeMillis())
            partido
        }

    private fun obtenerEventosPartido(fixtureId: Int): List<EventoPartido> {
        val json = httpGet("/fixtures/events?fixture=$fixtureId") ?: return emptyList()
        val arr = json.optJSONArray("response") ?: return emptyList()
        val lista = mutableListOf<EventoPartido>()
        for (i in 0 until arr.length()) {
            val e = arr.optJSONObject(i) ?: continue
            val minuto = e.optJSONObject("time")?.optInt("elapsed", 0) ?: 0
            val tipo = e.optString("type", "")
            val detalle = e.optString("detail", "")

            val equipoRaw = e.optJSONObject("team")?.optString("name", "") ?: ""
            val jugadorRaw = e.optJSONObject("player")?.optString("name", "") ?: ""
            val equipo = limpiarNull(equipoRaw)
            val jugador = limpiarNull(jugadorRaw)

            lista.add(EventoPartido(minuto, tipo, detalle, equipo, jugador))
        }
        return lista
    }

    private fun limpiarNull(s: String): String {
        if (s.isBlank()) return ""
        if (s.equals("null", ignoreCase = true)) return ""
        return s
    }

    private fun obtenerEstadisticasPartido(fixtureId: Int): EstadisticasPartido? {
        val json = httpGet("/fixtures/statistics?fixture=$fixtureId") ?: return null
        val arr = json.optJSONArray("response") ?: return null
        if (arr.length() < 2) return null

        fun parseStats(idx: Int): Map<String, String> {
            val team = arr.optJSONObject(idx) ?: return emptyMap()
            val stats = team.optJSONArray("statistics") ?: return emptyMap()
            val map = mutableMapOf<String, String>()
            for (i in 0 until stats.length()) {
                val s = stats.optJSONObject(i) ?: continue
                map[s.optString("type")] = s.opt("value")?.toString() ?: "0"
            }
            return map
        }

        val local = parseStats(0)
        val visitante = parseStats(1)

        fun intDe(m: Map<String, String>, k: String): Int =
            m[k]?.replace("%", "")?.toIntOrNull() ?: 0

        return EstadisticasPartido(
            posesionLocal = intDe(local, "Ball Possession"),
            posesionVisitante = intDe(visitante, "Ball Possession"),
            cornersLocal = intDe(local, "Corner Kicks"),
            cornersVisitante = intDe(visitante, "Corner Kicks"),
            tirosLocal = intDe(local, "Total Shots"),
            tirosVisitante = intDe(visitante, "Total Shots")
        )
    }
}

data class PartidoEnVivo(
    val fixtureId: Int,
    val localNombre: String,
    val localLogo: String,
    val visitanteNombre: String,
    val visitanteLogo: String,
    val golesLocal: Int,
    val golesVisitante: Int,
    val minuto: Int,
    val estado: String,
    val estadoCorto: String,
    val eventos: List<EventoPartido>,
    val estadisticas: EstadisticasPartido?
) {
    val enVivo: Boolean get() = estadoCorto in listOf("1H", "HT", "2H", "ET", "BT", "P", "LIVE")
    val terminado: Boolean get() = estadoCorto in listOf("FT", "AET", "PEN")
    val noEmpezado: Boolean get() = estadoCorto in listOf("NS", "TBD")
}

data class EventoPartido(
    val minuto: Int,
    val tipo: String,
    val detalle: String,
    val equipo: String,
    val jugador: String
)

data class EstadisticasPartido(
    val posesionLocal: Int,
    val posesionVisitante: Int,
    val cornersLocal: Int,
    val cornersVisitante: Int,
    val tirosLocal: Int,
    val tirosVisitante: Int
)
