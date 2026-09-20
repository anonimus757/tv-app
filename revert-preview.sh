#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/HomeScreen.kt"

if [ -f "$FILE.bak-preview" ]; then
    cp "$FILE.bak-preview" "$FILE"
    echo "✅ Revertido desde .bak-preview"
else
    echo "❌ No hay backup .bak-preview"
    exit 1
fi

echo ""
echo "🔎 Verificando:"
grep -c "CardVideoPreview" "$FILE" | xargs -I {} echo "  CardVideoPreview: {} (debe ser 0)"
grep -c "mostrarVideoPreview" "$FILE" | xargs -I {} echo "  mostrarVideoPreview: {} (debe ser 0)"

echo ""
echo "✅✅✅ Preview eliminado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"