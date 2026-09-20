#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  exit 1
fi

GRADLE_FILE="app/build.gradle.kts"

if [ ! -f "$GRADLE_FILE" ]; then
  echo "❌ No encuentro $GRADLE_FILE"
  exit 1
fi

# Guarda: si ya está en 23, no hacemos nada
if grep -q "minSdk = 23" "$GRADLE_FILE"; then
  echo "ℹ️  minSdk ya está en 23, no hago nada."
  exit 0
fi

echo "📝 Subiendo minSdk de 21 → 23 en $GRADLE_FILE..."
sed -i 's/minSdk = 21/minSdk = 23/' "$GRADLE_FILE"

echo ""
echo "🔎 Verificando:"
grep -n "minSdk" "$GRADLE_FILE"

echo ""
echo "✅✅✅ Fix 26b completo — minSdk subido a 23 (Android 6.0)"
echo ""
echo "📌 Por qué:"
echo "   Firebase Auth requiere mínimo API 23 (Android 6.0)"
echo "   Android 5.0 (API 21-22) tiene <1% del mercado, cero impacto real"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"