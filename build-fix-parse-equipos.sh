#!/bin/bash
set -e

REPO="app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
cp "$REPO" "${REPO}.bak.parse.$(date +%s)"
echo "✅ Backup: ${REPO}.bak.parse.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Reemplazar la lectura de equipoLocal/equipoVisitante para que haga fallback parseando descripcion
viejo = '''            // Campos API-Sports (opcionales)
            val equipoLocal = doc.getString("equipo_local")?.trim() ?: ""
            val equipoVisitante = doc.getString("equipo_visitante")?.trim() ?: ""
            val liga = doc.getString("liga")?.trim() ?: ""
            val fixtureId = doc.getLong("fixture_id")?.toInt()'''

nuevo = '''            // Campos API-Sports: primero busca en Firestore, si no, parsea de la descripción
            var equipoLocal = doc.getString("equipo_local")?.trim() ?: ""
            var equipoVisitante = doc.getString("equipo_visitante")?.trim() ?: ""

            // Fallback: parsear "AUCAS vs MACARA" → local=AUCAS, visitante=MACARA
            if (equipoLocal.isBlank() || equipoVisitante.isBlank()) {
                val parsed = parsearEquiposDeDescripcion(descripcion)
                if (equipoLocal.isBlank()) equipoLocal = parsed.first
                if (equipoVisitante.isBlank()) equipoVisitante = parsed.second
            }

            // Liga: si no está en Firestore, usar la categoría
            val liga = doc.getString("liga")?.trim()?.takeIf { it.isNotBlank() } ?: categoria
            val fixtureId = doc.getLong("fixture_id")?.toInt()'''

if viejo not in c:
    print("❌ No encontré el bloque de campos API-Sports.")
    raise SystemExit(1)
c = c.replace(viejo, nuevo, 1)
print("✅ Parseo de equipos desde descripcion agregado")

# Agregar la función helper parsearEquiposDeDescripcion al final del archivo (dentro del object)
# Buscamos el último cierre "}" del object y metemos la función antes
m = c.rfind("}")
if m < 0:
    print("❌ No encontré el cierre del object.")
    raise SystemExit(1)

helper = '''
    /**
     * Parsea equipos desde la descripción tipo "AUCAS vs MACARA" o "Boca vs River".
     * Devuelve Pair(local, visitante). Si no puede parsear, devuelve ("", "").
     */
    private fun parsearEquiposDeDescripcion(desc: String): Pair<String, String> {
        return try {
            // Buscar separadores comunes: "vs", "vs.", "v", " - "
            val regex = Regex("""\\s+(?:vs\\.?|v\\.?|-)\\s+""", RegexOption.IGNORE_CASE)
            val partes = desc.split(regex).map { it.trim() }.filter { it.isNotBlank() }

            if (partes.size >= 2) {
                Pair(partes[0], partes[1])
            } else {
                // Fallback: buscar dos equipos en la descripción sin separador
                Pair("", "")
            }
        } catch (e: Exception) {
            Pair("", "")
        }
    }

'''

c = c[:m] + helper + c[m:]

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ Función parsearEquiposDeDescripcion agregada")
PYEOF

echo ""
echo "✅✅✅ Parseo de equipos desde descripcion OK"
echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
