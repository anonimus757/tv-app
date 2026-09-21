#!/bin/bash
set -e

echo "🔧 Aplicando backend para API-Sports..."

# ═══════════════════════════════════════════════════════════
# 1. BACKUPS
# ═══════════════════════════════════════════════════════════
for f in \
  "app/src/main/java/com/anonimus757/tvapp/data/Models.kt" \
  "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt" \
  "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"; do
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak.$(date +%s)"
    echo "✅ Backup: $f"
  else
    echo "⚠️ No existe: $f (se creará o saltará)"
  fi
done

# ═══════════════════════════════════════════════════════════
# 2. MODELS.KT: agregar campos nuevos a Evento
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
import re
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

viejo = '''data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "" // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY
)'''

nuevo = '''data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "", // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY

    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null
)'''

if viejo not in c:
    print("❌ Models.kt: no encontré el data class Evento exacto.")
    raise SystemExit(1)
c = c.replace(viejo, nuevo, 1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ Models.kt: Evento extendido con equipoLocal, equipoVisitante, liga, fixtureId")
PYEOF

# ═══════════════════════════════════════════════════════════
# 3. EVENTREPOSITORY.KT: parsear los nuevos campos
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# 3a. Agregar lectura de los campos nuevos
viejo_parse = '''            val fecha = doc.getString("fecha")?.trim() ?: ""
            if (fecha.isEmpty()) {
                DebugLog.log("⚠️ '${descripcion}' sin fecha → descartado")
                return null
            }'''

nuevo_parse = '''            val fecha = doc.getString("fecha")?.trim() ?: ""
            if (fecha.isEmpty()) {
                DebugLog.log("⚠️ '${descripcion}' sin fecha → descartado")
                return null
            }

            // Campos API-Sports (opcionales)
            val equipoLocal = doc.getString("equipo_local")?.trim() ?: ""
            val equipoVisitante = doc.getString("equipo_visitante")?.trim() ?: ""
            val liga = doc.getString("liga")?.trim() ?: ""
            val fixtureId = doc.getLong("fixture_id")?.toInt()'''

if viejo_parse not in c:
    print("❌ EventRepository.kt: no encontré el bloque de lectura de fecha.")
    raise SystemExit(1)
c = c.replace(viejo_parse, nuevo_parse, 1)

# 3b. Pasar los campos al constructor de Evento
viejo_evento = '''            Evento(
                fuente = fuente,
                groupTitle = categoria,
                descripcion = descripcion,
                hora = hora,
                imagen = imagen,
                embeds = embeds,
                fecha = fecha
            )'''

nuevo_evento = '''            Evento(
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
                fixtureId = fixtureId
            )'''

if viejo_evento not in c:
    print("❌ EventRepository.kt: no encontré el constructor de Evento.")
    raise SystemExit(1)
c = c.replace(viejo_evento, nuevo_evento, 1)

# 3c. Log de cuántos eventos tienen fixtureId
viejo_log = '''            DebugLog.log("✅ Firestore eventos OK: ${lista.size}")'''
nuevo_log = '''            val conFixture = lista.count { it.fixtureId != null }
            DebugLog.log("✅ Firestore eventos OK: ${lista.size} (con fixtureId: $conFixture)")'''
c = c.replace(viejo_log, nuevo_log, 1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ EventRepository.kt: parseo de equipoLocal, equipoVisitante, liga, fixtureId")
PYEOF

# ═══════════════════════════════════════════════════════════
# 4. REMOTECONFIG: agregar apiSportsKey al data class
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
import re
fp = "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Buscar el data class RemoteConfig y agregar campo antes del cierre
# Patrón: data class RemoteConfig( ... ) con cualquier contenido
m = re.search(r'(data\s+class\s+RemoteConfig\s*\([^)]*)(\)\s*(?:/\*.*?\*/)?\s*$)', c, re.MULTILINE | re.DOTALL)
if not m:
    print("⚠️ No encontré data class RemoteConfig. Puede llamarse distinto.")
    print("   Agregá manualmente: val apiSportsKey: String = \"\"")
else:
    cuerpo = m.group(1)
    cierre = m.group(2)
    # Detectar si ya tiene el campo
    if "apiSportsKey" in cuerpo:
        print("ℹ️ RemoteConfig ya tiene apiSportsKey")
    else:
        # Agregar antes del cierre, cuidando la coma
        cuerpo_strip = cuerpo.rstrip()
        if not cuerpo_strip.endswith(","):
            cuerpo_strip += ","
        nuevo_cuerpo = cuerpo_strip + "\n    val apiSportsKey: String = \"\" // API-Sports key (leer desde Firestore config/app)"
        c = c.replace(cuerpo, nuevo_cuerpo, 1)
        print("✅ RemoteConfigRepository.kt: agregado campo apiSportsKey")

        with open(fp, 'w', encoding='utf-8') as f:
            f.write(c)
PYEOF

# ═══════════════════════════════════════════════════════════
# 5. CREAR ApiSportsRepository.kt
# ═══════════════════════════════════════════════════════════
mkdir -p app/src/main/java/com/anonimus757/tvapp/data

cat > app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt << 'KOTLIN_EOF'
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
 *
 * Flujo para obtener datos en vivo:
 *   1. buscarEquipoId("Boca") → 451
 *   2. buscarFixtureId(451, 435, "2026-09-20") → 123456
 *   3. obtenerPartidoEnVivo(123456) → PartidoEnVivo con marcador, eventos y stats
 *
 * Tiene caché en memoria para no repetir llamadas:
 *   - Equipos: caché permanente (los IDs no cambian)
 *   - Fixture IDs: caché por (equipoLocalId + equipoVisitanteId + fecha)
 *   - Partido en vivo: caché de 60 segundos
 */
object ApiSportsRepository {

    private const val TAG = "ApiSports"
    private const val BASE = "https://v3.football.api-sports.io"

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    // ═══ Caché en memoria ═══
    private val cacheEquipos = ConcurrentHashMap<String, Int>()
    private val cacheFixtures = ConcurrentHashMap<String, Int>()
    private data class CacheLive(val partido: PartidoEnVivo, val timestamp: Long)
    private val cacheLive = ConcurrentHashMap<Int, CacheLive>()
    private const val LIVE_CACHE_MS = 60_000L

    // ═══════════════════════════════════════════════════════════
    // API KEY (se setea desde RemoteConfig al inicio)
    // ═══════════════════════════════════════════════════════════
    @Volatile private var apiKey: String = ""

    fun setApiKey(key: String) {
        apiKey = key.trim()
        Log.d(TAG, "🔑 API key ${if (apiKey.isEmpty()) "VACÍA" else "configurada (${apiKey.take(6)}...)"}")
    }

    fun tieneApiKey(): Boolean = apiKey.isNotEmpty()

    // ═══════════════════════════════════════════════════════════
    // HTTP helper
    // ═══════════════════════════════════════════════════════════
    private fun httpGet(path: String): JSONObject? {
        if (apiKey.isEmpty()) {
            Log.w(TAG, "⚠️ Sin API key, abortando: $path")
            return null
        }
        return try {
            val req = Request.Builder()
                .url("$BASE$path")
                .header("x-apisports-key", apiKey)
                .build()
            client.newCall(req).execute().use { resp ->
                val body = resp.body?.string()
                if (body.isNullOrBlank()) {
                    Log.w(TAG, "Respuesta vacía: $path")
                    null
                } else {
                    JSONObject(body)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "httpGet fail: $path → ${e.message}")
            null
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 1. BUSCAR EQUIPO POR NOMBRE → teamId
    // ═══════════════════════════════════════════════════════════
    suspend fun buscarEquipoId(nombre: String): Int? = withContext(Dispatchers.IO) {
        if (nombre.isBlank()) return@withContext null
        val key = nombre.lowercase().trim()
        cacheEquipos[key]?.let { return@withContext it }

        val json = httpGet("/teams?search=${java.net.URLEncoder.encode(nombre, "UTF-8")}")
            ?: return@withContext null

        val resultados = json.optJSONArray("response") ?: return@withContext null
        if (resultados.length() == 0) {
            Log.w(TAG, "Sin resultados para '$nombre'")
            return@withContext null
        }

        // Tomamos el primer resultado (suele ser el más relevante)
        val team = resultados.optJSONObject(0)?.optJSONObject("team") ?: return@withContext null
        val id = team.optInt("id", -1)
        if (id > 0) {
            cacheEquipos[key] = id
            Log.d(TAG, "✅ Equipo '$nombre' → id=$id (${team.optString("name")})")
            id
        } else null
    }

    // ═══════════════════════════════════════════════════════════
    // 2. BUSCAR FIXTURE ID
    // ═══════════════════════════════════════════════════════════
    suspend fun buscarFixtureId(
        equipoLocalId: Int,
        equipoVisitanteId: Int,
        fechaYYYYMMDD: String
    ): Int? = withContext(Dispatchers.IO) {
        val cacheKey = "$equipoLocalId-$equipoVisitanteId-$fechaYYYYMMDD"
        cacheFixtures[cacheKey]?.let { return@withContext it }

        // Buscar fixtures del local en esa fecha y filtrar por visitante
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
                    Log.d(TAG, "✅ Fixture encontrado: $cacheKey → $fixtureId")
                    return@withContext fixtureId
                }
            }
        }
        Log.w(TAG, "⚠️ No se encontró fixture para $cacheKey")
        null
    }

    /**
     * Resuelve todo de una: nombre local + nombre visitante + fecha → fixtureId.
     * Devuelve null si no hay API key o no se encuentra.
     */
    suspend fun resolverFixtureId(
        equipoLocal: String,
        equipoVisitante: String,
        fechaYYYYMMDD: String
    ): Int? {
        if (equipoLocal.isBlank() || equipoVisitante.isBlank()) return null

        val idLocal = buscarEquipoId(equipoLocal) ?: return null
        val idVisitante = buscarEquipoId(equipoVisitante) ?: return null
        return buscarFixtureId(idLocal, idVisitante, fechaYYYYMMDD)
    }

    // ═══════════════════════════════════════════════════════════
    // 3. DATOS DEL PARTIDO EN VIVO
    // ═══════════════════════════════════════════════════════════
    suspend fun obtenerPartidoEnVivo(fixtureId: Int, forzarRefresh: Boolean = false): PartidoEnVivo? =
        withContext(Dispatchers.IO) {
            // Caché de 60 seg
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

            // Traer eventos y stats en paralelo (simulado secuencial, son rápidos)
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

    // ═══════════════════════════════════════════════════════════
    // UTIL
    // ═══════════════════════════════════════════════════════════
    fun fechaApi(fechaYYYYMMDD: String): String {
        // La API espera yyyy-MM-dd, ya lo tenemos así
        return try {
            val inFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val outFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            outFmt.format(inFmt.parse(fechaYYYYMMDD)!!)
        } catch (e: Exception) { fechaYYYYMMDD }
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
    val estadoCorto: String, // "NS", "1H", "HT", "2H", "ET", "FT", etc.
    val eventos: List<EventoPartido>,
    val estadisticas: EstadisticasPartido?
) {
    val enVivo: Boolean get() = estadoCorto in listOf("1H", "HT", "2H", "ET", "BT", "P", "LIVE")
    val terminado: Boolean get() = estadoCorto in listOf("FT", "AET", "PEN")
    val noEmpezado: Boolean get() = estadoCorto in listOf("NS", "TBD")
}

data class EventoPartido(
    val minuto: Int,
    val tipo: String,       // "Goal", "Card", "subst", "Var"
    val detalle: String,    // "Normal Goal", "Yellow Card", etc.
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
echo "✅ ApiSportsRepository.kt creado"

echo ""
echo "✅✅✅ Backend API-Sports completo"
echo ""
echo "📋 Próximos pasos:"
echo "  1. Compilá:  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
echo "  2. Si compila OK, avisame y hacemos el rediseño del EventDetailScreen"
echo ""
echo "⚠️ IMPORTANTE: para que funcione la API, agregá la key en Firestore:"
echo "   config/app → campo 'apiSportsKey' = 'tu_key_de_api_football'"
