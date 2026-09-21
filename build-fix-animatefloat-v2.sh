#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.animfloatv2.$(date +%s)"
echo "✅ Backup"

echo "=== Imports actuales ==="
grep -n "^import androidx.compose.animation" "$PLAYER"

echo ""
echo "=== Línea 1581 ==="
sed -n '1578,1584p' "$PLAYER"

echo ""
echo "🔧 Arreglando imports..."

# Insertar import de animateFloat ANTES de la primera línea de código
python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    lineas = f.readlines()

# Buscar la línea de import de animation.core.tween (o la primera animation.core)
idx_ancla = -1
for i, l in enumerate(lineas):
    if 'androidx.compose.animation.core.tween' in l:
        idx_ancla = i
        break

if idx_ancla < 0:
    for i, l in enumerate(lineas):
        if 'androidx.compose.animation.core' in l:
            idx_ancla = i
            break

if idx_ancla < 0:
    # Última opción: después del último import
    for i, l in enumerate(lineas):
        if l.startswith('import '):
            idx_ancla = i

necesarios = [
    'import androidx.compose.animation.core.animateFloat\n',
    'import androidx.compose.animation.core.infiniteRepeatable\n',
    'import androidx.compose.animation.core.rememberInfiniteTransition\n',
    'import androidx.compose.animation.core.RepeatMode\n',
]

# Ver qué falta
contenido = ''.join(lineas)
faltantes = [imp for imp in necesarios if imp.strip() not in contenido]

if faltantes:
    # Insertar justo después del ancla
    lineas[idx_ancla + 1:idx_ancla + 1] = faltantes
    with open(fp, 'w', encoding='utf-8') as f:
        f.writelines(lineas)
    for f_imp in faltantes:
        print(f"✅ Agregado: {f_imp.strip()}")
else:
    print("ℹ️ Todos los imports ya estaban presentes")
PYEOF

echo ""
echo "=== Imports DESPUÉS ==="
grep -n "animateFloat\|infiniteRepeatable\|rememberInfiniteTransition\|RepeatMode" "$PLAYER" | head -8

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
