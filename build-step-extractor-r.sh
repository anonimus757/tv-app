#!/bin/bash
set -e

EXTRACTOR="app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
BACKUP="${EXTRACTOR}.bak.$(date +%s)"

[ ! -f "$EXTRACTOR" ] && { echo "❌ No existe $EXTRACTOR"; exit 1; }
cp "$EXTRACTOR" "$BACKUP"
echo "✅ Backup: $BACKUP"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Inyectar helper decodificarWrapperR justo después de "object M3u8Extractor {"
helper = '''
    /**
     * Si la URL es un wrapper tipo futbollibrefullhd.org/embed/eventos.html?r=BASE64,
     * decodifica el parámetro "r" y devuelve la URL real interna.
     * Devuelve null si no aplica o si la decodificación falla.
     */
    private fun decodificarWrapperR(url: String): String? {
        return try {
            if (!url.contains("?r=") && !url.contains("&r=")) return null
            val idx = url.indexOf("r=")
            if (idx < 0) return null
            val desdeR = url.substring(idx + 2)
            val b64 = desdeR.substringBefore('&').substringBefore('#')
            if (b64.isBlank()) return null
            val decoded = String(
                android.util.Base64.decode(
                    b64,
                    android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
                )
            )
            if (decoded.startsWith("http://") || decoded.startsWith("https://")) decoded else null
        } catch (e: Exception) {
            null
        }
    }

'''

# Insertar helper después de la llave de apertura del object
match = re.search(r'object\s+M3u8Extractor\s*\{', c)
if not match:
    print("❌ No encontré 'object M3u8Extractor {'")
    raise SystemExit(1)
c = c[:match.end()] + "\n" + helper + c[match.end():]

# 2. Inyectar el atajo AL PRINCIPIO de extraerYTestear, antes del for
pattern = r'(suspend\s+fun\s+extraerYTestear\s*\(\s*urlEmbed:\s*String,\s*referer:\s*String,\s*onLog:\s*\(String\)\s*->\s*Unit\s*\)\s*:\s*String\?\s*=\s*withContext\(Dispatchers\.IO\)\s*\{)'
m2 = re.search(pattern, c)
if not m2:
    print("❌ No encontré la firma exacta de extraerYTestear")
    raise SystemExit(1)

atajo = '''

        // ⬇️ ATAJO: si la URL es un wrapper con parámetro r=BASE64, usar la URL real directa
        decodificarWrapperR(urlEmbed)?.let { urlReal ->
            onLog("🎯 Wrapper r= detectado → URL real: $urlReal")
            val ok = testearUrl(urlReal, referer)
            if (ok) {
                onLog("✅ URL wrapper verificada OK")
                return@withContext urlReal
            } else {
                onLog("⚠️ URL wrapper falló, siguiendo con extractor normal...")
            }
        }
'''

c = c[:m2.end()] + atajo + c[m2.end():]

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ M3u8Extractor.kt actualizado con decodificador r=BASE64 + atajo en extraerYTestear")
PYEOF

echo ""
echo "✅✅✅ Paso extractor-r completo"
echo ""
echo "Compilá con:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
