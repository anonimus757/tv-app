#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.fuzzypro.$(date +%s)"
echo "✅ Backup: ${API}.bak.fuzzypro.$(date +%s)"

cat > "$API" << 'KOTLIN_EOF'
package com.anonimus757.tvapp.data

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Cliente para api-sports.io (api-football v3).
 * Con fuzzy matching inteligente que filtra por fecha, hora, liga y categoría.
 */
object ApiSportsRepository {

    private const val TAG = "ApiSports"
    private const val BASE = "https://v3.football.api-sports.io"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val cacheEquipos = ConcurrentHashMap<String, Int>()
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
    // API PUBLICA
    // ═══════════════════════════════════════════════════════════

    /**
     * Resuelve el fixtureId a partir del evento.
     * 1. Si ya tiene fixtureId → lo usa directo
     * 2. Si no, intenta buscar por equipos+fecha+hora+liga
     */
    suspend fun resolverFixtureId(
        equipoLocal: String,
        equipoVisitante: String,
        fechaYYYYMMDD: String,
        horaEvento: String = "",
        ligaHint: String = ""
    ): Int? {
        if (equipoLocal.isBlank() || equipoVisitante.isBlank()) return null

        DebugLog.log("🔍 Buscando '$equipoLocal' vs '$equipoVisitante' · $fechaYYYYMMDD · $horaEvento")

        // 1. Búsqueda exacta por equipos
        val idLocal = buscarEquipoId(equipoLocal)
        val idVisitante = buscarEquipoId(equipoVisitante)
        if (idLocal != null && idVisitante != null) {
            val fid = buscarFixtureId(idLocal, idVisitante, fechaYYYYMMDD)
            if (fid != null) {
                DebugLog.log("✅ Encontrado por búsqueda exacta: $fid")
                return fid
            }
        }

        // 2. Fuzzy inteligente
        DebugLog.log("🔍 Búsqueda exacta sin resultado, probando fuzzy inteligente...")
        return buscarFixtureInteligente(
            local = equipoLocal,
            visitante = equipoVisitante,
            fecha = fechaYYYYMMDD,
            horaEvento = horaEvento,
            ligaHint = ligaHint
        )
    }

    suspend fun buscarEquipoId(nombre: String): Int? = withContext(Dispatchers.IO) {
        if (nombre.isBlank()) return@withContext null
        val key = nombre.lowercase().trim()
        cacheEquipos[key]?.let { return@withContext it }

        val json = httpGet("/teams?search=${java.net.URLEncoder.encode(nombre, "UTF-8")}")
            ?: return@withContext null
        val resultados = json.optJSONArray("response") ?: return@withContext null
        if (resultados.length() == 0) return@withContext null

        val team = resultados.optJSONObject(0)?.optJSONObject("team") ?: return@withContext null
        val id = team.optInt("id", -1)
        if (id > 0) {
            cacheEquipos[key] = id
            id
        } else null
    }

    suspend fun buscarFixtureId(
        equipoLocalId: Int,
        equipoVisitanteId: Int,
        fechaYYYYMMDD: String
    ): Int? = withContext(Dispatchers.IO) {
        val cacheKey = "$equipoLocalId-$equipoVisitanteId-$fechaYYYYMMDD"
        cacheFixtures[cacheKey]?.let { return@withContext it }

        val json = httpGet("/fixtures?team=$equipoLocalId&date=$fechaYYYYMMDD")
            ?: return@withContext null
        val fixtures = json.optJSONArray("response") ?: return@withContext null

        for (i in 0 until fixtures.length()) {
            val f = fixtures.optJSONObject(i) ?: continue
            val teams = f.optJSONObject("teams") ?: continue
            val awayId = teams.optJSONObject("away")?.optInt("id", -1) ?: continue
            val homeId = teams.optJSONObject("home")?.optInt("id", -1) ?: continue

            if (awayId == equipoVisitanteId || homeId == equipoVisitanteId) {
                val fixtureId = f.optJSONObject("fixture")?.optInt("id", -1) ?: continue
                if (fixtureId > 0) {
                    cacheFixtures[cacheKey] = fixtureId
                    return@withContext fixtureId
                }
            }
        }
        null
    }

    // ═══════════════════════════════════════════════════════════
    // FUZZY MATCHING INTELIGENTE
    // ═══════════════════════════════════════════════════════════

