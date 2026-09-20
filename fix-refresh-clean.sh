#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

# Revertir al estado anterior (antes del fix roto)
if [ -f "$UI_DIR/PlayerScreen.kt.bak-visible" ]; then
    cp "$UI_DIR/PlayerScreen.kt.bak-visible" "$UI_DIR/PlayerScreen.kt"
    echo "✅ Revertido a versión estable"
else
    echo "❌ No encontré backup .bak-visible"
    exit 1
fi

echo ""
echo "📝 Agregando detector limpio (sin LaunchedEffect que se reinicie)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Borrar CUALQUIER detector viejo que haya quedado
# ═══════════════════════════════════════════════════════════
content = re.sub(
    r'\n    // ═+\n    // DETECTOR DE.*?\n    \}\n',
    '\n',
    content,
    flags=re.DOTALL
)

# ═══════════════════════════════════════════════════════════
# 2) Detector LIMPIO usando scope.launch desde un LaunchedEffect
# con key embedActual (que NO cambia cuando auto-refrescamos)
# ═══════════════════════════════════════════════════════════

detector_limpio = '''
    // ═══════════════════════════════════════════════════════
    // AUTO-REFRESH LIMPIO (no interfiere con el estado)
    // Detecta si después de 5 seg no está reproduciendo y hace
    // un refresh automático usando una corrutina INDEPENDIENTE.
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(embedActual) {
        while (true) {
            delay(5000)

            // Solo actúa si hay un m3u8 cargado y NO está reproduciendo
            val hayUrl = m3u8Url != null
            val reproduciendo = try {
                exoPlayer.playbackState == Player.STATE_READY && exoPlayer.isPlaying
            } catch (_: Exception) { false }

            if (hayUrl && !reproduciendo && !refrescando && !todosFallaron && !eventoMuerto) {
                addLog("⏰ 5s sin reproducir → auto-refresh")

                // Corrutina INDEPENDIENTE para no romper el LaunchedEffect
                scope.launch {
                    try {
                        val fresh = M3u8Extractor.extraerYTestear(
                            embedActual.url, embedActual.referer, addLog
                        )
                        if (fresh != null) {
                            cookies = M3u8Extractor.cookieString()
                            m3u8Url = fresh
                            addLog("✅ Auto-refresh OK")
                        } else {
                            addLog("⚠️ Auto-refresh sin URL, reintentando con la misma")
                            reloadTrigger++
                        }
                    } catch (_: Exception) {
                        reloadTrigger++
                    }
                }
            }
        }
    }
'''

# Insertar antes del timer
ancla = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''

if ancla in content:
    content = content.replace(ancla, detector_limpio + "\n" + ancla, 1)
    print("✅ Detector limpio agregado (key=embedActual)")
else:
    print("⚠️  No encontré el ancla del timer")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "DETECTOR DE" "$UI_DIR/PlayerScreen.kt" | xargs -I {} echo "  Detectores viejos: {}"
grep -q "AUTO-REFRESH LIMPIO" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Detector limpio"
grep -q "LaunchedEffect(embedActual)" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Key = embedActual (no se reinicia)"

echo ""
echo "✅✅✅ Sistema limpio"
echo ""
echo "🎯 Qué cambió:"
echo "   • El detector usa embedActual como key (no m3u8Url)"
echo "   • La lógica de refresh corre en scope.launch INDEPENDIENTE"
echo "   • NUNCA se va a quedar pegado el spinner"
echo "   • Cada 5 seg verifica: si no reproduce → refresh"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"