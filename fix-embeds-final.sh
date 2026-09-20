#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-final"
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-final"

echo "📝 Aplicando fix final..."

# ═══════════════════════════════════════════════════════════
# FIX 1 — esPaginaDinamica: solo URLs realmente dinámicas
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

old = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    return low.contains(".php") ||
           low.contains("stream=") ||
           low.contains("/live/") ||
           low.contains("/embed/") ||
           low.contains("/player") ||
           low.contains("/canal/") ||
           low.contains("/watch/") ||
           low.contains("?id=") ||
           low.contains("&id=")
}'''

new = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // Solo URLs de sitios que SABEMOS que usan JS dinámico.
    // NO usar .php ni stream= (esos son extraíbles por el extractor estático)
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com") ||
           low.contains("/embed/twitch") ||
           low.contains("/embed/vimeo")
}'''

if old in content:
    content = content.replace(old, new)
    print("✅ esPaginaDinamica limitado a URLs realmente dinámicas")
elif "esPaginaDinamica" in content:
    print("⚠️  esPaginaDinamica existe pero con formato distinto, buscando...")
    import re
    pattern = r'private fun esPaginaDinamica\(url: String\): Boolean \{.*?\n\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new + content[match.end():]
        print("✅ Reemplazado (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# FIX 2 — Reintentos: URL fresca al 2°, no al 3°
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

old = '''                            } else {
                                reintentos++
                                when (reintentos) {
                                    1, 2 -> {
                                        addLog("🔄 Reintento $reintentos/3 (misma URL)")
                                        delay(1000L * reintentos)
                                        exoError = null
                                        reloadTrigger++
                                    }
                                    3 -> {'''

new = '''                            } else {
                                reintentos++
                                when (reintentos) {
                                    1 -> {
                                        addLog("🔄 Reintento 1/3 (misma URL)")
                                        delay(1000L)
                                        exoError = null
                                        reloadTrigger++
                                    }
                                    2, 3 -> {'''

if old in content:
    content = content.replace(old, new)
    # Arreglar el mensaje del log para el 3
    content = content.replace(
        'addLog("🔄 Reintento 3/3 (URL fresca)")',
        'addLog("🔄 Reintento $reintentos/3 (URL fresca)")'
    )
    # Y el path de URL fresca hace falta un else para el caso
    content = content.replace(
        'addLog("❌ URL fresca falló, saltando canal...")',
        'addLog("❌ URL fresca falló, saltando canal...")'
    )
    print("✅ Reintentos: URL fresca desde el 2° intento")
else:
    print("⚠️  No encontré el bloque de reintentos")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# FIX 3 — Limpiar el :443 explícito de las URLs m3u8
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Agregar una función para limpiar URLs
if "private fun limpiarUrlFinal" not in content:
    helper = '''
    /**
     * Limpia una URL final para ExoPlayer:
     * - Quita el :443 explícito en HTTPS (puede causar IO_NETWORK_CONNECTION_FAILED)
     * - Quita el :80 explícito en HTTP
     */
    private fun limpiarUrlFinal(url: String): String {
        return try {
            url
                .replace(":443/", "/")  // HTTPS: quitar :443
                .replace(":80/", "/")    // HTTP: quitar :80
        } catch (_: Exception) { url }
    }

'''
    # Insertar antes de "private fun elegirVariante"
    if "private fun elegirVariante" in content:
        content = content.replace(
            "private fun elegirVariante",
            helper + "private fun elegirVariante",
            1
        )
        print("✅ Función limpiarUrlFinal agregada")
    else:
        print("⚠️  No encontré elegirVariante para insertar limpiarUrlFinal")

# Aplicar limpiarUrlFinal al retorno de extraer()
if "mejor.take(90)" in content and "limpiarUrlFinal(mejor)" not in content:
    # Buscar el return donde devuelve el URL final
    old_return = '''                onLog("🎯 Final: ${mejor.take(90)}")
                mejor'''
    new_return = '''                val finalLimpio = limpiarUrlFinal(mejor)
                onLog("🎯 Final: ${finalLimpio.take(90)}")
                finalLimpio'''

    if old_return in content:
        content = content.replace(old_return, new_return)
        print("✅ limpiarUrlFinal aplicado al retorno")
    else:
        print("⚠️  No encontré el bloque de retorno")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "streamxhd.com" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ esPaginaDinamica limitado"
grep -q "Reintento 1/3 (misma URL)" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Reintentos reordenados"
grep -q "limpiarUrlFinal" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ limpiarUrlFinal agregada"

echo ""
echo "✅✅✅ Fix final aplicado"
echo ""
echo "🎯 Qué cambió:"
echo "   1. esPaginaDinamica ya no atrapa tvf90.com/canal.php (era falso positivo)"
echo "   2. Reintento 2 ya usa URL fresca (antes era el 3)"
echo "   3. URLs con :443 explícito → limpiadas antes de ExoPlayer"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"