    private suspend fun buscarFixtureInteligente(
        local: String,
        visitante: String,
        fecha: String,
        horaEvento: String,
        ligaHint: String
    ): Int? = withContext(Dispatchers.IO) {
        val json = httpGet("/fixtures?date=$fecha") ?: return@withContext null
        val fixtures = json.optJSONArray("response") ?: return@withContext null
        Log.d(TAG, "📊 ${fixtures.length()} partidos el $fecha")

        val localNorm = normalizarTexto(local)
        val visitanteNorm = normalizarTexto(visitante)
        val ligaNorm = normalizarTexto(ligaHint)
        val minEvento = horaAMinutos(horaEvento)

        val eventoMencionaEspecial = mencionaCategoriaEspecial("$local $visitante $ligaHint")

        DebugLog.log("🧠 Fuzzy: '$localNorm' vs '$visitanteNorm' · hora=$horaEvento")

        var mejorMatch: Int? = null
        var mejorScore = 0.0
        var mejorDesc = ""

        for (i in 0 until fixtures.length()) {
            val f = fixtures.optJSONObject(i) ?: continue
            val fixtureObj = f.optJSONObject("fixture") ?: continue
            val fixtureId = fixtureObj.optInt("id", -1)
            if (fixtureId <= 0) continue

            val teams = f.optJSONObject("teams") ?: continue
            val homeName = teams.optJSONObject("home")?.optString("name", "") ?: continue
            val awayName = teams.optJSONObject("away")?.optString("name", "") ?: continue

            val leagueObj = f.optJSONObject("league") ?: JSONObject()
            val leagueName = leagueObj.optString("name", "")
            val leagueRound = leagueObj.optString("round", "")

            // ─── FILTRO 1: Categoría especial (U20, reservas, etc.) ───
            val textoPartido = "$homeName $awayName $leagueName $leagueRound"
            if (!eventoMencionaEspecial && mencionaCategoriaEspecial(textoPartido)) {
                continue
            }

            // ─── Score de nombres ───
            val homeNorm = normalizarTexto(homeName)
            val awayNorm = normalizarTexto(awayName)

            val sLocalHome = similitud(localNorm, homeNorm)
            val sVisitAway = similitud(visitanteNorm, awayNorm)
            val sLocalAway = similitud(localNorm, awayNorm)
            val sVisitHome = similitud(visitanteNorm, homeNorm)

            val normalValido = sLocalHome >= 0.5 && sVisitAway >= 0.5
            val invertidoValido = sLocalAway >= 0.5 && sVisitHome >= 0.5
            if (!normalValido && !invertidoValido) continue

            var score = maxOf(
                if (normalValido) sLocalHome + sVisitAway else 0.0,
                if (invertidoValido) sLocalAway + sVisitHome else 0.0
            )

            // ─── BONUS: liga parecida ───
            if (ligaNorm.isNotBlank() && leagueName.isNotBlank()) {
                val simLiga = similitud(ligaNorm, normalizarTexto(leagueName))
                if (simLiga >= 0.5) score += 0.4
            }

            // ─── BONUS: hora cercana ───
            if (minEvento != null) {
                val isoDate = fixtureObj.optString("date", "")
                val minFixture = horaDeIsoUtc(isoDate)
                if (minFixture != null) {
                    val diff = Math.abs(minFixture - minEvento)
                    val diffCircular = minOf(diff, 1440 - diff)
                    when {
                        diffCircular <= 15 -> score += 0.5    // muy cerca
                        diffCircular <= 60 -> score += 0.3    // ±1 hora
                        diffCircular <= 180 -> score += 0.15  // ±3 horas (timezones)
                        else -> score -= 0.3                   // muy lejos → penalizar
                    }
                }
            }

            if (score > mejorScore) {
                mejorScore = score
                mejorMatch = fixtureId
                mejorDesc = "$homeName vs $awayName ($leagueName)"
            }
        }

        DebugLog.log("🧠 Mejor: '$mejorDesc' score=${"%.2f".format(mejorScore)}")

        if (mejorScore >= 1.5 && mejorMatch != null) {
            DebugLog.log("✅ Match OK: $mejorMatch")
            mejorMatch
        } else {
            DebugLog.log("❌ Sin match confiable (score ${"%.2f".format(mejorScore)} < 1.5)")
            null
        }
    }

