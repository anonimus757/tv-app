#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE_EXTRACTOR="$DATA_DIR/M3u8Extractor.kt"
FILE_PLAYER="$UI_DIR/PlayerScreen.kt"

cp "$FILE_EXTRACTOR" "$FILE_EXTRACTOR.bak-universal"
cp "$FILE_PLAYER" "$FILE_PLAYER.bak-universal"

echo "📝 Paso 1 — Simplificando M3u8Extractor (sin lista de dominios)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# 1) Quitar la lista de dominios (ya no la necesitamos)
pattern = r'\n    // ═+\n    // DOMINIOS QUE REQUIEREN WEBVIEW.*?\)\n'
content = re.sub(pattern, '\n', content, flags=re.DOTALL)

# 2) Quitar la detección de dominios en extraer()
pattern2 = r'\n        // ═+\n        // Si el dominio \(o el embed original\) requiere WebView,.*?return@withContext null\n        \}\n'
content = re.sub(pattern2, '\n', content, flags=re.DOTALL)

# 3) Quitar la detección en extraerYTestear()
pattern3 = r'\n        // ═+\n        // Si el dominio requiere WebView → null rápido.*?return@withContext null\n        \}\n'
content = re.sub(pattern3, '\n', content, flags=re.DOTALL)

with open(file_path, "w") as f:
    f.write(content)
print("✅ Lista de dominios eliminada")
PYEOF

echo ""
echo "📝 Paso 2 — Bajar timeouts para que sea más rápido..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Bajar timeout del cliente HTTP de 10s a 4s
content = content.replace(
    ".connectTimeout(10, TimeUnit.SECONDS)\n            .readTimeout(10, TimeUnit.SECONDS)",
    ".connectTimeout(4, TimeUnit.SECONDS)\n            .readTimeout(4, TimeUnit.SECONDS)"
)

# Bajar el timeout total de extraerYTestear de 12s a 6s
content = content.replace(
    "if (System.currentTimeMillis() - inicio > 12000) {",
    "if (System.currentTimeMillis() - inicio > 6000) {"
)

# Bajar timeout individual de 5s a 3s
content = content.replace(
    "withTimeoutOrNull(5000L) {",
    "withTimeoutOrNull(3000L) {"
)

with open(file_path, "w") as f:
    f.write(content)
print("✅ Timeouts reducidos (4s cliente, 6s total, 3s por intento)")
PYEOF

echo ""
echo "📝 Paso 3 — PlayerScreen: activar WebView más rápido..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Bajar el timeout de extracción en PlayerScreen de 15s a 8s
content = content.replace(
    "val url = withTimeoutOrNull(15000L) {",
    "val url = withTimeoutOrNull(8000L) {"
)

# Bajar el timeout del WebView de 25s a 20s
content = content.replace(
    "// Esperar hasta 25 segundos a que capture el m3u8 del WebView invisible\n            delay(25000)",
    "// Esperar hasta 20 segundos a que capture el m3u8 del WebView invisible\n            delay(20000)"
)

with open(file_path, "w") as f:
    f.write(content)
print("✅ Timeouts del PlayerScreen reducidos")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "DOMINIOS_REQUIEREN_WEBVIEW" "$FILE_EXTRACTOR" && echo "  ⚠️ Todavía hay lista de dominios" || echo "  ✓ Lista de dominios eliminada"
grep -q "connectTimeout(4" "$FILE_EXTRACTOR" && echo "  ✓ Timeout HTTP: 4s"
grep -q "withTimeoutOrNull(8000L)" "$FILE_PLAYER" && echo "  ✓ Timeout extracción PlayerScreen: 8s"
grep -q "delay(20000)" "$FILE_PLAYER" && echo "  ✓ Timeout WebView: 20s"

echo ""
echo "✅✅✅ Fix universal aplicado"
echo ""
echo "📌 Cómo funciona ahora:"
echo "   1. Tocás cualquier canal"
echo "   2. Extractor estático intenta extraer (máx 6 seg)"
echo "   3. Si encuentra m3u8 → reproduce AL TOQUE"
echo "   4. Si NO encuentra → WebView automático (invisible)"
echo "   5. WebView ejecuta el JS y captura el .m3u8"
echo "   6. Reproduce ✅"
echo ""
echo "🎯 Funciona con CUALQUIER embed, sin listas."
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"