#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-def"
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-def"

echo "📝 FIX DEFINITIVO..."

# ═══════════════════════════════════════════════════════════
# FIX 1 — limpiarUrlFinal: hacerlo SÍ o SÍ
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# 1) Primero, eliminar la versión vieja de limpiarUrlFinal si existe
import re
content = re.sub(
    r'\n    /\*\*\n     \* Limpia una URL final.*?\n    \}\n',
    '\n',
    content,
    flags=re.DOTALL
)

# 2) Agregar la versión nueva y robusta
if "private fun limpiarUrlFinal" not in content:
    helper = '''
    /**
     * Limpia una URL final antes de pasarla a ExoPlayer.
     * Quita el :443 explícito (rompe ExoPlayer con IO_NETWORK_CONNECTION_FAILED)
     * y el :80 explícito.
     */
    private fun limpiarUrlFinal(url: String): String {
        return url
            .replace(":443/", "/")
            .replace(":80/", "/")
            .replace(":443?", "?")
            .replace(":80?", "?")
            .replace(":443", "")
            .replace(":80", "")
    }

'''
    # Insertar antes de la última función del archivo (buscar elegirVariante)
    if "private fun elegirVariante" in content:
        content = content.replace(
            "private fun elegirVariante",
            helper + "private fun elegirVariante",
            1
        )
        print("✅ limpiarUrlFinal agregada")
    else:
        # Fallback: agregar al final de la clase
        content = content.rstrip() + "\n" + helper + "\n}\n"
        print("✅ limpiarUrlFinal agregada al final")

# 3) Aplicar limpiarUrlFinal a TODOS los returns de extraer()
# Buscar la línea "onLog("🎯 Final: ...")" y forzar limpieza
old_pattern1 = '''                onLog("🎯 Final: ${mejor.take(90)}")
                mejor'''
new_pattern1 = '''                val finalLimpio = limpiarUrlFinal(mejor)
                onLog("🎯 Final: ${finalLimpio.take(90)}")
                finalLimpio'''

if old_pattern1 in content:
    content = content.replace(old_pattern1, new_pattern1)
    print("✅ limpiarUrlFinal aplicado al return (patrón 1)")
else:
    # Buscar variante
    old_pattern2 = '''            onLog("🎯 Final: ${mejor.take(90)}")
            mejor'''
    new_pattern2 = '''            val finalLimpio = limpiarUrlFinal(mejor)
            onLog("🎯 Final: ${finalLimpio.take(90)}")
            finalLimpio'''
    if old_pattern2 in content:
        content = content.replace(old_pattern2, new_pattern2)
        print("✅ limpiarUrlFinal aplicado al return (patrón 2)")
    else:
        # Último intento: regex
        pattern = r'onLog\("🎯 Final: \$\{mejor\.take\(90\)\}"\)\s*\n\s*mejor'
        if re.search(pattern, content):
            content = re.sub(
                pattern,
                'val finalLimpio = limpiarUrlFinal(mejor)\n                onLog("🎯 Final: ${finalLimpio.take(90)}")\n                finalLimpio',
                content
            )
            print("✅ limpiarUrlFinal aplicado (regex)")
        else:
            print("⚠️  No se pudo aplicar limpiarUrlFinal al return")

# 4) También limpiar en elegirVariante (por si acaso)
if "return url_m3u8" in content and "limpiarUrlFinal(url_m3u8)" not in content:
    content = content.replace("return url_m3u8, \"media\"", "return limpiarUrlFinal(url_m3u8), \"media\"")
    content = content.replace("return url_m3u8, \"\"", "return limpiarUrlFinal(url_m3u8), \"\"")
    content = content.replace("return url_m3u8, \"?\"", "return limpiarUrlFinal(url_m3u8), \"?\"")
    print("✅ limpiarUrlFinal aplicado en elegirVariante")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# FIX 2 — Reintentos: si error de red → URL fresca directo
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Detectar el bloque del onPlayerError y modificar la lógica
old_block = '''                            } else {
                                reintentos++
                                when (reintentos) {
                                    1 -> {
                                        addLog("🔄 Reintento 1/3 (misma URL)")
                                        delay(1000L)
                                        exoError = null
                                        reloadTrigger++
                                    }
                                    2, 3 -> {'''

new_block = '''                            } else {
                                reintentos++
                                when (reintentos) {
                                    1 -> {
                                        // FIX: si es error de RED, sacar URL fresca directo.
                                        // No perder tiempo con la misma URL porque ya sabemos que falla.
                                        val esErrorRed = exoError?.contains("IO_NETWORK") == true ||
                                                         exoError?.contains("NETWORK_CONNECTION") == true
                                        if (esErrorRed) {
                                            addLog("🔄 Error de red → URL fresca directo")
                                        } else {
                                            addLog("🔄 Reintento 1/3 (misma URL)")
                                        }
                                        delay(800L)
                                        val fresh = try {
                                            M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                                        } catch (ex: Exception) { null }
                                        if (fresh != null) {
                                            cookies = M3u8Extractor.cookieString()
                                            exoError = null
                                            m3u8Url = fresh
                                        } else {
                                            exoError = null
                                            reloadTrigger++
                                        }
                                    }
                                    2, 3 -> {'''

if old_block in content:
    content = content.replace(old_block, new_block)
    print("✅ Reintentos: URL fresca directo si error de red")
else:
    print("⚠️  No encontré el bloque de reintentos exacto, buscando variante...")
    # Variante: buscar por el primer reintento
    import re
    pattern = r'(\s+)when \(reintentos\) \{\s*\n\s*1 -> \{\s*\n\s*addLog\("🔄 Reintento 1/3 \(misma URL\)"\)'
    match = re.search(pattern, content)
    if match:
        print("   Encontré el patrón 1 pero no el bloque completo")
        print("   Puede requerir ajuste manual")
    else:
        print("   No se pudo modificar")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "limpiarUrlFinal" "$DATA_DIR/M3u8Extractor.kt" | xargs -I {} echo "  limpiarUrlFinal: {} apariciones"
grep -q "Error de red → URL fresca" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Reintentos inteligentes"

echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"