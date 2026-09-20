#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-visible"

echo "📝 Haciendo visible el contador y el auto-refresh..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Detector con contador visible + spinner compartido
# ═══════════════════════════════════════════════════════════

# Borrar el detector viejo
patron_viejo = r'\n    // ═+\n    // DETECTOR DE "NO REPRODUCE".*?\n    \}\n'
content = re.sub(patron_viejo, '\n', content, flags=re.DOTALL)

detector_nuevo = '''
    // ═══════════════════════════════════════════════════════
    // DETECTOR DE "NO REPRODUCE" (5 seg)
    // Muestra contador visible. Si a los 5 seg no reproduce,
    // dispara auto-refresh con el MISMO spinner que manual.
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosBuffering = 0; return@LaunchedEffect }
        segundosBuffering = 0

        // Contador visible de 0 a 5
        for (i in 1..5) {
            delay(1000)
            segundosBuffering = i
            status = "Cargando reproductor... ${i}s"
        }

        // Verificar si ya reproduce
        val reproduciendoOk = try {
            exoPlayer.playbackState == Player.STATE_READY && exoPlayer.isPlaying
        } catch (_: Exception) { false }

        if (!reproduciendoOk && !refrescando) {
            addLog("⏰ No reproduce en 5s → auto-refresh")
            // ⭐ Mostrar el MISMO spinner que cuando tocás manual
            refrescando = true
            try {
                // Esperar un toque para que se vea el spinner
                delay(300)

                val fresh = M3u8Extractor.extraerYTestear(
                    embedActual.url, embedActual.referer, addLog
                )
                if (fresh != null) {
                    cookies = M3u8Extractor.cookieString()
                    m3u8Url = fresh
                    addLog("✅ Auto-refresh silencioso OK")
                    status = "Reproduciendo"
                } else {
                    addLog("⚠️ Auto-refresh no encontró URL")
                    // Fallback: reintentar con la misma
                    reloadTrigger++
                }
            } catch (_: Exception) {
                reloadTrigger++
            } finally {
                // Dejar el spinner un momento visible
                delay(500)
                refrescando = false
                segundosBuffering = 0
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
    content = content.replace(ancla, detector_nuevo + "\n" + ancla, 1)
    print("✅ Detector con contador visible + spinner compartido")
else:
    print("⚠️  No encontré el ancla del timer")

# ═══════════════════════════════════════════════════════════
# 2) Cambiar el texto de "Cargando reproductor..." en EstadoOverlay
# para que muestre los segundos dinámicamente
# ═══════════════════════════════════════════════════════════
# El status ya se actualiza desde el detector. Solo verificamos que
# el EstadoOverlay lo lea del state correcto.

# Si el EstadoOverlay recibe el status como parámetro, ok. Si no, hay que pasarlo.
# Buscar "EstadoOverlay(" en el código
if "EstadoOverlay(" in content:
    # Verificar que reciba status
    if "status = status" in content or "status = status," in content:
        print("✅ EstadoOverlay ya recibe status dinámico")
    else:
        # Actualizar la llamada
        content = re.sub(
            r'EstadoOverlay\(\s*\n(\s*)error = exoError,',
            r'EstadoOverlay(\n\1error = exoError,\n\1status = status,',
            content
        )
        print("✅ status pasado a EstadoOverlay")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "Cargando reproductor... \${i}s" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Contador visible (5s)"
grep -q "No reproduce en 5s" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Detector de 5s"
grep -q "refrescando = true" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Spinner compartido con manual"

echo ""
echo "✅✅✅ Contador y auto-refresh visibles"
echo ""
echo "🎯 Ahora vas a ver:"
echo "   'Cargando reproductor... 1s'"
echo "   'Cargando reproductor... 2s'"
echo "   'Cargando reproductor... 3s'"
echo "   'Cargando reproductor... 4s'"
echo "   'Cargando reproductor... 5s'"
echo "   ┌────────────────────────┐"
echo "   │   🔄 Refrescando...    │  ← mismo spinner que manual"
echo "   │  Buscando URL fresca   │"
echo "   └────────────────────────┘"
echo "   ✅ Reproduciendo"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"