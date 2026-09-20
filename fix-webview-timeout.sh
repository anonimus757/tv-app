#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-wvtimeout"

echo "📝 Fix: esPaginaDinamica + timeout WebView..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) esPaginaDinamica: SOLO streamxhd (dejar tvf90 al extractor)
# ═══════════════════════════════════════════════════════════
patron_esPag = r'private fun esPaginaDinamica\(url: String\): Boolean \{[^}]*?\n\}'
nuevo_esPag = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // SOLO sitios que realmente no se pueden extraer (usan MSE/Blob)
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com")
}'''

if re.search(patron_esPag, content, re.DOTALL):
    content = re.sub(patron_esPag, nuevo_esPag, content, flags=re.DOTALL)
    print("✅ esPaginaDinamica limitado SOLO a streamxhd")

# ═══════════════════════════════════════════════════════════
# 2) Agregar timeout al WebView: si en 8 seg no captura → cambiar
# ═══════════════════════════════════════════════════════════

# Agregar estado de timestamp de WebView
if "var webViewStartTime" not in content:
    ancla = "    var urlsCandidatas by remember { mutableStateOf(listOf<String>()) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    var webViewStartTime by remember { mutableLongStateOf(0L) }",
            1
        )
        print("✅ Estado webViewStartTime agregado")

# Agregar LaunchedEffect que chequea el WebView
detector_webview = '''
    // ═══════════════════════════════════════════════════════
    // TIMEOUT DE WEBVIEW: si en 8 seg no captura m3u8 → saltar canal
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(usarWebView) {
        if (usarWebView) {
            webViewStartTime = System.currentTimeMillis()
            delay(8000)

            val sinCapturar = m3u8Url == null
            val siguenPasandoLosSegundos = System.currentTimeMillis() - webViewStartTime >= 8000

            if (sinCapturar && siguenPasandoLosSegundos && !refrescando) {
                addLog("⏰ WebView no capturó en 8s → siguiente canal")

                // Buscar siguiente canal del evento
                val siguiente = evento.embeds.firstOrNull {
                    it.url != embedActual.url && it.url !in canalesIntentados
                }
                if (siguiente != null) {
                    addLog("📡 Sin señal, buscando otra...")
                    mostrandoSinSenal = true
                    delay(2000)
                    mostrandoSinSenal = false
                    canalesIntentados = canalesIntentados + embedActual.url
                    usarWebView = false
                    reintentos = 0
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0
                    embedActual = siguiente
                } else {
                    addLog("❌ Evento sin señal")
                    eventoMuerto = true
                    todosFallaron = true
                    usarWebView = false
                }
            }
        }
    }
'''

# Insertar antes del timer
ancla_timer = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''

if ancla_timer in content and "TIMEOUT DE WEBVIEW" not in content:
    content = content.replace(ancla_timer, detector_webview + "\n" + ancla_timer, 1)
    print("✅ Timeout de WebView agregado")
elif "TIMEOUT DE WEBVIEW" in content:
    print("ℹ️  Timeout de WebView ya existía")

# ═══════════════════════════════════════════════════════════
# 3) Import para mutableLongStateOf
# ═══════════════════════════════════════════════════════════
if "import androidx.compose.runtime.mutableLongStateOf" not in content and "mutableLongStateOf" in content:
    content = content.replace(
        "import androidx.compose.runtime.mutableIntStateOf",
        "import androidx.compose.runtime.mutableIntStateOf\nimport androidx.compose.runtime.mutableLongStateOf"
    )
    print("✅ Import mutableLongStateOf")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -A3 "private fun esPaginaDinamica" "$UI_DIR/PlayerScreen.kt" | head -5
grep -q "TIMEOUT DE WEBVIEW" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Timeout de WebView"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🎯 Qué cambió:"
echo "   • esPaginaDinamica SOLO detecta streamxhd (no .php ni stream=)"
echo "   • tvf90.com vuelve al extractor estático (extrae bien)"
echo "   • Si el WebView no captura en 8 seg → cambia al siguiente canal"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"