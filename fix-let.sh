#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-let"

echo "📝 Arreglando el return@let..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el bloque roto de abrirSelectorCalidad
old = '''        // Si hay 1 sola calidad → no tiene sentido el selector
        if (calidades.size <= 1) {
            toast = "Este canal tiene 1 sola calidad"
            return@let
        }

        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }.let { { it() } }'''

new = '''        // Si hay 1 sola calidad → no tiene sentido el selector
        if (calidades.size <= 1) {
            toast = "Este canal tiene 1 sola calidad"
            return@abrirSelectorCalidad
        }

        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }'''

if old in content:
    content = content.replace(old, new)
    print("✅ return@let arreglado")
else:
    # Buscar variante
    print("⚠️  No encontré el bloque exacto, buscando variante...")
    # Intento con regex más flexible
    pattern = r'return@let\n(\s*)\}\n\s*\n\s*calidadesDisponibles = calidades\.sortedByDescending \{ it\.first \}\n\s*mostrarSelectorCalidad = true\n\s*mostrarControles = false\n\s*\}\.let \{ \{ it\(\) \} \}'
    match = re.search(pattern, content)
    if match:
        new_flexible = '''return@abrirSelectorCalidad
        }

        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }'''
        content = content[:match.start()] + new_flexible + content[match.end():]
        print("✅ Arreglado (regex flexible)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "return@let" "$FILE" | xargs -I {} echo "  return@let: {} (debe ser 0)"
grep -q "return@abrirSelectorCalidad" "$FILE" && echo "  ✓ return@abrirSelectorCalidad presente"
grep -c "\.let { { it() } }" "$FILE" | xargs -I {} echo "  .let { { it() } }: {} (debe ser 0)"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"