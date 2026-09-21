#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.animfloat.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Verificar imports actuales
print("=== Imports de animation.core ===")
for line in c.split('\n'):
    if 'animation.core' in line and line.strip().startswith('import'):
        print(f"  {line}")

# Agregar los que faltan justo después de "import androidx.compose.animation.core.tween"
falta = []
for imp in ['animateFloat', 'infiniteRepeatable', 'rememberInfiniteTransition', 'RepeatMode', 'LinearEasing', 'FastOutSlowInEasing']:
    full = f'import androidx.compose.animation.core.{imp}'
    if full not in c:
        falta.append(full)

if falta:
    ancla = 'import androidx.compose.animation.core.tween'
    if ancla in c:
        c = c.replace(ancla, ancla + '\n' + '\n'.join(falta), 1)
        for f in falta:
            print(f"✅ Agregado: {f}")
    else:
        # Fallback: agregar después del primer import animation
        ancla2 = 'import androidx.compose.animation.animateColorAsState'
        if ancla2 in c:
            c = c.replace(ancla2, ancla2 + '\n' + '\n'.join(falta), 1)
            for f in falta:
                print(f"✅ Agregado (alt): {f}")
        else:
            print("❌ No encontré ancla para imports")
            raise SystemExit(1)
else:
    print("ℹ️ Todos los imports ya estaban")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("✅ Listo")
PYEOF

echo ""
echo "Verificá:"
grep -n "animateFloat\|infiniteRepeatable\|rememberInfiniteTransition" "$PLAYER" | head -10

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
