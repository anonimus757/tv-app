#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.pulsesimple.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Ver qué hay en la zona del error
print("=== ANTES (líneas 1575-1595) ===")
lineas = c.split('\n')
for i in range(1574, min(1596, len(lineas))):
    print(f"  {i+1}: {lineas[i]}")

# Reemplazo: quitar el rememberInfiniteTransition y animateFloat
# Dejar un pulseAlpha con LaunchedEffect
viejo = '''    val pulse = rememberInfiniteTransition(label = "livePulse")
    val pulseAlpha by pulse.animateFloat(
        initialValue = 0.4f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "pulseAlpha"
    )'''

nuevo = '''    // Pulse simple sin animaciones (evita imports problemáticos)
    var pulseAlpha by remember { mutableFloatStateOf(1f) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(600)
            pulseAlpha = if (pulseAlpha > 0.7f) 0.4f else 1f
        }
    }'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ Pulse reemplazado por LaunchedEffect")
else:
    print("⚠️ No matcheó el bloque exacto. Buscando variantes...")
    # Variante por si hay espacios distintos
    patron = re.compile(
        r'val\s+pulse\s*=\s*rememberInfiniteTransition[^\n]*\n\s*val\s+pulseAlpha\s+by\s+pulse\.animateFloat\([^)]*\)',
        re.DOTALL
    )
    c_nuevo, n = patron.subn(nuevo, c, count=1)
    if n > 0:
        c = c_nuevo
        print("✅ Variante aplicada")
    else:
        print("❌ No pude reemplazar. Revisá manual.")
        raise SystemExit(1)

# Asegurar import de mutableFloatStateOf
if 'import androidx.compose.runtime.mutableFloatStateOf' not in c:
    if 'import androidx.compose.runtime.*' not in c:
        # Agregar después de mutableStateOf
        for ancla in [
            'import androidx.compose.runtime.mutableStateOf',
            'import androidx.compose.runtime.Composable',
        ]:
            if ancla in c:
                c = c.replace(ancla, ancla + '\nimport androidx.compose.runtime.mutableFloatStateOf', 1)
                print("✅ Import mutableFloatStateOf agregado")
                break

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

# Verificar el resultado
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

print("")
if 'pulseAlpha by pulse.animateFloat' in final:
    print("⚠️ Todavía hay animateFloat")
else:
    print("✅ Ya no hay animateFloat problemático")

print("")
print("=== DESPUÉS (líneas 1575-1595) ===")
lineas = final.split('\n')
for i in range(1574, min(1596, len(lineas))):
    print(f"  {i+1}: {lineas[i]}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
