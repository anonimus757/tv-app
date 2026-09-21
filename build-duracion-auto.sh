#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# 1. EventRepository: hardcodear 150 min, no leer de Firestore
# ═══════════════════════════════════════════════════════════
REPO="app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
cp "$REPO" "${REPO}.bak.duracion.$(date +%s)"
echo "✅ Backup EventRepository"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Quitar lectura de duracion_minutos del Firestore y dejar 150 hardcoded
viejo = '''            val duracionMinutos = doc.getLong("duracion_minutos")?.toInt() ?: 150'''
nuevo = '''            // Duración automática: 150 minutos (2h 30min) para todos los eventos
            val duracionMinutos = 150'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ EventRepository: duración hardcoded en 150 min")
else:
    print("⚠️ No matcheó la lectura de duracion_minutos")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2. Models.kt: forzar default 150 (por si acaso)
# ═══════════════════════════════════════════════════════════
MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
cp "$MODELS" "${MODELS}.bak.duracion.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# El campo sigue existiendo pero con default 150
viejo = 'val duracionMinutos: Int = 150,'
if viejo in c:
    print("ℹ️ Models.kt ya tiene default 150")
else:
    # Si tiene otro valor, forzarlo
    import re
    c_nuevo = re.sub(r'val\s+duracionMinutos\s*:\s*Int\s*=\s*\d+', 'val duracionMinutos: Int = 150', c)
    if c_nuevo != c:
        c = c_nuevo
        print("✅ Models.kt: default forzado a 150")
        with open(fp, 'w', encoding='utf-8') as f:
            f.write(c)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

echo ""
echo "✅✅✅ Duración automática 150 min (2h 30min)"
echo ""
echo "📋 Próximos pasos:"
echo "  1. Compilá:  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
echo "  2. Actualizá el Apps Script (ver abajo en el mensaje del asistente)"
echo "  3. Podés BORRAR la columna duracion_minutos del Sheet"
echo "  4. Corré el botón de sincronizar del Sheet"
