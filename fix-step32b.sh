#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

if [ ! -f "$FILE" ]; then
  echo "❌ No encuentro $FILE"
  exit 1
fi

echo "📝 Agregando imports faltantes a PlayerScreen.kt..."

# Backup
cp "$FILE" "$FILE.bak32b"

# Agregar los imports que faltan (si no están ya)
if ! grep -q "import androidx.compose.foundation.focusable" "$FILE"; then
  # Insertamos focusable después de clickable (que sí existe)
  sed -i 's|import androidx.compose.foundation.clickable|import androidx.compose.foundation.clickable\nimport androidx.compose.foundation.focusable|' "$FILE"
  echo "  ✓ import focusable"
fi

if ! grep -q "import androidx.compose.foundation.gestures.detectHorizontalDragGestures" "$FILE"; then
  # Insertamos gestures después de focusable
  sed -i 's|import androidx.compose.foundation.focusable|import androidx.compose.foundation.focusable\nimport androidx.compose.foundation.gestures.detectHorizontalDragGestures\nimport androidx.compose.foundation.gestures.detectTapGestures|' "$FILE"
  echo "  ✓ imports de gestures"
fi

echo ""
echo "🔎 Verificando:"
grep -n "import androidx.compose.foundation.focusable" "$FILE"
grep -n "import androidx.compose.foundation.gestures.detectHorizontalDragGestures" "$FILE"
grep -n "import androidx.compose.foundation.gestures.detectTapGestures" "$FILE"

echo ""
echo "✅✅✅ Fix 32b completo — imports agregados"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"