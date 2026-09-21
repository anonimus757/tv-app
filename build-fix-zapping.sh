#!/bin/bash
set -e

PLAYER_FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
BACKUP_FILE="${PLAYER_FILE}.bak.$(date +%s)"

[ ! -f "$PLAYER_FILE" ] && { echo "❌ No existe $PLAYER_FILE"; exit 1; }
cp "$PLAYER_FILE" "$BACKUP_FILE"
echo "✅ Backup: $BACKUP_FILE"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Inyectar Referer forzado para futbollibrefullhd si embedActual.referer está vacío
c = c.replace(
    'val headers = mutableMapOf(\n                "User-Agent" to USER_AGENT,\n                "Accept" to "*/*",\n                "Connection" to "keep-alive"\n            )',
    'val refForzado = embedActual.referer.ifBlank { "https://futbollibrefullhd.org/" }\n            val headers = mutableMapOf(\n                "User-Agent" to USER_AGENT,\n                "Accept" to "*/*",\n                "Connection" to "keep-alive",\n                "Referer" to refForzado,\n                "Origin" to refForzado.trimEnd(\'/\')\n            )'
)

# 2. Reemplazar bloque de headers viejos
c = c.replace(
    'if (embedActual.referer.isNotBlank()) {\n                headers["Referer"] = embedActual.referer\n                headers["Origin"] = embedActual.referer.trimEnd(\'/\')\n            }',
    '// Referer forzado (ya seteado arriba)'
)

# 3. Log de URL + Referer
c = c.replace(
    'logDiag("🔵 Cargando URL (trigger=$reloadTrigger)")',
    'logDiag("🔵 Cargando URL (trigger=$reloadTrigger)")\n        logDiag("🎯 URL: $url")\n        logDiag("🎯 Referer: ${embedActual.referer.ifBlank { "https://futbollibrefullhd.org/" }}")'
)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ PlayerScreen.kt actualizado")
PYEOF

echo ""
echo "✅✅✅ Fix ZAPPING aplicado"
echo "Compilá con:"
echo "  ./gradlew clean assembleDebug --no-daemon --max-workers=1"
