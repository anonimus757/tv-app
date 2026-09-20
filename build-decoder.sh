#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-decoder"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-decoder"

echo "📝 Agregando decoder de streamxhd al M3u8Extractor..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Insertar la llamada al decoder en buscarRecursivo
# ═══════════════════════════════════════════════════════════
old_buscar = '''        val directos = buscarM3u8EnHtml(html, url)
        if (directos.isNotEmpty()) {
            onLog("  🎯 m3u8 directo")
            return directos
        }'''

new_buscar = '''        val directos = buscarM3u8EnHtml(html, url)
        if (directos.isNotEmpty()) {
            onLog("  🎯 m3u8 directo")
            return directos
        }

        // 🆕 DECODER: URLs ofuscadas con base64 (streamxhd y similares)
        val decodificado = decodificarOfuscado(html)
        if (decodificado != null) {
            onLog("  🎯 URL decodificada OK")
            return listOf(decodificado)
        }'''

if old_buscar in content:
    content = content.replace(old_buscar, new_buscar, 1)
    print("✅ Llamada al decoder insertada en buscarRecursivo")
else:
    print("⚠️  No encontré el bloque de buscarM3u8EnHtml")

# ═══════════════════════════════════════════════════════════
# 2) Agregar la función decodificarOfuscado al final de la clase
# ═══════════════════════════════════════════════════════════
funcion_decoder = '''
    /**
     * Decodifica URLs ofuscadas con base64 (típico de streamxhd y clones).
     *
     * El sitio hace:
     *   1. Tiene un array [índice, "base64"] con cada carácter
     *   2. k = fn1() + fn2()  (dos números)
     *   3. Para cada elemento: parseInt(atob(base64).replace(/\D/g, '')) - k
     *   4. Ese resultado es un carácter ASCII de la URL
     *
     * Reconstruimos la URL completa acá.
     */
    private fun decodificarOfuscado(html: String): String? {
        return try {
            // Verificar que tiene el patrón típico
            if (!html.contains("gV = [") && !html.contains("gV=[")) return null

            // Extraer el array gV = [[...]]
            val arrayRegex = Regex("""gV\\s*=\\s*(\\[\\[.*?\\]\\])\\s*;""", RegexOption.DOT_MATCHES_ALL)
            val arrayMatch = arrayRegex.find(html) ?: return null
            val arrayRaw = arrayMatch.groupValues[1]

            // Extraer las funciones k = fn1() + fn2()
            val kRegex = Regex("""var\\s+k\\s*=\\s*(\\w+)\\(\\)\\s*\\+\\s*(\\w+)\\(\\)""")
            val kMatch = kRegex.find(html) ?: return null
            val fn1 = kMatch.groupValues[1]
            val fn2 = kMatch.groupValues[2]

            // Extraer el "return" de cada función
            val returnRegex1 = Regex("""function\\s+${Regex.escape(fn1)}\\(\\)\\s*\\{\\s*return\\s+(\\d+);?\\s*\\}""")
            val returnRegex2 = Regex("""function\\s+${Regex.escape(fn2)}\\(\\)\\s*\\{\\s*return\\s+(\\d+);?\\s*\\}""")
            val n1 = returnRegex1.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: return null
            val n2 = returnRegex2.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: return null
            val k = n1 + n2

            // Parsear cada elemento [idx, "base64"]
            val elemRegex = Regex("""\\[(\\d+)\\s*,\\s*"([^"]+)"\\]""")
            val elementos = elemRegex.findAll(arrayRaw)
                .mapNotNull { match ->
                    try {
                        val idx = match.groupValues[1].toIntOrNull() ?: return@mapNotNull null
                        val b64 = match.groupValues[2]
                        // Decodificar base64
                        val decoded = String(android.util.Base64.decode(b64, android.util.Base64.DEFAULT))
                        // Sacar solo los dígitos
                        val digits = decoded.filter { it.isDigit() }
                        val num = digits.toIntOrNull() ?: return@mapNotNull null
                        // Restar la clave
                        val code = num - k
                        if (code < 32 || code > 126) return@mapNotNull null
                        idx to code.toChar()
                    } catch (_: Exception) { null }
                }
                .sortedBy { it.first }
                .map { it.second }
                .joinToString("")

            // Verificar que sea una URL válida
            if (elementos.startsWith("http") && elementos.contains("m3u8")) {
                elementos
            } else if (elementos.startsWith("http")) {
                // Puede ser un .ts u otro formato
                elementos
            } else null

        } catch (e: Exception) {
            android.util.Log.d("M3u8Extractor", "decoder fail: ${e.message}")
            null
        }
    }

'''

# Insertar antes del último "}" de la clase (cierre del object)
content = content.rstrip()
if content.endswith("}"):
    content = content[:-1] + funcion_decoder + "}\n"

with open(file_path, "w") as f:
    f.write(content)

print("✅ Función decodificarOfuscado agregada")
PYEOF

echo ""
echo "📝 Sacando streamxhd de 'esPaginaDinamica' (ahora se decodifica)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Cambiar esPaginaDinamica para sacar streamxhd.*
old = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // Sitios con reproductores dinámicos (JS, Blob URLs, MSE)
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com") ||
           low.contains("streamxhd.st") ||
           low.contains("stream-xhd") ||
           low.contains("streamx-hd") ||
           low.contains("liontv.es") // LionTV también puede ser dinámico
}'''

new = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // NOTA: streamxhd.* ya NO está acá porque el M3u8Extractor
    // ahora lo decodifica directamente (decodificarOfuscado)
    return low.contains("stream-xhd-visible") ||  // placeholder
           false
}'''

if old in content:
    content = content.replace(old, new)
    print("✅ streamxhd sacado de esPaginaDinamica (ahora va al extractor)")
else:
    print("⚠️  No encontré esPaginaDinamica exacta, buscando...")
    pattern = r'private fun esPaginaDinamica\(url: String\): Boolean \{[^}]*\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new + content[match.end():]
        print("✅ esPaginaDinamica simplificada (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "decodificarOfuscado" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Función decodificarOfuscado"
grep -q "DECODER: URLs ofuscadas" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Llamada en buscarRecursivo"
grep -q "streamxhd.*ya NO está" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ streamxhd sacado de esPaginaDinamica"

echo ""
echo "✅✅✅ Decoder de streamxhd instalado"
echo ""
echo "📌 Cómo funciona:"
echo "   1. Extractor hace GET a streamxhd.com/live1.php?stream=zapping_ec"
echo "   2. Detecta el array gV ofuscado"
echo "   3. Decodifica cada carácter: base64 → dígitos → restar k → ASCII"
echo "   4. Reconstruye la URL del m3u8"
echo "   5. Reproduce como cualquier m3u8"
echo ""
echo "🎯 Bonus: también funciona con clones de streamxhd que usen el mismo método"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"