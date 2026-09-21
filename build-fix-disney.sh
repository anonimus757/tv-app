#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# 1. Fix EventDetailScreen: falta import alpha
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
cp "$DETAIL" "${DETAIL}.bak.fixalpha.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

if 'import androidx.compose.ui.draw.alpha' not in c:
    # Insertar después de clip
    if 'import androidx.compose.ui.draw.clip' in c:
        c = c.replace(
            'import androidx.compose.ui.draw.clip',
            'import androidx.compose.ui.draw.alpha\nimport androidx.compose.ui.draw.clip',
            1
        )
        print("✅ Import alpha agregado a EventDetailScreen")
    else:
        # Fallback: después de ui.Modifier
        c = c.replace(
            'import androidx.compose.ui.Modifier',
            'import androidx.compose.ui.Modifier\nimport androidx.compose.ui.draw.alpha',
            1
        )
        print("✅ Import alpha agregado (fallback)")
else:
    print("ℹ️ alpha ya estaba")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2. Fix HomeScreen: setOf comido
# ═══════════════════════════════════════════════════════════
HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME" "${HOME}.bak.fixset.$(date +%s)"

echo ""
echo "🔍 Estado del error en HomeScreen línea 83:"
sed -n '78,90p' "$HOME"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Si hay "val X = set" sin continuar, o "setOf(" roto
# Arreglar el patrón roto
import re

# Caso 1: "val xxx = set\n" → reemplazar por setOf correcto
c = re.sub(
    r'val\s+(\w+)\s*=\s*set\s*\n',
    'val \\1 = setOf()\n',
    c
)

# Caso 2: si quedó "= set\n" con más código huérfano
# Buscar "= set" seguido de saltos de línea hasta otro código
patron = re.compile(r'=\s*set\s*\n(?!Of)')
if patron.search(c):
    print("⚠️ Encontré '= set' huérfano")
    # Reemplazar por setOf vacío
    c = patron.sub('= setOf()\n', c)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("✅ HomeScreen procesado")

# Mostrar la zona después
print("")
print("=== DESPUÉS (líneas 78-90) ===")
with open(fp, 'r', encoding='utf-8') as f:
    lineas = f.read().split('\n')
for i in range(77, min(91, len(lineas))):
    print(f"  {i+1}: {lineas[i]}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
