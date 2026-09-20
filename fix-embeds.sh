#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

echo "📝 Aplicando fix definitivo para embeds dinámicos..."

# ═══════════════════════════════════════════════════════════
# 1) PlayerScreen.kt — Detección + Timeout + WebView agresivo
# ═══════════════════════════════════════════════════════════

cp "$PKG_DIR/PlayerScreen.kt" "$PKG_DIR/PlayerScreen.kt.bak-embeds"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ── 1a) Agregar helper esPaginaDinamica ──────────────────
helper = '''
/**
 * Detecta si una URL es una página que carga el video vía JavaScript.
 * Para esas, saltamos directo al WebView en vez de perder tiempo con el extractor estático.
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
           low.contains("/v/") ||
           low.contains("/e/")
}
'''

# Insertar el helper antes de "private fun formatoTiempo"
if "esPaginaDinamica" not in content:
    content = content.replace(
        "private fun formatoTiempo(segundos: Int): String {",
        helper + "\nprivate fun formatoTiempo(segundos: Int): String {"
    )
    print("✅ Helper esPaginaDinamica agregado")

# ── 1b) Modificar LaunchedEffect(embedActual) ──────────────
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

        // FIX: si es página dinámica → ir directo a WebView
        if (esPaginaDinamica(embedActual.url)) {
            addLog("⚡ Página dinámica → WebView directo")
            status = "Cargando reproductor..."
            usarWebView = true
            return@LaunchedEffect
        }

        try {
            // Timeout de 12 seg: si no responde, pasamos a WebView
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

if old_effect in content:
    content = content.replace(old_effect, new_effect)
    print("✅ LaunchedEffect actualizado con detección + timeout")
else:
    # Intento con regex más flexible
    import re
    pattern = r'    LaunchedEffect\(embedActual\) \{.*?\n    \}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_effect + content[match.end():]
        print("✅ LaunchedEffect actualizado (regex)")
    else:
        print("⚠️  No se pudo reemplazar LaunchedEffect")

# ── 1c) Agregar timeout al WebView (si no captura en 20 seg → error) ──
# Buscar el bloque del WebView y agregar un LaunchedEffect de timeout
if "webViewTimeout" not in content:
    # Agregar un estado de timeout
    content = content.replace(
        "    var usarWebView by remember { mutableStateOf(false) }",
        "    var usarWebView by remember { mutableStateOf(false) }\n    var webViewTimeout by remember { mutableStateOf(false) }"
    )
    
    # Agregar LaunchedEffect para timeout de WebView después de LaunchedEffect(m3u8Url)
    old_timer = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''
    
    new_timer = old_timer + '''

    // Timeout de WebView: si en 20 seg no captura el m3u8, mostramos error
    LaunchedEffect(usarWebView) {
        if (usarWebView && m3u8Url == null) {
            webViewTimeout = false
            delay(20000)
            if (m3u8Url == null) {
                webViewTimeout = true
                addLog("⏰ WebView no capturó en 20s")
            }
        }
    }'''
    
    if old_timer in content:
        content = content.replace(old_timer, new_timer)
        print("✅ Timeout de WebView agregado")

# ── 1d) Mostrar error si WebView no capturó ──────────────
old_error_check = '''        if ((m3u8Url == null || exoError != null) && !refrescando && avisoCambio == null) {'''
new_error_check = '''        if (webViewTimeout && m3u8Url == null && usarWebView) {
            // WebView no capturó → mostrar error con botón de reintentar
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(30.dp)) {
                    Icon(imageVector = AppIcons.advertencia, contentDescription = null,
                        tint = Color(0xFFEF4444), modifier = Modifier.size(52.dp))
                    Spacer(Modifier.height(14.dp))
                    Text("No se pudo cargar este canal", color = Color(0xFFEF4444),
                        fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text("Probá otro canal con el panel lateral (←)",
                        color = Color(0xFF94A3B8), fontSize = 13.sp)
                    Spacer(Modifier.height(16.dp))
                    Box(Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0xFFD4AF37))
                        .clickable {
                            webViewTimeout = false
                            usarWebView = false
                            scope.launch {
                                delay(200)
                                usarWebView = true
                            }
                        }
                        .padding(horizontal = 24.dp, vertical = 12.dp)
                    ) {
                        Text("🔄 Reintentar", color = Color.Black, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        } else if ((m3u8Url == null || exoError != null) && !refrescando && avisoCambio == null) {'''
    
    if old_error_check in content:
        content = content.replace(old_error_check, new_error_check)
        print("✅ Error de WebView timeout agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2) M3u8Extractor.kt — Timeout global + más patrones
# ═══════════════════════════════════════════════════════════

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-embeds"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# ── 2a) Reducir MAX_PROF de 8 a 5 (evita cuelgues) ───────
if "private const val MAX_PROF = 8" in content:
    content = content.replace("private const val MAX_PROF = 8", "private const val MAX_PROF = 5")
    print("✅ MAX_PROF reducido a 5")

# ── 2b) Reducir timeouts de OkHttp ───────────────────────
if "connectTimeout(15, TimeUnit.SECONDS)" in content:
    content = content.replace("connectTimeout(15, TimeUnit.SECONDS)", "connectTimeout(8, TimeUnit.SECONDS)")
    content = content.replace("readTimeout(15, TimeUnit.SECONDS)", "readTimeout(8, TimeUnit.SECONDS)")
    print("✅ Timeouts reducidos a 8s")

# ── 2c) Agregar más patrones de m3u8 ────────────────────
old_patrones = '''    private val PATRONES = listOf(
        Regex("""["']((?:https?:)?//[^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""["'](/[^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""["']([^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""file\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""source\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""loadSource\\s*\\(\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""src\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""url\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""playbackURL\\s*[:=]\\s*["']([^"']+)["']""")
    )'''

new_patrones = '''    private val PATRONES = listOf(
        Regex("""["']((?:https?:)?//[^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""["'](/[^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""["']([^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']"""),
        Regex("""file\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""source\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""loadSource\\s*\\(\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""src\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""url\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""playbackURL\\s*[:=]\\s*["']([^"']+)["']"""),
        // Nuevos patrones para reproductores modernos
        Regex("""data-src\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""hls\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""manifest\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""videoUrl\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""streamUrl\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""media\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""path\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        // JSON típico de HLS.js
        Regex("""["']((?:https?:)?//[^"'\\s<>]+\\.m3u8[^"'\\s<>]*)["']""")
    )'''

if old_patrones in content:
    content = content.replace(old_patrones, new_patrones)
    print("✅ Patrones de m3u8 ampliados (17 patrones)")

# ── 2d) Reducir visitas máximas ──────────────────────────
if "if (prof > MAX_PROF) return emptyList()" in content:
    content = content.replace(
        "if (prof > MAX_PROF) return emptyList()",
        "if (prof > MAX_PROF || visitadas.size > 15) return emptyList()"
    )
    print("✅ Límite de visitas agregado (15 máximo)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) Verificación
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔎 Verificando:"
grep -q "esPaginaDinamica" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ esPaginaDinamica en PlayerScreen"
grep -q "withTimeoutOrNull(12000L)" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ Timeout de 12s en extractor"
grep -q "webViewTimeout" "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ Timeout de WebView"
grep -q "MAX_PROF = 5" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ MAX_PROF reducido"
grep -q "connectTimeout(8" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Timeouts reducidos"

echo ""
echo "✅✅✅ Fix definitivo para embeds dinámicos aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   • Detecta .php, stream=, /live/, /embed/ → WebView directo"
echo "   • Timeout de 12s en extractor estático"
echo "   • Timeout de 20s en WebView → muestra error si no captura"
echo "   • 17 patrones de m3u8 (antes 9)"
echo "   • Límite de 15 visitas máximo"
echo "   • Timeouts HTTP reducidos a 8s"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"