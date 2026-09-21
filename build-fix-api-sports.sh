#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# 1. Verificar que Models.kt esté bien (debe tener los campos)
# ═══════════════════════════════════════════════════════════
MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
if ! grep -q "equipoLocal" "$MODELS"; then
    echo "❌ Models.kt no tiene equipoLocal. Corré primero build-fix-models-clean.sh"
    exit 1
fi
echo "✅ Models.kt OK"

# ═══════════════════════════════════════════════════════════
# 2. Crear ApiSportsRepository.kt
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
                if (body.isNullOrBlank()) null else JSONObject(body)
            }
        } catch (e: Exception) {
            Log.e(TAG, "httpGet fail: $path → ${e.message}")
            null
        }
    }

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

        val team = resultados.optJSONObject(0)?.optJSONObject("team") ?: return@withContext null
        val id = team.optInt("id", -1)
        if (id > 0) {
            cacheEquipos[key] = id
            Log.d(TAG, "✅ Equipo '$nombre' → id=$id (${team.optString("name")})")
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
                    Log.d(TAG, "✅ Fixture encontrado: $cacheKey → $fixtureId")
                    return@withContext fixtureId
                }
            }
        }
        Log.w(TAG, "⚠️ No se encontró fixture para $cacheKey")
        null
    }

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

    fun fechaApi(fechaYYYYMMDD: String): String {
        return try {
            val inFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val outFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            outFmt.format(inFmt.parse(fechaYYYYMMDD)!!)
        } catch (e: Exception) { fechaYYYYMMDD }
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
KOTLIN_EOF
echo "✅ ApiSportsRepository.kt creado"

# ═══════════════════════════════════════════════════════════
# 3. Verificar que RemoteConfigRepository tenga apiSportsKey
# ═══════════════════════════════════════════════════════════
RC="app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
if ! grep -q "apiSportsKey" "$RC"; then
    echo "⚠️ RemoteConfigRepository.kt NO tiene apiSportsKey"
    cp "$RC" "${RC}.bak.apikey.$(date +%s)"
    python3 << 'PYEOF'
import re
fp = "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Buscar data class RemoteConfig
patron = re.compile(
    r'(data\s+class\s+\w*Config\w*\s*\([^)]*?)(\)\s*(?:/\*.*?\*/)?\s*$)',
    re.MULTILINE | re.DOTALL
)
m = patron.search(c)
if m:
    cuerpo = m.group(1)
    if "apiSportsKey" not in cuerpo:
        cuerpo_strip = cuerpo.rstrip()
        if not cuerpo_strip.endswith(","):
            cuerpo_strip += ","
        nuevo_cuerpo = cuerpo_strip + '\n    val apiSportsKey: String = "" // API-Sports (Firestore: config/app)'
        c = c[:m.start(1)] + nuevo_cuerpo + c[m.end(1):]
        with open(fp, 'w', encoding='utf-8') as f:
            f.write(c)
        print("✅ RemoteConfig: campo apiSportsKey agregado")
else:
    print("⚠️ No pude agregar apiSportsKey automáticamente. Agregalo manual al data class RemoteConfig")
PYEOF
else
    echo "✅ RemoteConfigRepository.kt ya tiene apiSportsKey"
fi

# ═══════════════════════════════════════════════════════════
# 4. Fix import faltante en EventDetailScreen.kt (alpha)
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
if [ -f "$DETAIL" ]; then
    cp "$DETAIL" "${DETAIL}.bak.alpha.$(date +%s)"
    python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

if 'import androidx.compose.ui.draw.alpha' not in c:
    c = c.replace(
        'import androidx.compose.ui.draw.clip',
        'import androidx.compose.ui.draw.alpha\nimport androidx.compose.ui.draw.clip'
    )
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ EventDetailScreen.kt: import alpha agregado")
else:
    print("ℹ️ EventDetailScreen.kt ya tiene import alpha")
PYEOF
else
    echo "⚠️ No existe $DETAIL (extraño, debería estar)"
fi

echo ""
echo "✅✅✅ Fix ApiSportsRepository completo"
echo ""
echo "Verificá:"
echo "  ls -la app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
