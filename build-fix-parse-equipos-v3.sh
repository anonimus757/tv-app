#!/bin/bash
set -e

REPO="app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
[ ! -f "$REPO" ] && { echo "❌ No existe $REPO"; exit 1; }
cp "$REPO" "${REPO}.bak.parsev3.$(date +%s)"
echo "✅ Backup: ${REPO}.bak.parsev3.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

cambios = 0

# ═══════════════════════════════════════════════════════════
# PASO 1: Insertar campos API-Sports después del bloque de fecha
# ═══════════════════════════════════════════════════════════
ancla_fecha = '''            val fecha = doc.getString("fecha")?.trim() ?: ""
            if (fecha.isEmpty()) {
                DebugLog.log("⚠️ '${descripcion}' sin fecha → descartado")
                return null
            }
'''

nuevo_fecha = '''            val fecha = doc.getString("fecha")?.trim() ?: ""
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
'''

if ancla_fecha in c:
    c = c.replace(ancla_fecha, nuevo_fecha, 1)
    print("✅ Paso 1: campos API-Sports insertados después de fecha")
    cambios += 1
else:
    print("❌ Paso 1: no encontré el ancla de fecha")
    raise SystemExit(1)

# ═══════════════════════════════════════════════════════════
# PASO 2: Reemplazar el constructor de Evento
# ═══════════════════════════════════════════════════════════
viejo_constructor = '''            Evento(
                fuente = fuente,
                groupTitle = categoria,
                descripcion = descripcion,
                hora = hora,
                imagen = imagen,
                embeds = embeds,
                fecha = fecha
            )'''

nuevo_constructor = '''            Evento(
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

if viejo_constructor in c:
    c = c.replace(viejo_constructor, nuevo_constructor, 1)
    print("✅ Paso 2: constructor de Evento actualizado")
    cambios += 1
else:
    print("❌ Paso 2: no encontré el constructor de Evento exacto")
    raise SystemExit(1)

# ═══════════════════════════════════════════════════════════
# PASO 3: Agregar la función helper antes del último cierre
# ═══════════════════════════════════════════════════════════
if 'private fun parsearEquiposDeDescripcion' not in c:
    m = c.rfind("}")
    helper = '''
    /**
     * Parsea equipos desde la descripción tipo "AUCAS vs MACARA" o "Boca vs River".
     * Devuelve Pair(local, visitante). Si no puede parsear, devuelve ("", "").
     */
    private fun parsearEquiposDeDescripcion(desc: String): Pair<String, String> {
        return try {
            val regex = Regex("""\\s+(?:vs\\.?|v\\.?|-)\\s+""", RegexOption.IGNORE_CASE)
            val partes = desc.split(regex).map { it.trim() }.filter { it.isNotBlank() }
            if (partes.size >= 2) Pair(partes[0], partes[1]) else Pair("", "")
        } catch (e: Exception) {
            Pair("", "")
        }
    }

'''
    c = c[:m] + helper + c[m:]
    print("✅ Paso 3: función parsearEquiposDeDescripcion agregada")
    cambios += 1
else:
    print("ℹ️ Paso 3: función ya existía")

# ═══════════════════════════════════════════════════════════
# PASO 4: Log de cuántos eventos tienen fixtureId (opcional)
# ═══════════════════════════════════════════════════════════
viejo_log = '            DebugLog.log("✅ Firestore eventos OK: ${lista.size}")'
nuevo_log = '''            val conFixture = lista.count { it.fixtureId != null }
            DebugLog.log("✅ Firestore eventos OK: ${lista.size} (con fixtureId: $conFixture)")'''
if viejo_log in c:
    c = c.replace(viejo_log, nuevo_log, 1)
    print("✅ Paso 4: log con contador de fixtureId")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print(f"✅ Total cambios: {cambios}")

# Verificación final
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

checks = {
    "equipoLocal = parsed.first": "equipoLocal = parsed.first" in final,
    "parsearEquiposDeDescripcion": "private fun parsearEquiposDeDescripcion" in final,
    "fixtureId = fixtureId": "fixtureId = fixtureId" in final,
    "equipoLocal = equipoLocal": "equipoLocal = equipoLocal" in final,
}
for k, v in checks.items():
    print(f"   {'✅' if v else '❌'} {k}")
PYEOF

echo ""
echo "✅✅✅ Fix parse equipos v3 OK"
echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
