#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.fuzzyfix.$(date +%s)"
echo "✅ Backup: ${API}.bak.fuzzyfix.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

patron = re.compile(
    r'private suspend fun buscarFixturePorFechaFuzzy\s*\([^)]*\)\s*:\s*Int\?\s*=\s*withContext\(Dispatchers\.IO\)\s*\{.*?\n    \}',
    re.DOTALL
)

nuevo = '''private suspend fun buscarFixturePorFechaFuzzy(
        local: String,
        visitante: String,
        fecha: String
    ): Int? = withContext(Dispatchers.IO) {
        val json = httpGet("/fixtures?date=$fecha") ?: return@withContext null
        val fixtures = json.optJSONArray("response") ?: return@withContext null
        Log.d(TAG, "📊 ${fixtures.length()} partidos el $fecha")

        val localNorm = normalizarNombre(local)
        val visitanteNorm = normalizarNombre(visitante)
        Log.d(TAG, "🔍 Buscando: '$localNorm' vs '$visitanteNorm'")

        var mejorMatch: Int? = null
        var mejorScore = 0.0
        var mejorDesc = ""

        for (i in 0 until fixtures.length()) {
            val f = fixtures.optJSONObject(i) ?: continue
            val teams = f.optJSONObject("teams") ?: continue
            val homeName = teams.optJSONObject("home")?.optString("name", "") ?: continue
            val awayName = teams.optJSONObject("away")?.optString("name", "") ?: continue
            val fixtureId = f.optJSONObject("fixture")?.optInt("id", -1) ?: continue

            val homeNorm = normalizarNombre(homeName)
            val awayNorm = normalizarNombre(awayName)

            val sLocalHome = similitud(localNorm, homeNorm)
            val sVisitAway = similitud(visitanteNorm, awayNorm)
            val sLocalAway = similitud(localNorm, awayNorm)
            val sVisitHome = similitud(visitanteNorm, homeNorm)

            // ⚠️ AMBOS lados deben tener mínimo de similitud (>= 0.5)
            val normalValido = sLocalHome >= 0.5 && sVisitAway >= 0.5
            val invertidoValido = sLocalAway >= 0.5 && sVisitHome >= 0.5

            val mejorLocal = maxOf(sLocalHome, sLocalAway)
            val mejorVisit = maxOf(sVisitAway, sVisitHome)

            if ((normalValido || invertidoValido) && (mejorLocal + mejorVisit) > mejorScore) {
                mejorScore = mejorLocal + mejorVisit
                mejorMatch = fixtureId
                mejorDesc = "$homeName vs $awayName"
            }
        }

        // Umbral alto: 1.5 (evita matches flojos tipo "Nacional" == "Nacional")
        if (mejorScore >= 1.5 && mejorMatch != null) {
            Log.d(TAG, "✅ Fuzzy match: '$mejorDesc' (score=${"%.2f".format(mejorScore)}) → fixtureId=$mejorMatch")
            mejorMatch
        } else {
            Log.w(TAG, "❌ Fuzzy sin coincidencias válidas (mejor: ${"%.2f".format(mejorScore)} · $mejorDesc)")
            null
        }
    }'''

c_nuevo, n = patron.subn(nuevo, c, count=1)

if n == 0:
    print("❌ No matcheó buscarFixturePorFechaFuzzy. Abortando.")
    raise SystemExit(1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c_nuevo)
print("✅ Fuzzy matching corregido: requiere AMBOS lados ≥ 0.5 y score total ≥ 1.5")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
