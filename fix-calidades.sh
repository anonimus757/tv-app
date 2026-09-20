#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
cp "$FILE" "$FILE.bak-calidades"

echo "📝 Fix: devolver master playlist en vez de elegir variante..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Modificar extraer() para NO elegir variante
# ═══════════════════════════════════════════════════════════
old_extraer = '''        onLog("✅ Encontrado: ${encontradas[0].take(90)}")

        // 3) Elegir mejor variante
        val mejor = elegirVariante(encontradas[0], urlReal, onLog) ?: encontradas[0]
        val finalLimpio = limpiarUrlFinal(mejor)
        onLog("🎯 Final: ${finalLimpio.take(90)}")
        finalLimpio
    }'''

new_extraer = '''        onLog("✅ Encontrado: ${encontradas[0].take(90)}")

        // FIX CALIDADES: devolvemos el m3u8 tal cual (master o media)
        // ExoPlayer se encarga de elegir la calidad automáticamente (ABR)
        val finalLimpio = limpiarUrlFinal(encontradas[0])
        onLog("🎯 Final: ${finalLimpio.take(90)}")

        // Log de cuántas calidades tiene (informativo)
        try {
            val txt = httpGet(finalLimpio, urlReal)
            if (txt != null) {
                val cantidad = Regex("""#EXT-X-STREAM-INF""").findAll(txt).count()
                if (cantidad > 0) {
                    onLog("📊 Master con $cantidad calidades (adaptive)")
                } else {
                    onLog("📊 Stream único")
                }
            }
        } catch (_: Exception) {}

        finalLimpio
    }'''

if old_extraer in content:
    content = content.replace(old_extraer, new_extraer)
    print("✅ extraer() devuelve master sin elegir variante")
else:
    print("⚠️  No encontré el bloque de extraer()")
    # Buscar variante
    pattern = r'val mejor = elegirVariante\([^\n]+\)[^\n]*\n\s*val finalLimpio = limpiarUrlFinal\(mejor\)'
    match = re.search(pattern, content)
    if match:
        content = content[:match.start()] + '''val finalLimpio = limpiarUrlFinal(encontradas[0])''' + content[match.end():]
        print("✅ Reemplazado (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "FIX CALIDADES" "$FILE" && echo "  ✓ Fix aplicado"
grep -q "Master con.*calidades" "$FILE" && echo "  ✓ Log de calidades"

echo ""
echo "✅✅✅ Fix de calidades aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   ANTES: extractor elegía 1 calidad (la mejor) y descartaba el resto"
echo "   AHORA: devuelve el master playlist completo"
echo "   ExoPlayer lee TODAS las calidades → el selector muestra todas"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"