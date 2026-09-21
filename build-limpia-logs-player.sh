#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
BACKUP="${PLAYER}.bak.$(date +%s)"

[ ! -f "$PLAYER" ] && { echo "❌ No existe $PLAYER"; exit 1; }
cp "$PLAYER" "$BACKUP"
echo "✅ Backup: $BACKUP"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

original_len = len(c)

# Borrar líneas que loguean la URL y el Referer (las que agregó el fix-zapping)
# Patrón: cualquier línea que contenga logDiag("🎯 URL: ...) o logDiag("🎯 Referer: ...)
# o DebugLog.add("🎯 URL: ...) / DebugLog.add("🎯 Referer: ...)
patron = r'[ \t]*(?:logDiag|DebugLog\.add)\("🎯 (?:URL|Referer):[^\n]*\n'

c_nuevo, count = re.subn(patron, '', c)

if count == 0:
    print("ℹ️ No encontré líneas con '🎯 URL:' o '🎯 Referer:' (puede que ya estén limpias)")
else:
    print(f"✅ Borradas {count} línea(s) de log del reproductor")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c_nuevo)

print(f"📉 Archivo: {original_len} → {len(c_nuevo)} bytes")
PYEOF

echo ""
echo "✅✅✅ Limpieza de logs completa"
echo ""
echo "Verificá con:"
echo "  grep -n '🎯 URL\\|🎯 Referer' app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
echo "  (si no devuelve nada → quedó limpio)"
echo ""
echo "Después compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
