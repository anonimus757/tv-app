#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

GRADLE_FILE="app/build.gradle.kts"

# Guarda: si ya está habilitado, no hacemos nada
if grep -q "buildConfig = true" "$GRADLE_FILE"; then
  echo "ℹ️  buildConfig ya estaba habilitado"
  exit 0
fi

echo "📝 Habilitando buildConfig en $GRADLE_FILE..."

# Caso 1: si está la línea exacta sin punto y coma
if grep -q 'buildFeatures { compose = true }' "$GRADLE_FILE"; then
  sed -i 's/buildFeatures { compose = true }/buildFeatures { compose = true; buildConfig = true }/' "$GRADLE_FILE"
# Caso 2: si está con salto de línea
elif grep -q 'buildFeatures {' "$GRADLE_FILE"; then
  # Insertar buildConfig = true después de la línea de buildFeatures {
  sed -i '/buildFeatures {/a\        buildConfig = true' "$GRADLE_FILE"
fi

echo ""
echo "🔎 Verificando:"
grep -n "buildFeatures\|buildConfig" "$GRADLE_FILE"

echo ""
echo "✅✅✅ Fix 28b completo — BuildConfig habilitado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"