#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.fuzzyv2.$(date +%s)"
echo "✅ Backup: ${API}.bak.fuzzyv2.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# 1. Reemplazar normalizarNombre con versión mejorada
# ═══════════════════════════════════════════════════════════
patron_norm = re.compile(
    r'private fun normalizarNombre\(nombre: String\): String \{.*?\n    \}',
    re.DOTALL
)

nueva_norm = '''private fun normalizarNombre(nombre: String): String {
        var n = nombre.lowercase()
            .replace("á", "a").replace("é", "e").replace("í", "i")
            .replace("ó", "o").replace("ú", "u").replace("ñ", "n")
            .replace("ü", "u")
            .replace(Regex("[^a-z0-9\\\\s]"), " ")
            .replace(Regex("\\\\s+"), " ")
            .trim()

        // Solo quitamos sufijos que NO son parte del nombre real
        // (NO quitamos atletico, club, deportivo, nacional porque son críticos)
        val sufijos = setOf(
            "fc", "cf", "sc", "sd", "ad", "cd", "cs", "the", "sa"
        )
        n = n.split(" ").filter { it !in sufijos }.joinToString(" ")
        return n.trim()
    }'''

c_nuevo, n = patron_norm.subn(nueva_norm, c, count=1)
if n == 0:
    print("❌ No matcheó normalizarNombre")
    raise SystemExit(1)
c = c_nuevo
print("✅ normalizarNombre mejorado (mantiene atletico, club, deportivo, nacional)")

# ═══════════════════════════════════════════════════════════
# 2. Bajar umbral y agregar logs con DebugLog
# ═══════════════════════════════════════════════════════════
viejo_umbral = '''        // Umbral alto: 1.5 (evita matches flojos tipo "Nacional" == "Nacional")
        if (mejorScore >= 1.5 && mejorMatch != null) {
            Log.d(TAG, "✅ Fuzzy match: '$mejorDesc' (score=${"%.2f".format(mejorScore)}) → fixtureId=$mejorMatch")
            mejorMatch
        } else {
            Log.w(TAG, "❌ Fuzzy sin coincidencias válidas (mejor: ${"%.2f".format(mejorScore)} · $mejorDesc)")
            null
        }'''

nuevo_umbral = '''        DebugLog.log("🔍 Fuzzy: '$localNorm' vs '$visitanteNorm' → mejor '${mejorDesc}' score=${"%.2f".format(mejorScore)}")

        // Umbral 1.2: requiere que AMBOS lados tengan buena similitud
        if (mejorScore >= 1.2 && mejorMatch != null) {
            DebugLog.log("✅ Match: '$mejorDesc' → ID $mejorMatch")
            Log.d(TAG, "✅ Fuzzy: '$mejorDesc' (score=${"%.2f".format(mejorScore)}) → $mejorMatch")
            mejorMatch
        } else {
            DebugLog.log("❌ Sin match (mejor: ${"%.2f".format(mejorScore)} · $mejorDesc)")
            Log.w(TAG, "❌ Sin match (mejor: ${"%.2f".format(mejorScore)})")
            null
        }'''

if viejo_umbral in c:
    c = c.replace(viejo_umbral, nuevo_umbral, 1)
    print("✅ Umbral bajado a 1.2 + logs con DebugLog")
else:
    print("⚠️ No matcheó el bloque de umbral")

# ═══════════════════════════════════════════════════════════
# 3. Mejorar la condición de "ambos lados válidos"
# ═══════════════════════════════════════════════════════════
viejo_cond = '''            // ⚠️ AMBOS lados deben tener mínimo de similitud (>= 0.5)
            val normalValido = sLocalHome >= 0.5 && sVisitAway >= 0.5
            val invertidoValido = sLocalAway >= 0.5 && sVisitHome >= 0.5'''

nuevo_cond = '''            // ⚠️ AMBOS lados deben tener mínimo de similitud (>= 0.4)
            val normalValido = sLocalHome >= 0.4 && sVisitAway >= 0.4
            val invertidoValido = sLocalAway >= 0.4 && sVisitHome >= 0.4'''

if viejo_cond in c:
    c = c.replace(viejo_cond, nuevo_cond, 1)
    print("✅ Umbral por lado bajado a 0.4")

# ═══════════════════════════════════════════════════════════
# 4. Agregar DebugLog a la búsqueda exacta también
# ═══════════════════════════════════════════════════════════
viejo_exacta = '''        // ─── Intento 1: búsqueda exacta de equipos ───
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
        return buscarFixturePorFechaFuzzy(equipoLocal, equipoVisitante, fechaYYYYMMDD)'''

nuevo_exacta = '''        // ─── Intento 1: búsqueda exacta de equipos ───
        DebugLog.log("🔍 Buscando '$equipoLocal' vs '$equipoVisitante' en $fechaYYYYMMDD")
        val idLocal = buscarEquipoId(equipoLocal)
        val idVisitante = buscarEquipoId(equipoVisitante)
        if (idLocal != null && idVisitante != null) {
            val fid = buscarFixtureId(idLocal, idVisitante, fechaYYYYMMDD)
            if (fid != null) {
                DebugLog.log("✅ Encontrado por búsqueda exacta: $fid")
                return fid
            }
        }

        // ─── Intento 2 (fallback): buscar TODOS los partidos del día + fuzzy match ───
        DebugLog.log("🔍 Búsqueda exacta sin resultado, probando fuzzy...")
        return buscarFixturePorFechaFuzzy(equipoLocal, equipoVisitante, fechaYYYYMMDD)'''

if viejo_exacta in c:
    c = c.replace(viejo_exacta, nuevo_exacta, 1)
    print("✅ Logs agregados a la búsqueda exacta")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ ApiSportsRepository.kt actualizado")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
