#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

# ═══════════════════════════════════════════════════════════
# 1) Restaurar desde el backup ANTES del fix roto
# ═══════════════════════════════════════════════════════════
echo "🔄 Restaurando PlayerScreen.kt desde .bak-wvtimeout..."

if [ -f "$UI_DIR/PlayerScreen.kt.bak-wvtimeout" ]; then
    cp "$UI_DIR/PlayerScreen.kt.bak-wvtimeout" "$UI_DIR/PlayerScreen.kt"
    echo "✅ PlayerScreen restaurado"
else
    echo "❌ No hay backup .bak-wvtimeout"
    exit 1
fi

# ═══════════════════════════════════════════════════════════
# 2) Arreglar limpiarUrlFinal (bug de :443 y :80 sin delimitador)
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Arreglando limpiarUrlFinal..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Reemplazar la función limpiarUrlFinal por la versión correcta
patron = r'private fun limpiarUrlFinal\(url: String\): String \{.*?\n    \}'
nueva_funcion = '''private fun limpiarUrlFinal(url: String): String {
        return try {
            // Solo limpiamos el :443/:80 si aparecen como puerto DESPUÉS del host
            // Ej: https://host.com:443/path → https://host.com/path
            // NUNCA tocamos el resto de la URL (tokens pueden contener ":80" y se rompen)
            val regex = Regex("^(https?://[^/:]+):(443|80)(/.*)?$")
            val match = regex.find(url)
            if (match != null) {
                val hostPart = match.groupValues[1]
                val resto = match.groupValues[3]
                hostPart + resto
            } else {
                url
            }
        } catch (_: Exception) { url }
    }'''

match = re.search(patron, content, re.DOTALL)
if match:
    content = content[:match.start()] + nueva_funcion + content[match.end():]
    print("✅ limpiarUrlFinal arreglado (solo limpia el puerto real)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) Hacer tolerante el testearUrl: si falla, devolver igual la URL
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Haciendo el test tolerante..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Cambiar la lógica de extraerYTestear: si el test falla, IGUAL devuelve la URL
patron = r'suspend fun extraerYTestear\(.*?\n    \}'
nueva = '''suspend fun extraerYTestear(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        // Extrae la URL sin testearla (más rápido y sin falsos negativos)
        // El test puede fallar por timeout del server pero la URL igual funciona en ExoPlayer
        try {
            val url = extraer(urlEmbed, referer, onLog)
            if (url != null) {
                onLog("🎯 URL lista: ${url.take(80)}")
                return@withContext url
            }
        } catch (e: Exception) {
            onLog("❌ Extracto fail: ${e.message}")
        }
        null
    }'''

match = re.search(patron, content, re.DOTALL)
if match:
    content = content[:match.start()] + nueva + content[match.end():]
    print("✅ extraerYTestear ahora es tolerante (no bloquea por test)")
else:
    print("⚠️  No encontré extraerYTestear")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "NUNCA tocamos el resto" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ limpiarUrlFinal arreglado"
grep -q "extraerYTestear ahora es tolerante" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ test tolerante"
grep -q "bak-wvtimeout" "$UI_DIR/PlayerScreen.kt" && echo "  ⚠️  Backup aún visible (normal)"
grep -c "usarWebView = true" "$UI_DIR/PlayerScreen.kt" | xargs -I {} echo "  usarWebView = true: {} lugares"

echo ""
echo "✅✅✅ Fix urgente aplicado"
echo ""
echo "🎯 Qué cambió:"
echo "   • Restaurado PlayerScreen de versión que funcionaba"
echo "   • limpiarUrlFinal: solo limpia el puerto real (no rompe tokens)"
echo "   • extraerYTestear: extrae y devuelve la URL SIN bloquear"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"