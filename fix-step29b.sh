#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

FILE="app/src/main/java/com/anonimus757/tvapp/ui/BusquedaScreen.kt"

if [ ! -f "$FILE" ]; then
  echo "❌ No encuentro $FILE"
  exit 1
fi

echo "📝 Cambiando ev.categoria → ev.groupTitle en BusquedaScreen..."

# Guarda: si ya está corregido, no hacemos nada
if ! grep -q "ev.categoria" "$FILE"; then
  echo "ℹ️  Ya estaba corregido"
  exit 0
fi

sed -i 's/ev\.categoria/ev.groupTitle/g' "$FILE"

echo ""
echo "🔎 Verificando:"
grep -n "ev\.groupTitle" "$FILE" | head -5
echo "---"
if grep -q "ev\.categoria" "$FILE"; then
  echo "⚠️  Todavía queda ev.categoria, revisar manual"
else
  echo "  ✓ Sin referencias a ev.categoria"
fi

echo ""
echo "✅✅✅ Fix 29b completo — BusquedaScreen usa groupTitle"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"