#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

echo "🔄 Restaurando M3u8Extractor.kt del backup..."

if [ -f "$DATA_DIR/M3u8Extractor.kt.bak-retry" ]; then
    cp "$DATA_DIR/M3u8Extractor.kt.bak-retry" "$DATA_DIR/M3u8Extractor.kt"
    echo "✅ Restaurado desde .bak-retry"
else
    echo "❌ No hay backup .bak-retry"
    exit 1
fi

echo ""
echo "🔎 Verificando:"
grep -q "WARM-UP: primera petición" "$DATA_DIR/M3u8Extractor.kt" && echo "  ⚠️  Aún tiene warm-up" || echo "  ✓ Warm-up eliminado"

echo ""
echo "✅✅✅ Revert completo — extrayendo como antes"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"