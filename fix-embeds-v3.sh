#!/bin/bash
set -e

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$PKG_DIR/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-embeds-v3"

echo "📝 Aplicando fix v3 con patrón EXACTO..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Agregar helper esPaginaDinamica antes de formatoTiempo
# ═══════════════════════════════════════════════════════════
if "private fun esPaginaDinamica" not in content:
    helper = '''/**
 * Detecta si una URL es una página dinámica (PHP, stream=, etc.)
 * Para esas, saltamos directo al WebView sin perder tiempo con el extractor estático.
 */
private fun esPaginaDinamica(url: String): Boolean {
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
}

'''
    content = content.replace(
        "private fun formatoTiempo(segundos: Int): String {",
        helper + "private fun formatoTiempo(segundos: Int): String {",
        1
    )
    print("✅ esPaginaDinamica agregado antes de formatoTiempo")

# ═══════════════════════════════════════════════════════════
# 2) Reemplazar el LaunchedEffect(embedActual) EXACTO
# ═══════════════════════════════════════════════════════════
old_block = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
        addLog("🔍 Analizando ${embedActual.nombre}...")
        try {
            val url = M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
            } else {
                addLog("⚠️ Static falló, WebView...")
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message}")
            usarWebView = true
        }
    }'''

new_block = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
        addLog("🔍 Analizando ${embedActual.nombre}...")

        // FIX: si es página dinámica (PHP, stream=, etc.) → WebView directo
        if (esPaginaDinamica(embedActual.url)) {
            addLog("⚡ Página dinámica → WebView directo")
            status = "Cargando reproductor..."
            usarWebView = true
            return@LaunchedEffect
        }

        try {
            // Timeout de 12 seg para el extractor estático
            val url = kotlinx.coroutines.withTimeoutOrNull(12000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
            } else {
                addLog("⚠️ Extracto falló/timeout → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }
    }'''

if old_block in content:
    content = content.replace(old_block, new_block)
    print("✅ LaunchedEffect REEMPLAZADO con versión nueva")
else:
    print("❌ No coincidió el bloque exacto")
    # Buscar diferencias
    import difflib
    print("   Buscando pistas...")
    if "LaunchedEffect(embedActual)" in content:
        print("   El bloque existe en el archivo pero con diferencias")
    exit(1)

# ═══════════════════════════════════════════════════════════
# 3) Agregar webViewTimeout
# ═══════════════════════════════════════════════════════════
if "webViewTimeout" not in content:
    old_var = "    var usarWebView by remember { mutableStateOf(false) }"
    new_var = "    var usarWebView by remember { mutableStateOf(false) }\n    var webViewTimeout by remember { mutableStateOf(false) }"
    if old_var in content:
        content = content.replace(old_var, new_var, 1)
        print("✅ webViewTimeout agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "private fun esPaginaDinamica" "$FILE" && echo "  ✓ esPaginaDinamica DEFINIDO"
grep -q "if (esPaginaDinamica(embedActual.url))" "$FILE" && echo "  ✓ esPaginaDinamica EN USO"
grep -q "withTimeoutOrNull(12000L)" "$FILE" && echo "  ✓ Timeout aplicado"
grep -q "webViewTimeout" "$FILE" && echo "  ✓ webViewTimeout definido"

echo ""
echo "📄 Bloque nuevo:"
grep -A 32 "LaunchedEffect(embedActual) {" "$FILE" | head -35

echo ""
echo "✅✅✅ Fix v3 aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"