    /**
     * Detecta si un texto menciona categoría especial (sub-20, reservas, etc.)
     */
    private fun mencionaCategoriaEspecial(texto: String): Boolean {
        val t = texto.lowercase()
        val palabras = listOf(
            "sub-20", "sub 20", "sub20", "u20", "u-20",
            "sub-17", "sub 17", "sub17", "u17", "u-17",
            "sub-23", "sub 23", "sub23", "u23", "u-23",
            "sub-19", "sub 19", "sub19", "u19",
            "reserve", "reserves", "reservas",
            "juvenil", "juveniles", "cantera",
            "women", "femenino", "femenil", "wfc",
            "youth", "academy", "academia",
            " ii", " b\"", " ii\"",       // equipos B/II
            "primavera", "primavera"
        )
        return palabras.any { t.contains(it) }
    }

    // ═══════════════════════════════════════════════════════════
    // HELPERS DE TEXTO
    // ═══════════════════════════════════════════════════════════

    private fun normalizarTexto(nombre: String): String {
        if (nombre.isBlank()) return ""
        var n = nombre.lowercase()
            .replace("á", "a").replace("é", "e").replace("í", "i")
            .replace("ó", "o").replace("ú", "u").replace("ñ", "n")
            .replace("ü", "u")
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        val sufijos = setOf("fc", "cf", "sc", "sd", "ad", "cd", "cs", "the", "sa", "srl")
        n = n.split(" ").filter { it.isNotBlank() && it !in sufijos }.joinToString(" ")
        return n.trim()
    }

    private fun similitud(a: String, b: String): Double {
        if (a.isBlank() || b.isBlank()) return 0.0
        if (a == b) return 1.0
        if (a.contains(b) || b.contains(a)) return 0.9

        val tokensA = a.split(" ").filter { it.isNotBlank() }.toSet()
        val tokensB = b.split(" ").filter { it.isNotBlank() }.toSet()
        if (tokensA.isEmpty() || tokensB.isEmpty()) return 0.0

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

    /**
     * Extrae la hora del string ISO: "2026-09-20T20:40:00+00:00"
     * Devuelve minutos desde medianoche en UTC.
     */
    private fun horaDeIso(iso: String): Int? {
        if (!iso.contains("T")) return null
        return try {
            val hora = iso.substringAfter("T").substringBefore(":")
            val min = iso.substringAfter("T").substringAfter(":").substringBefore(":")
            val h = hora.toIntOrNull() ?: return null
            val m = min.toIntOrNull() ?: return null
            h * 60 + m
        } catch (e: Exception) { null }
    }

    private fun horaDeIsoUtc(iso: String): Int? {
        // La API devuelve UTC. Devolvemos hora UTC en minutos.
        return horaDeIso(iso)
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
            val equipo = e.optJSONObject("team")?.optString("name", "") ?: ""
            val jugador = e.optJSONObject("player")?.optString("name", "") ?: ""
            lista.add(EventoPartido(minuto, tipo, detalle, equipo, jugador))
        }
        return lista
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

// ═══════════════════════════════════════════════════════════
// MODELOS
// ═══════════════════════════════════════════════════════════
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
KOTLIN_EOF

echo "✅ ApiSportsRepository.kt reescrito con fuzzy inteligente"

# ═══════════════════════════════════════════════════════════
# Actualizar la llamada en EventDetailScreen para pasar hora + liga
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
if [ -f "$DETAIL" ]; then
    cp "$DETAIL" "${DETAIL}.bak.fuzzypro.$(date +%s)"
    python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

viejo = '''            val fid = evento.fixtureId ?: ApiSportsRepository.resolverFixtureId(
                evento.equipoLocal, evento.equipoVisitante, evento.fecha
            )'''

nuevo = '''            val fid = evento.fixtureId ?: ApiSportsRepository.resolverFixtureId(
                equipoLocal = evento.equipoLocal,
                equipoVisitante = evento.equipoVisitante,
                fechaYYYYMMDD = evento.fecha,
                horaEvento = evento.hora,
                ligaHint = evento.liga
            )'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ EventDetailScreen actualizado para pasar hora+liga")
else:
    print("⚠️ No matcheó la llamada. Revisá manual.")
PYEOF
fi

echo ""
echo "✅✅✅ Fuzzy inteligente listo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
