#!/bin/bash
set -e

GRADLE="app/build.gradle.kts"

echo "📝 Subiendo a v3.1..."

# Actualizar versionName
if grep -q 'versionName = "3.0"' "$GRADLE"; then
    sed -i 's/versionName = "3.0"/versionName = "3.1"/' "$GRADLE"
    echo "✅ versionName: 3.0 → 3.1"
elif grep -q 'versionName = "2.' "$GRADLE"; then
    sed -i 's/versionName = "2\..*"/versionName = "3.1"/' "$GRADLE"
    echo "✅ versionName actualizado a 3.1"
fi

# Actualizar versionCode (incrementar)
if grep -q 'versionCode = 5' "$GRADLE"; then
    sed -i 's/versionCode = 5/versionCode = 6/' "$GRADLE"
    echo "✅ versionCode: 5 → 6"
elif grep -q 'versionCode = 4' "$GRADLE"; then
    sed -i 's/versionCode = 4/versionCode = 6/' "$GRADLE"
    echo "✅ versionCode: 4 → 6"
fi

echo ""
echo "🔎 Verificando:"
grep -E "versionCode|versionName" "$GRADLE"
