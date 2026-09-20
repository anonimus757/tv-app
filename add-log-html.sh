#!/bin/bash
set -e

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-loghtml"

echo "📝 Agregando logs detallados del HTML..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Agregar logs del HTML antes del decoder
old = '''        // 🆕 DECODER: URLs ofuscadas con base64 (streamxhd y similares)
        val decodificado = decodificarOfuscado(html)
        if (decodificado != null) {
            onLog("  🎯 URL decodificada OK")
            return listOf(decodificado)
        }'''

new = '''        // 🆕 LOGS DETALLADOS DEL HTML (para debug)
        ExtractorLog.log("📄 HTML primeros 300 chars:")
        ExtractorLog.log(html.take(300).replace("\\n", " "))
        ExtractorLog.log("───")
        ExtractorLog.log("🔍 ¿cloudflare? ${html.contains("cloudflare", true)}")
        ExtractorLog.log("🔍 ¿captcha? ${html.contains("captcha", true)}")
        ExtractorLog.log("🔍 ¿challenge? ${html.contains("challenge", true)}")
        ExtractorLog.log("🔍 ¿window.location? ${html.contains("window.location")}")
        ExtractorLog.log("🔍 ¿meta refresh? ${html.contains("http-equiv=\\"refresh\\"", true)}")
        ExtractorLog.log("🔍 ¿iframe? ${html.contains("<iframe")}")
        ExtractorLog.log("🔍 ¿clappr? ${html.contains("clappr", true)}")
        ExtractorLog.log("🔍 ¿khala? ${html.contains("khala", true)}")
        ExtractorLog.log("🔍 ¿futlivehd? ${html.contains("futlivehd", true)}")

        // Buscar redirect por window.location
        val redirectRegex = Regex("""window\\.location(?:\\.href)?\\s*=\\s*["']([^"']+)["']""")
        val redirectMatch = redirectRegex.find(html)
        if (redirectMatch != null) {
            val nuevaUrl = redirectMatch.groupValues[1]
            ExtractorLog.log("🔀 Redirect detectado: ${nuevaUrl.take(80)}")
            val urlRedirigida = adaptarUrl(nuevaUrl, url)
            if (urlRedirigida != null && urlRedirigida != url) {
                ExtractorLog.log("🔀 Siguiendo redirect...")
                val sub = buscarRecursivo(urlRedirigida, referer, prof + 1, visitadas, onLog)
                if (sub.isNotEmpty()) return sub
            }
        }

        // 🆕 DECODER: URLs ofuscadas con base64 (streamxhd y similares)
        val decodificado = decodificarOfuscado(html)
        if (decodificado != null) {
            onLog("  🎯 URL decodificada OK")
            return listOf(decodificado)
        }'''

if old in content:
    content = content.replace(old, new)
    print("✅ Logs detallados del HTML agregados")
else:
    print("⚠️  No encontré el bloque del decoder")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "HTML primeros 300 chars" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Log del HTML"
grep -q "Redirect detectado" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Detecta redirect"

echo ""
echo "✅✅✅ Logs ampliados"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"