#!/bin/bash
set -e

GRADLE="app/build.gradle.kts"

echo "📝 Subiendo a v2.1..."
sed -i 's/versionName = "2.0"/versionName = "2.1"/' "$GRADLE"
sed -i 's/versionCode = 3/versionCode = 4/' "$GRADLE"

grep -E "versionCode|versionName" "$GRADLE" | head -3

echo ""
echo "✅ Listo. Ahora compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"
