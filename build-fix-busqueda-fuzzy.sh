#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.fuzzy.$(date +%s)"
echo "✅ Backup: ${API}.bak.fuzzy.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# PASO 1: Reemplazar resolverFixtureId con versión con fallback fuzzy
# ═══════════════════════════════════════════════════════════
viejo_resolver = '''    suspend fun resolverFixtureId(
        equipoLocal: String,
        equipoVisitante: String,
        fechaYYYYMMDD: String
    ): Int? {
        if (equipoLocal.isBlank() || equipoVisitante.isBlank()) return null
        val idLocal = buscarEquipoId(equipoLocal) ?: return null
        val idVisitante = buscarEquipoId(equipoVisitante) ?: return null
        return buscarFixtureId(idLocal, idVisitante, fechaYYYYMMDD)
    }'''

nuevo_resolver = '''    suspend fun resolverFixtureId(
        equipoLocal: String,
        equipoVisitante: String,
        fechaYYYYMMDD: String
    ): Int? {
        if (equipoLocal.isBlank() || equipoVisitante.isBlank()) return null

        // ─── Intento 1: búsqueda exacta de equipos ───
        val idLocal = buscarEquipoId(equipoLocal)
        val idVisitante = buscarEquipoId(equipoVisitante)
        if (idLocal != null && idVisitante != null) {
            val fid = buscarFixtureId(idLocal, idVisitante, fechaYYYYMMDD)
            if (fid != null) {
                Log.d(TAG, "✅ Fixture por búsqueda exacta: $fid")
                return fid
            }
        }

        // ─── Intento 2 (fallback): buscar TODOS los partidos del día + fuzzy match ───
        Log.d(TAG, "🔍 Exacta falló, probando fuzzy por fecha...")
        return buscarFixturePorFechaFuzzy(equipoLocal, equipoVisitante, fechaYYYYMMDD)
    }

    /**
     * Trae TODOS los fixtures del día y busca coincidencia fuzzy con los nombres.
     * Tolera abreviaturas como "dep cuenca" → "Deportivo Cuenca".
     */
    private suspend fun buscarFixturePorFechaFuzzy(
        local: String,
        visitante: String,
        fecha: String
    ): Int? = withContext(Dispatchers.IO) {
        val json = httpGet("/fixtures?date=$fecha") ?: return@withContext null
        val fixtures = json.optJSONArray("response") ?: return@withContext null
        Log.d(TAG, "📊 ${fixtures.length()} partidos el $fecha")

        val localNorm = normalizarNombre(local)
        val visitanteNorm = normalizarNombre(visitante)

        var mejorMatch: Int? = null
        var mejorScore = 0.0

        for (i in 0 until fixtures.length()) {
            val f = fixtures.optJSONObject(i) ?: continue
            val teams = f.optJSONObject("teams") ?: continue
            val homeName = teams.optJSONObject("home")?.optString("name", "") ?: continue
            val awayName = teams.optJSONObject("away")?.optString("name", "") ?: continue
            val fixtureId = f.optJSONObject("fixture")?.optInt("id", -1) ?: continue

            val homeNorm = normalizarNombre(homeName)
            val awayNorm = normalizarNombre(awayName)

            // Score combinado: local vs home + visitante vs away
            val scoreNormal = similitud(localNorm, homeNorm) + similitud(visitanteNorm, awayNorm)
            // También probamos invertido (por si los equipos están al revés)
            val scoreInvertido = similitud(localNorm, awayNorm) + similitud(visitanteNorm, homeNorm)
            val score = maxOf(scoreNormal, scoreInvertido)

            if (score > mejorScore) {
                mejorScore = score
                mejorMatch = fixtureId
                Log.d(TAG, "   🔎 '$homeName vs $awayName' score=${"%.2f".format(score)}")
            }
        }

        // Umbral: score >= 1.0 significa que al menos hay match decente en un lado
        if (mejorScore >= 1.0 && mejorMatch != null) {
            Log.d(TAG, "✅ Fuzzy match: fixtureId=$mejorMatch (score=${"%.2f".format(mejorScore)})")
            mejorMatch
        } else {
            Log.w(TAG, "❌ Fuzzy match falló (mejor score: ${"%.2f".format(mejorScore)})")
            null
        }
    }

    /**
     * Normaliza un nombre de equipo:
     * - minúsculas
     * - sin acentos
     * - sin palabras comunes (club, deportivo, fc, cd, etc.)
     * - sin espacios extra
     */
    private fun normalizarNombre(nombre: String): String {
        var n = nombre.lowercase()
            .replace("á", "a").replace("é", "e").replace("í", "i")
            .replace("ó", "o").replace("ú", "u").replace("ñ", "n")
            .replace(Regex("[^a-z0-9\\s]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        // Quitar palabras comunes que no aportan
        val comunes = setOf(
            "club", "deportivo", "dep", "cd", "cs", "fc", "cf", "sc", "sd", "ad",
            "atletico", "atl", "real", "united", "city", "the"
        )
        n = n.split(" ").filter { it !in comunes }.joinToString(" ")
        return n.trim()
    }

    /**
     * Similitud entre dos nombres normalizados.
     * - Si uno contiene al otro → score alto (0.9)
     * - Si comparten tokens → Jaccard
     * - Sino 0
     */
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
    }'''

if viejo_resolver not in c:
    print("❌ No encontré el resolverFixtureId original.")
    raise SystemExit(1)
c = c.replace(viejo_resolver, nuevo_resolver, 1)
print("✅ resolverFixtureId ahora tiene fallback fuzzy")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("✅✅✅ Búsqueda fuzzy agregada")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()
checks = {
    "buscarFixturePorFechaFuzzy": 'buscarFixturePorFechaFuzzy' in final,
    "normalizarNombre": 'private fun normalizarNombre' in final,
    "similitud": 'private fun similitud' in final,
}
for k, v in checks.items():
    print(f"   {'✅' if v else '❌'} {k}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
