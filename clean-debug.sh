#!/bin/bash
set -e

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-clean"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-clean"

echo "🧹 Limpieza 1 — Eliminando ExtractorLog.kt..."
rm -f "$DATA_DIR/ExtractorLog.kt"
echo "✅ ExtractorLog.kt eliminado"

echo ""
echo "🧹 Limpieza 2 — Sacando logs y decodificador del M3u8Extractor..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# 1) Sacar todos los ExtractorLog.log()
content = re.sub(r'\n\s*ExtractorLog\.log\([^\n]*\)', '', content)

# 2) Sacar ExtractorLog.limpiar()
content = re.sub(r'\n\s*ExtractorLog\.limpiar\(\)', '', content)

# 3) Sacar la función decodificarOfuscado completa
pattern = r'\n    /\*\*\n     \* Decodifica URLs ofuscadas.*?\n    \}\n'
content = re.sub(pattern, '\n', content, flags=re.DOTALL)

# 4) Sacar los logs detallados del HTML que agregamos
content = re.sub(
    r'\n        // 🆕 LOGS DETALLADOS DEL HTML.*?ExtractorLog\.log\("🔍 ¿script src\? \$\{html\.contains\("<script"\)\}"\)',
    '',
    content,
    flags=re.DOTALL
)

# 5) Sacar la búsqueda de gV y window.location que solo era para debug
content = re.sub(
    r'\n        // Buscar "gV" en cualquier parte del HTML.*?(?=\n\n        // 🆕 DECODER|\n        // Verificar que tiene el patrón)',
    '',
    content,
    flags=re.DOTALL
)

# 6) Sacar la llamada al decoder
content = re.sub(
    r'\n        // 🆕 DECODER: URLs ofuscadas con base64.*?return listOf\(decodificado\)\n        \}',
    '',
    content,
    flags=re.DOTALL
)

# 7) Sacar la búsqueda de redirect (que solo era para debug)
content = re.sub(
    r'\n        // Buscar redirect por window\.location.*?if \(sub\.isNotEmpty\(\)\) return sub\n            \}\n        \}',
    '',
    content,
    flags=re.DOTALL
)

# 8) Limpiar líneas vacías múltiples
content = re.sub(r'\n{3,}', '\n\n', content)

with open(file_path, "w") as f:
    f.write(content)
print("✅ M3u8Extractor limpio")
PYEOF

echo ""
echo "🧹 Limpieza 3 — Sacando botón LOG y panel del PlayerScreen..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Sacar import de ExtractorLog
content = re.sub(r'\nimport com\.anonimus757\.tvapp\.data\.ExtractorLog', '', content)

# 2) Sacar el estado mostrarLogExtractor
content = re.sub(r'\n    var mostrarLogExtractor by remember \{ mutableStateOf\(false\) \}', '', content)

# 3) Sacar el botón + panel del LOG (desde el comentario "🐛 BOTÓN DE LOG" hasta antes del cierre del Box)
pattern = r'\n        // ═+\n        // 🐛 BOTÓN DE LOG DEL EXTRACTOR.*?\n        \}\n    \}\n\}'
match = re.search(pattern, content, re.DOTALL)
if match:
    content = content[:match.start()] + '\n    }\n}\n' + content[match.end():]
    print("✅ Botón LOG + panel eliminados")
else:
    print("⚠️  No encontré el bloque del LOG, buscando variante...")
    # Intento más flexible
    pattern2 = r'\n        // 🐛 BOTÓN DE LOG.*?(?=\n    \}\n\})'
    match2 = re.search(pattern2, content, re.DOTALL)
    if match2:
        content = content[:match2.start()] + content[match2.end():]
        print("✅ Botón LOG eliminado (variante)")

# 4) Limpiar líneas vacías
content = re.sub(r'\n{3,}', '\n\n', content)

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🧹 Limpieza 4 — Simplificando esPaginaDinamica..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

old = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // NOTA: streamxhd.* ya NO está acá porque el M3u8Extractor
    // ahora lo decodifica directamente (decodificarOfuscado)
    return low.contains("stream-xhd-visible") ||  // placeholder
           false
}'''

new = '''private fun esPaginaDinamica(url: String): Boolean {
    // Ya no usamos WebView para páginas dinámicas.
    // Los embeds que andan (Futbollibre, Pelota Libre, LionTV) se extraen
    // directo con el M3u8Extractor.
    return false
}'''

if old in content:
    content = content.replace(old, new)
    print("✅ esPaginaDinamica simplificada")
else:
    # Buscar variante
    pattern = r'private fun esPaginaDinamica\(url: String\): Boolean \{[^}]*\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new + content[match.end():]
        print("✅ Simplificada (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ ! -f "$DATA_DIR/ExtractorLog.kt" ] && echo "  ✓ ExtractorLog.kt eliminado"
grep -c "ExtractorLog" "$DATA_DIR/M3u8Extractor.kt" | xargs -I {} echo "  ExtractorLog en M3u8Extractor: {} (debe ser 0)"
grep -c "ExtractorLog" "$UI_DIR/PlayerScreen.kt" | xargs -I {} echo "  ExtractorLog en PlayerScreen: {} (debe ser 0)"
grep -c "mostrarLogExtractor" "$UI_DIR/PlayerScreen.kt" | xargs -I {} echo "  mostrarLogExtractor: {} (debe ser 0)"
grep -c "decodificarOfuscado" "$DATA_DIR/M3u8Extractor.kt" | xargs -I {} echo "  decodificarOfuscado: {} (debe ser 0)"

echo ""
echo "✅✅✅ Limpieza completa"
echo ""
echo "📌 Qué se sacó:"
echo "   🗑️ ExtractorLog.kt"
echo "   🗑️ Botón 🐛 LOG del reproductor"
echo "   🗑️ Panel de log"
echo "   🗑️ Función decodificarOfuscado()"
echo "   🗑️ Logs de debug del HTML"
echo "   🗑️ esPaginaDinamica simplificada"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"