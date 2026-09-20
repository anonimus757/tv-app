#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

echo "📝 Agregando auto-retry + warm-up de cookies al extractor..."

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-retry"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# ── 1) Modificar la función extraer() para agregar warm-up + retry ──
old_extraer = '''    suspend fun extraer(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {

        // 1) Decodificar ?r=base64 si existe
        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
        }

        // 2) Buscar recursivamente
        val visitadas = mutableSetOf<String>()
        val encontradas = buscarRecursivo(urlReal, referer, 0, visitadas, onLog)

        if (encontradas.isEmpty()) {
            onLog("❌ No se encontró m3u8 en el HTML")
            return@withContext null
        }

        onLog("✅ Encontrado: ${encontradas[0].take(90)}")

        // 3) Elegir mejor variante
        val mejor = elegirVariante(encontradas[0], urlReal, onLog) ?: encontradas[0]
        onLog("🎯 Final: ${mejor.take(90)}")
        mejor
    }'''

new_extraer = '''    suspend fun extraer(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {

        // 1) Decodificar ?r=base64 si existe
        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
        }

        // ═══════════════════════════════════════════════════════
        // WARM-UP: primera petición para capturar cookies de sesión
        // Muchos servidores generan el token en la primera visita
        // y lo entregan en la segunda. Esto evita que el usuario
        // tenga que tocar "Refrescar señal" manualmente.
        // ═══════════════════════════════════════════════════════
        try {
            onLog("🔥 Warm-up de cookies...")
            httpGet(urlReal, referer)
        } catch (_: Exception) {}

        // ═══════════════════════════════════════════════════════
        // AUTO-RETRY: hasta 3 intentos automáticos
        // Intento 1 → normal
        // Intento 2 → normal (cookies ya cargadas)
        // Intento 3 → con delay más largo (por si el server tarda)
        // ═══════════════════════════════════════════════════════
        var intento = 1
        val maxIntentos = 3

        while (intento <= maxIntentos) {
            try {
                if (intento > 1) {
                    onLog("🔄 Intento $intento/$maxIntentos...")
                    Thread.sleep(800L * intento)
                }

                val visitadas = mutableSetOf<String>()
                val encontradas = buscarRecursivo(urlReal, referer, 0, visitadas, onLog)

                if (encontradas.isNotEmpty()) {
                    onLog("✅ Encontrado: ${encontradas[0].take(90)}")
                    val mejor = elegirVariante(encontradas[0], urlReal, onLog) ?: encontradas[0]
                    onLog("🎯 Final: ${mejor.take(90)}")
                    return@withContext mejor
                }

                onLog("⚠️ Intento $intento falló")
                intento++
            } catch (e: Exception) {
                onLog("❌ Intento $intento error: ${e.message}")
                intento++
            }
        }

        onLog("❌ No se encontró m3u8 después de $maxIntentos intentos")
        null
    }'''

if old_extraer in content:
    content = content.replace(old_extraer, new_extraer)
    print("✅ auto-retry + warm-up agregado")
elif "WARM-UP: primera petición" in content:
    print("ℹ️  auto-retry ya estaba")
else:
    print("⚠️  No encontré el bloque exacto de extraer()")
    # Intento con regex
    import re
    pattern = r'    suspend fun extraer\(\n.*?\n    \}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_extraer + content[match.end():]
        print("✅ Reemplazado (regex)")
    else:
        print("❌ No se pudo reemplazar")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "WARM-UP: primera petición" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Warm-up de cookies"
grep -q "maxIntentos = 3" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Auto-retry (3 intentos)"

echo ""
echo "✅✅✅ Fix auto-retry aplicado"
echo ""
echo "📌 Qué hace ahora el extractor:"
echo "   1. Warm-up: pide la página 1 vez para capturar cookies"
echo "   2. Intento 1: busca el m3u8 normal"
echo "   3. Si falla → Intento 2 (con cookies cargadas, con 1.6s delay)"
echo "   4. Si falla → Intento 3 (con 2.4s delay)"
echo "   5. Solo si los 3 fallan → pasa a WebView"
echo ""
echo "🎯 Resultado: ya no vas a tener que tocar 'Refrescar señal'"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"