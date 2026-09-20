#!/bin/bash
# build-fix-zapping.sh - Fix para ZAPPING: redirecciones + headers + fail-fast
set -e

echo "🔧 Aplicando fix para el canal ZAPPING..."

PLAYER_FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
BACKUP_FILE="${PLAYER_FILE}.bak.$(date +%s)"

# 1. Backup de seguridad
if [ ! -f "$PLAYER_FILE" ]; then
    echo "❌ Error: No se encuentra $PLAYER_FILE"
    exit 1
fi

cp "$PLAYER_FILE" "$BACKUP_FILE"
echo "✅ Backup creado en: $BACKUP_FILE"

# 2. Buscar el bloque de creación del DefaultHttpDataSource.Factory
# Buscamos la línea que contiene "DefaultHttpDataSource.Factory()" o similar.
# Este script asume que ya tienes una variable "dataSourceFactory" creada.
# Si no la tienes, el script fallará y deberás revisar el archivo manualmente.

python3 << 'PYEOF'
import re

file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Patrón para encontrar el bloque donde se construye el DataSourceFactory.
# Buscamos "DefaultHttpDataSource.Factory()" o "DefaultHttpDataSourceFactory"
pattern = r'(val\s+dataSourceFactory\s*=\s*DefaultHttpDataSource\.Factory\(\)\s*\n(?:\s*\.set\w+\([^)]*\)\s*\n)*)'

# Reemplazo: la versión mejorada
replacement = '''val dataSourceFactory = DefaultHttpDataSource.Factory()
    .setAllowCrossProtocolRedirects(true) // ⬅️ CRÍTICO para HTTP -> HTTPS
    .setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    .setDefaultRequestProperties(
        mapOf(
            "Referer" to (embedActual.referer.ifEmpty { "https://futbollibrefullhd.org/" }),
            "Origin" to "https://futbollibrefullhd.org"
        )
    )
    .setConnectTimeoutMs(15000)
    .setReadTimeoutMs(15000)

    // Log de debug para ver qué headers se envían
    DebugLog.add("🎯 URL: ${urlFinal}")
    DebugLog.add("🎯 Referer: ${embedActual.referer.ifEmpty { "https://futbollibrefullhd.org/" }}")
'''

# Reemplazar si se encuentra el patrón
new_content, count = re.subn(pattern, replacement, content)

if count == 0:
    print("⚠️ No se encontró el patrón exacto del DataSourceFactory.")
    print("   Abriendo el archivo para que lo revises manualmente...")
    # No modificamos el archivo si no encontramos el patrón
else:
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"✅ Se reemplazó el bloque del DataSourceFactory ({count} vez/veces).")
    print("   Se agregaron logs de URL y Referer.")
PYEOF

# 3. (Opcional) Inyectar un LoadErrorHandlingPolicy custom
# Este bloque es más complejo y depende de la estructura actual de tu código.
# Lo dejamos comentado para que lo revises. Si quieres, en el próximo paso lo hacemos.
: << 'COMMENT'
python3 << 'PYEOF'
# ... código para inyectar LoadErrorHandlingPolicy ...
PYEOF
COMMENT

echo ""
echo "========================================="
echo "✅✅✅ Paso 1 (fix DataSourceFactory) completado"
echo "========================================="
echo ""
echo "📋 Próximos pasos:"
echo "1. Compilá:  ./gradlew clean assembleDebug --no-daemon --max-workers=1"
echo "2. Instalá el APK en tu TV."
echo "3. Probá el ZAPPING de nuevo y pasame el log de DIAG."
echo ""
echo "⚠️  Si el script no encontró el patrón, revisá el archivo manualmente."
echo "   El backup está en: $BACKUP_FILE"