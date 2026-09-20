#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

echo "📝 Haciendo EventRepository tolerante a embeds (array o map)..."

# Backup
cp "$PKG_DIR/data/EventRepository.kt" "$PKG_DIR/data/EventRepository.kt.bak"

# Reemplazar solo la parte de parsear embeds con una versión tolerante
python3 << 'PYEOF'
import re

file_path = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(file_path, "r") as f:
    content = f.read()

# Patrón: el bloque actual de parseo de embeds
old_block = '''            @Suppress("UNCHECKED_CAST")
            val embedsRaw = doc.get("embeds") as? List<Map<String, Any?>> ?: emptyList()

            val embeds = embedsRaw.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim())
            }'''

new_block = '''            // Tolerante: acepta embeds como ARRAY de maps, o como UN SOLO map
            val embedsRawAny = doc.get("embeds")
            val embedsList: List<Map<String, Any?>> = when (embedsRawAny) {
                is List<*> -> embedsRawAny.mapNotNull { it as? Map<String, Any?> }
                is Map<*, *> -> listOf(embedsRawAny as Map<String, Any?>)
                else -> emptyList()
            }

            val embeds = embedsList.mapNotNull { m ->
                val nombre = (m["nombre"] as? String)?.takeIf { it.isNotBlank() } ?: "Canal"
                val url = (m["url"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val referer = (m["referer"] as? String) ?: ""
                Embed(nombre, url.trim(), referer.trim())
            }'''

if old_block not in content:
    print("⚠️  No encontré el bloque exacto. Puede que ya esté modificado.")
    print("    Avisame y te ayudo manualmente.")
    exit(1)

content = content.replace(old_block, new_block)

with open(file_path, "w") as f:
    f.write(content)

print("✅ EventRepository actualizado (tolera array y map)")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "Tolerante: acepta embeds" "$PKG_DIR/data/EventRepository.kt" && echo "  ✓ Cambio aplicado"

echo ""
echo "✅✅✅ Fix 28c completo — embeds tolerante a array o map"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"