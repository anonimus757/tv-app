#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-fix-items"

echo "📝 Corrigiendo llamada a items()..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Corregir: usar items() normal en vez de androidx.compose.foundation.lazy.items()
old = '''                    androidx.compose.foundation.lazy.items(logsDiagnostico.size) { i ->'''

new = '''                    items(logsDiagnostico.size) { i ->'''

if old in content:
    content = content.replace(old, new)
    print("✅ Corregido: items() normal")
else:
    print("⚠️  No encontré la línea exacta")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "androidx.compose.foundation.lazy.items(" "$FILE" | xargs -I {} echo "  llamadas incorrectas restantes: {}"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"