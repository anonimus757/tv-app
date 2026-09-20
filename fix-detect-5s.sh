#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-detect"

echo "📝 Ajustando detector a 5 seg (sin importar el estado)..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Reemplazar el detector viejo por uno que chequee si NO reproduce
# ═══════════════════════════════════════════════════════════

import re

# Encontrar y borrar el detector viejo
patron_viejo = r'\n    // ═+\n    // DETECTOR DE BUFFERING STUCK.*?\n    \}\n'

detector_nuevo = '''
    // ═══════════════════════════════════════════════════════
    // DETECTOR DE "NO REPRODUCE" (5 segundos)
    // Si después de 5 seg ExoPlayer NO está reproduciendo
    // (sin importar el estado: idle, buffering, preparing, error)
    // → auto-refresh silencioso
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosBuffering = 0; return@LaunchedEffect }
        segundosBuffering = 0
        var yaRefresco = false
        delay(5000) // Esperar 5 seg

        // Verificar si ya está reproduciendo
        val reproduciendoOk = try {
            exoPlayer.playbackState == Player.STATE_READY && exoPlayer.isPlaying
        } catch (_: Exception) { false }

        if (!reproduciendoOk && !refrescando && !yaRefresco) {
            yaRefresco = true
            addLog("⏰ No reproduce en 5s → auto-refresh")
            try {
                val fresh = M3u8Extractor.extraerYTestear(
                    embedActual.url, embedActual.referer, addLog
                )
                if (fresh != null) {
                    cookies = M3u8Extractor.cookieString()
                    m3u8Url = fresh
                    addLog("✅ Auto-refresh silencioso OK")
                } else {
                    addLog("⚠️ Auto-refresh no encontró URL")
                }
            } catch (_: Exception) {}
        }

        // Segunda verificación: si a los 5 seg más (total 10 seg) sigue sin reproducir
        delay(5000)
        val reproduciendoOk2 = try {
            exoPlayer.playbackState == Player.STATE_READY && exoPlayer.isPlaying
        } catch (_: Exception) { false }

        if (!reproduciendoOk2 && !refrescando) {
            addLog("⏰ No reproduce en 10s → segundo auto-refresh")
            try {
                val fresh2 = M3u8Extractor.extraerYTestear(
                    embedActual.url, embedActual.referer, addLog
                )
                if (fresh2 != null) {
                    cookies = M3u8Extractor.cookieString()
                    m3u8Url = fresh2
                    addLog("✅ Segundo auto-refresh OK")
                }
            } catch (_: Exception) {}
        }
    }
'''

match = re.search(patron_viejo, content, re.DOTALL)
if match:
    content = content[:match.start()] + detector_nuevo + content[match.end():]
    print("✅ Detector reemplazado (5 seg)")
else:
    # Insertar antes del timer si no encuentra el viejo
    ancla = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''
    if ancla in content:
        content = content.replace(ancla, detector_nuevo + "\n" + ancla, 1)
        print("✅ Detector agregado (nuevo)")
    else:
        print("⚠️  No se pudo insertar el detector")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "No reproduce en 5s" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Detector 5s"
grep -q "No reproduce en 10s" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Segundo detector 10s"

echo ""
echo "✅✅✅ Detector ajustado a 5 segundos"
echo ""
echo "🎯 Cómo funciona ahora:"
echo "   • Tocás canal → analiza + testea + reproduce"
echo "   • Si a los 5 seg NO está reproduciendo → auto-refresh silencioso"
echo "   • Si a los 10 seg sigue sin reproducir → segundo auto-refresh"
echo "   • Usuario no toca nada"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"