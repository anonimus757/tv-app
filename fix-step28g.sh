#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

echo "📝 Mejorando extracción para páginas PHP dinámicas..."

cp "$PKG_DIR/ui/PlayerScreen.kt" "$PKG_DIR/ui/PlayerScreen.kt.bak3"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Helper para detectar URLs dinámicas (PHP, stream=, etc.)
helper = '''
/**
 * Detecta si una URL es una página dinámica (PHP, stream=, etc.)
 * que probablemente cargue el video vía JavaScript. Para esas, saltamos
 * directo al WebView sin perder tiempo con el extractor estático.
 */
private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    return low.contains(".php") ||
           low.contains("stream=") ||
           low.contains("/embed/") ||
           low.contains("/player") ||
           low.contains("/live/") ||
           low.contains("/canal/")
}
'''

# Insertar helper antes de "private fun formatoTiempo"
content = content.replace(
    "private fun formatoTiempo(segundos: Int): String {",
    helper + "\nprivate fun formatoTiempo(segundos: Int): String {"
)

# 2) En el LaunchedEffect(embedActual), antes de llamar al extractor,
#    chequear si es página dinámica → ir directo a WebView
old_effect = '''    LaunchedEffect(embedActual) {
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

new_effect = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}
        m3u8Url = null
        exoError = null
        usarWebView = false
        reintentos = 0
        status = "Analizando embed..."
        saludMonitor.reset()
        addLog("🔍 Analizando ${embedActual.nombre}...")

        // FIX: si es página dinámica (PHP/stream=), ir directo a WebView
        if (esPaginaDinamica(embedActual.url)) {
            addLog("⚡ Página dinámica, usando WebView directo")
            usarWebView = true
            return@LaunchedEffect
        }

        try {
            // Timeout: si el extractor tarda más de 15s, pasamos a WebView
            val url = kotlinx.coroutines.withTimeoutOrNull(15000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
            } else {
                addLog("⚠️ Extracto falló/timeout, WebView...")
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message}, WebView...")
            usarWebView = true
        }
    }'''

if old_effect in content:
    content = content.replace(old_effect, new_effect)
    print("✅ LaunchedEffect actualizado")
else:
    print("⚠️  No encontré el LaunchedEffect exacto. Buscando variante...")
    # Intento con regex más flexible
    import re
    pattern = r'LaunchedEffect\(embedActual\) \{.*?\n    \}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_effect + content[match.end():]
        print("✅ LaunchedEffect reemplazado (regex)")
    else:
        print("❌ No se pudo reemplazar el LaunchedEffect")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "esPaginaDinamica" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ Helper esPaginaDinamica"
grep -q "withTimeoutOrNull(15000L)" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ Timeout de 15s en extractor"
grep -q "Página dinámica, usando WebView" "$PKG_DIR/ui/PlayerScreen.kt" && echo "  ✓ Salto directo a WebView"

echo ""
echo "✅✅✅ Fix 28g completo — extracción para páginas dinámicas"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"