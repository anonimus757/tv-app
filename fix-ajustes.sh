#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"

if [ ! -f "$FILE" ]; then
    echo "❌ No encontré $FILE"
    exit 1
fi

cp "$FILE" "$FILE.bak-proyecto"

echo "📝 Quitando la línea 'Proyecto' de Ajustes..."

# Borrar las 3 líneas del bloque Proyecto (Spacer + FilaInfo)
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# Patrón 1: con Spacer + FilaInfo
old_block = '''            Spacer(Modifier.height(8.dp))
            FilaInfo("Proyecto", "github.com/anonimus757/tv-app")'''

# Patrón 2: sin Spacer (por si quedó distinto)
old_block2 = '''            FilaInfo("Proyecto", "github.com/anonimus757/tv-app")'''

if old_block in content:
    content = content.replace(old_block, "")
    print("✅ Bloque Proyecto eliminado (con Spacer)")
elif old_block2 in content:
    content = content.replace(old_block2, "")
    print("✅ Línea Proyecto eliminada")
else:
    print("⚠️  No encontré la línea exacta, buscando variantes...")
    import re
    # Buscar cualquier línea con "Proyecto" y "github"
    pattern = r'\s*Spacer\(Modifier\.height\(8\.dp\)\)\s*\n\s*FilaInfo\("Proyecto"[^\n]*\n'
    if re.search(pattern, content):
        content = re.sub(pattern, '\n', content)
        print("✅ Eliminado (regex)")
    else:
        pattern2 = r'\s*FilaInfo\("Proyecto"[^\n]*\n'
        if re.search(pattern2, content):
            content = re.sub(pattern2, '\n', content)
            print("✅ Eliminado (regex 2)")
        else:
            print("❌ No se pudo encontrar la línea Proyecto")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -n "Proyecto\|github.com" "$FILE" || echo "  ✓ Ya no hay referencias al Proyecto/GitHub"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"