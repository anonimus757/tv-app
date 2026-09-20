#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

echo "📝 Agregando import de alpha..."

# Verificar si ya está
if grep -q "import androidx.compose.ui.draw.alpha" "$FILE"; then
    echo "ℹ️  Ya estaba el import"
else
    # Insertar después de "import androidx.compose.ui.draw.scale" o similar
    if grep -q "import androidx.compose.ui.draw.scale" "$FILE"; then
        sed -i 's|import androidx.compose.ui.draw.scale|import androidx.compose.ui.draw.alpha\nimport androidx.compose.ui.draw.scale|' "$FILE"
    elif grep -q "import androidx.compose.ui.draw.clip" "$FILE"; then
        sed -i 's|import androidx.compose.ui.draw.clip|import androidx.compose.ui.draw.alpha\nimport androidx.compose.ui.draw.clip|' "$FILE"
    else
        # Fallback: agregar antes de la primera línea de import de media3
        sed -i '0,/^import/s//import androidx.compose.ui.draw.alpha\nimport/' "$FILE"
    fi
    echo "✅ Import agregado"
fi

echo ""
echo "🔎 Verificando:"
grep -n "import androidx.compose.ui.draw.alpha" "$FILE"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"