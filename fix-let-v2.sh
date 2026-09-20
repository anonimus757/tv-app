#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-let-v2"

echo "📝 Reestructurando abrirSelectorCalidad sin return..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el bloque completo de abrirSelectorCalidad y reemplazarlo
pattern = r'    val abrirSelectorCalidad: \(\) -> Unit = \{.*?\n    \}'

new_block = '''    val abrirSelectorCalidad: () -> Unit = {
        val calidades = mutableListOf<Pair<Int, String>>()
        try {
            exoPlayer.currentTracks.groups.forEach { grupo ->
                if (grupo.type == androidx.media3.common.C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until grupo.length) {
                        val formato = grupo.getTrackFormat(i)
                        val altura = formato.height
                        if (altura > 0 && !calidades.any { it.first == altura }) {
                            val label = when {
                                altura >= 2160 -> "4K (${altura}p)"
                                altura >= 1080 -> "Full HD (${altura}p)"
                                altura >= 720 -> "HD (${altura}p)"
                                altura >= 480 -> "SD (${altura}p)"
                                else -> "${altura}p"
                            }
                            calidades.add(altura to label)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        if (calidades.size <= 1) {
            // Solo 1 calidad → no tiene sentido el selector
            toast = "Este canal tiene 1 sola calidad"
        } else {
            calidadesDisponibles = calidades.sortedByDescending { it.first }
            mostrarSelectorCalidad = true
            mostrarControles = false
        }
    }'''

match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + new_block + content[match.end():]
    print("✅ Bloque reestructurado con if/else")
else:
    print("⚠️  No encontré el bloque, buscando variante...")
    # Variante más flexible
    pattern2 = r'val abrirSelectorCalidad: \(\) -> Unit = \{[\s\S]*?\n    \}'
    match2 = re.search(pattern2, content)
    if match2:
        content = content[:match2.start()] + new_block + content[match2.end():]
        print("✅ Reestructurado (regex 2)")
    else:
        print("❌ No se pudo encontrar")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "return@" "$FILE" | xargs -I {} echo "  return@ en el archivo: {}"
grep -q "Solo 1 calidad → no tiene sentido" "$FILE" && echo "  ✓ Bloque reestructurado"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"