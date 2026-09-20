#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-fase3"

echo "📝 Agregando gestos de swipe en el reproductor..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Import de detectVerticalDragGestures
if "import androidx.compose.foundation.gestures.detectVerticalDragGestures" not in content:
    content = content.replace(
        "import androidx.compose.foundation.gestures.detectHorizontalDragGestures",
        "import androidx.compose.foundation.gestures.detectHorizontalDragGestures\nimport androidx.compose.foundation.gestures.detectVerticalDragGestures"
    )
    print("✅ Import detectVerticalDragGestures")

# 2) Agregar pointerInput para gestos verticales ANTES del pointerInput de tap
# El pointerInput actual maneja: horizontal (panel) y tap (controles)
# Agregamos vertical (cambiar canal + volumen) en un nuevo pointerInput

gestos_code = '''            // ═══════════════════════════════════════════════════════
            // 🆕 FASE 3: GESTOS DE SWIPE EN CELU
            // - Swipe ↑↓ zona izquierda (30%) → cambiar canal
            // - Swipe ↑↓ zona derecha (70%) → volumen
            // ═══════════════════════════════════════════════════════
            .pointerInput(panelAbierto, evento.embeds.size) {
                if (panelAbierto) return@pointerInput

                var totalDragY = 0f
                var xInicial = 0f

                detectVerticalDragGestures(
                    onDragStart = { offset ->
                        totalDragY = 0f
                        xInicial = offset.x
                    },
                    onDragEnd = {
                        // Detectar swipe según zona
                        if (kotlin.math.abs(totalDragY) > 120f) {
                            // Zona izquierda (primeros 30% de la pantalla) → cambiar canal
                            val anchoPantalla = size.width.toFloat()
                            val esZonaIzquierda = xInicial < anchoPantalla * 0.30f

                            if (esZonaIzquierda) {
                                // Cambiar canal
                                if (totalDragY > 0) {
                                    // Swipe hacia abajo → canal anterior
                                    val idxActual = evento.embeds.indexOfFirst { it.url == embedActual.url }
                                    if (idxActual > 0) {
                                        addLog("👆 Swipe ↓ → canal anterior")
                                        embedActual = evento.embeds[idxActual - 1]
                                    } else {
                                        toast = "Primer canal"
                                    }
                                } else {
                                    // Swipe hacia arriba → canal siguiente
                                    val idxActual = evento.embeds.indexOfFirst { it.url == embedActual.url }
                                    if (idxActual >= 0 && idxActual < evento.embeds.size - 1) {
                                        addLog("👇 Swipe ↑ → canal siguiente")
                                        embedActual = evento.embeds[idxActual + 1]
                                    } else {
                                        toast = "Último canal"
                                    }
                                }
                            } else {
                                // Zona derecha → volumen
                                if (totalDragY > 0) {
                                    // Swipe hacia abajo → bajar volumen
                                    val nuevo = (volumen - 0.15f).coerceAtLeast(0f)
                                    volumen = nuevo
                                    toast = "🔉 ${(nuevo * 100).toInt()}%"
                                } else {
                                    // Swipe hacia arriba → subir volumen
                                    val nuevo = (volumen + 0.15f).coerceAtMost(1f)
                                    volumen = nuevo
                                    toast = "🔊 ${(nuevo * 100).toInt()}%"
                                }
                            }
                        }
                        totalDragY = 0f
                    },
                    onVerticalDrag = { change, dragAmount ->
                        change.consume()
                        totalDragY += dragAmount
                    }
                )
            }
'''

# Insertar el nuevo pointerInput ANTES del pointerInput de tap actual
ancla = '''            .pointerInput(panelAbierto) {
                detectTapGestures(
                    onTap = {'''

if ancla in content and "GESTOS DE SWIPE EN CELU" not in content:
    content = content.replace(ancla, gestos_code + ancla, 1)
    print("✅ Gestos de swipe agregados")

# 3) Modificar onDoubleTap para hacer seek
old_doubletap = '''                    onDoubleTap = { mostrarControles = true; zona = ZonaUI.VIDEO }'''
new_doubletap = '''                    onDoubleTap = { offset ->
                        mostrarControles = true
                        zona = ZonaUI.VIDEO
                        // 🆕 FASE 3: Doble tap izq → retroceder 10s, der → adelantar 10s
                        try {
                            val anchoPantalla = size.width.toFloat()
                            val esIzquierda = offset.x < anchoPantalla / 2
                            if (esIzquierda) {
                                val nuevaPos = (exoPlayer.currentPosition - 10000L).coerceAtLeast(0L)
                                exoPlayer.seekTo(nuevaPos)
                                toast = "⏪ -10 seg"
                            } else {
                                val nuevaPos = exoPlayer.currentPosition + 10000L
                                exoPlayer.seekTo(nuevaPos)
                                toast = "⏩ +10 seg"
                            }
                        } catch (_: Exception) {}
                    }'''

if old_doubletap in content:
    content = content.replace(old_doubletap, new_doubletap)
    print("✅ Doble tap → seek")
else:
    print("⚠️  No encontré el onDoubleTap")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "GESTOS DE SWIPE EN CELU" "$FILE" && echo "  ✓ Gestos de swipe"
grep -q "detectVerticalDragGestures" "$FILE" && echo "  ✓ detectVerticalDragGestures"
grep -q "Swipe ↓ → canal anterior" "$FILE" && echo "  ✓ Cambio de canal por swipe"

echo ""
echo "✅✅✅ FASE 3 completo — Gestos en celular"
echo ""
echo "📌 Cómo usar (en celu):"
echo "   • Swipe ↑↓ zona IZQUIERDA (30%) → cambiar canal"
echo "   • Swipe ↑↓ zona DERECHA (70%) → volumen"
echo "   • Doble tap IZQ → retroceder 10 seg"
echo "   • Doble tap DER → adelantar 10 seg"
echo "   • Swipe ← → abrir/cerrar panel (ya existía)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"