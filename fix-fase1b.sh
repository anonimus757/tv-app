#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-fix-fase1b"

echo "📝 Arreglando errores de Fase 1b..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) QUITAR el buffer adaptativo (no se puede en runtime)
# ═══════════════════════════════════════════════════════════
patron_buffer = r'\n    // ═+\n    // 🆕 FASE 1b: BUFFER ADAPTATIVO.*?\n    \}\n'
content = re.sub(patron_buffer, '\n', content, flags=re.DOTALL)
print("✅ Buffer adaptativo quitado (no soportado en runtime)")

# ═══════════════════════════════════════════════════════════
# 2) ARREGLAR el SelectorCalidadItem mal ubicado
# ═══════════════════════════════════════════════════════════

# Primero: sacar el componente mal puesto del final del archivo
# El componente tiene "Modifier 'private' is not applicable"
patron_mal = r'\n// ═+\n// 🆕 FASE 1b: Item del selector de calidad.*?\n\}\n\}\n$'

match = re.search(patron_mal, content, re.DOTALL)
if match:
    # Extraer el componente completo
    componente_extraido = match.group(0)
    # Quitarlo del final
    content = content[:match.start()]

    # Limpiar el componente (quitar el "}\n}" extra del final)
    componente_limpio = componente_extraido.rstrip()
    if componente_limpio.endswith("}\n}"):
        componente_limpio = componente_limpio[:-2].rstrip() + "\n"

    # Agregarlo correctamente al final del archivo (fuera de todo)
    content = content.rstrip() + "\n" + componente_limpio + "\n"
    print("✅ SelectorCalidadItem reubicado al final del archivo")
else:
    print("⚠️  No encontré el SelectorCalidadItem mal ubicado")

# ═══════════════════════════════════════════════════════════
# 3) Verificar que no queden restos
# ═══════════════════════════════════════════════════════════
# Si todavía hay múltiples "}\n}" al final, limpiar
content = re.sub(r'\}\n\}\n*$', '}\n', content)

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "BUFFER ADAPTATIVO" "$FILE" | xargs -I {} echo "  Buffer adaptativo: {} (debe ser 0)"
grep -c "private fun SelectorCalidadItem" "$FILE" | xargs -I {} echo "  SelectorCalidadItem: {} (debe ser 1)"
tail -3 "$FILE"

echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"