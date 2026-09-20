#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

echo "📝 Sacando referencias a contadorErrores..."

# Reemplazar la línea que tiene "contadorErrores = 0" por nada
sed -i '/contadorErrores = 0/d' "$FILE"

echo ""
echo "🔎 Verificando:"
grep -c "contadorErrores" "$FILE" | xargs -I {} echo "  Referencias restantes: {}"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"