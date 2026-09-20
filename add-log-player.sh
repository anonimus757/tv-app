#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"

echo "💾 Backup..."
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-log"
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-log"

echo "📝 Agregando log visible en el reproductor..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ── 1) Agregar estado para mostrar/ocultar el panel de log ──
if "var mostrarLogPanel by remember" not in content:
    content = content.replace(
        "    var webViewTimeout by remember { mutableStateOf(false) }",
        "    var webViewTimeout by remember { mutableStateOf(false) }\n    var mostrarLogPanel by remember { mutableStateOf(false) }"
    )
    print("✅ Estado mostrarLogPanel agregado")

# ── 2) Agregar botón flotante y panel de log ANTES del cierre del Box principal ──
# Buscar el último cierre antes del cierre de la función (el Bloque del WebView invisible)
log_panel_code = '''
        // ═══════════════════════════════════════════════════════
        // LOG PANEL (DEBUG) — Sacar cuando terminemos de debuggear
        // ═══════════════════════════════════════════════════════
        Box(
            Modifier
                .align(Alignment.TopStart)
                .padding(16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color(0xCC000000))
                .border(1.dp, Color(0xFFFF6B6B), RoundedCornerShape(10.dp))
                .clickable { mostrarLogPanel = !mostrarLogPanel }
                .padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text(
                if (mostrarLogPanel) "🐛 LOG ▼" else "🐛 LOG ▲",
                color = Color(0xFFFF6B6B),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
        }

        if (mostrarLogPanel) {
            Box(
                Modifier
                    .align(Alignment.Center)
                    .fillMaxSize(0.85f)
                    .padding(top = 60.dp, bottom = 20.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFFF6B6B), RoundedCornerShape(12.dp))
            ) {
                androidx.compose.foundation.lazy.LazyColumn(
                    Modifier.fillMaxSize().padding(14.dp)
                ) {
                    item {
                        Text(
                            "🐛 LOG DEL REPRODUCTOR (${logs.size} líneas)",
                            color = Color(0xFFFF6B6B),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black
                        )
                        Spacer(Modifier.height(10.dp))
                    }
                    items(logs.size) { i ->
                        val l = logs[i]
                        val color = when {
                            l.contains("❌") || l.contains("fail") || l.contains("error") -> Color(0xFFFF6B6B)
                            l.contains("✅") || l.contains("OK") -> Color(0xFF4ADE80)
                            l.contains("⚠️") -> Color(0xFFFACC15)
                            l.contains("→") -> Color(0xFF38BDF8)
                            else -> Color(0xFFCBD5E1)
                        }
                        Text(
                            l,
                            color = color,
                            fontSize = 10.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                            lineHeight = 14.sp,
                            modifier = Modifier.padding(vertical = 1.dp)
                        )
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        // FIN LOG PANEL
        // ═══════════════════════════════════════════════════════
'''

# Insertar antes del cierre del Box principal (antes del último "}")
# Buscar el bloque del WebView (que ya existe y es el último bloque en el Box)
webview_block = '''        if (usarWebView && m3u8Url == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {'''

if webview_block in content:
    # Insertar el log panel justo antes del WebView block
    content = content.replace(webview_block, log_panel_code + "\n" + webview_block, 1)
    print("✅ Panel de log insertado en el reproductor")
else:
    print("⚠️  No encontré el bloque del WebView, intentando con ancla diferente...")
    # Buscar el último bloque antes del cierre de la función
    if '        if (usarWebView && m3u8Url == null) {' in content:
        content = content.replace(
            '        if (usarWebView && m3u8Url == null) {',
            log_panel_code + '\n        if (usarWebView && m3u8Url == null) {',
            1
        )
        print("✅ Panel agregado (variante)")
    else:
        print("❌ No se pudo insertar el panel")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "LOG DEL REPRODUCTOR" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Panel de log agregado"
grep -q "mostrarLogPanel" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado agregado"

echo ""
echo "✅✅✅ Panel de log instalado"
echo ""
echo "🎯 Cómo usarlo:"
echo "   1. Abrí un canal en el reproductor"
echo "   2. Vas a ver un botón rojo '🐛 LOG' arriba a la izquierda"
echo "   3. Tocalo → se abre el panel con TODOS los logs"
echo "   4. Cuando falle, tocá el botón y copiá/pasteame lo que ves"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"