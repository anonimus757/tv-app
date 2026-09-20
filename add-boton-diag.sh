#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-boton-diag"

echo "📝 Insertando botón 🐛 DIAG con marcador correcto..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Verificar que NO esté ya el botón
if "🐛 DIAG" in content:
    print("ℹ️  El botón ya está, no hago nada")
    exit(0)

# El marcador único: el bloque del WebView
old = '''        if (usarWebView && m3u8Url == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {'''

new = '''        // ═══════════════════════════════════════════════════════
        // 🐛 LOG DE DIAGNÓSTICO (tocar para ver/ocultar)
        // ═══════════════════════════════════════════════════════
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 110.dp, end = 16.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xCC000000))
                .border(1.dp, Color(0x66FF6B6B), RoundedCornerShape(8.dp))
                .clickable { mostrarLogDiag = !mostrarLogDiag }
                .padding(horizontal = 10.dp, vertical = 6.dp)
        ) {
            Text(
                "🐛 DIAG",
                color = Color(0xFFFF6B6B),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold
            )
        }

        if (mostrarLogDiag) {
            Box(
                Modifier
                    .align(Alignment.Center)
                    .fillMaxSize(0.85f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFFF6B6B), RoundedCornerShape(12.dp))
                    .padding(14.dp)
            ) {
                androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "🐛 DIAGNÓSTICO (${logsDiagnostico.size})",
                                color = Color(0xFFFF6B6B),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Black
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                "tocar 🐛 para cerrar",
                                color = Color(0xFF94A3B8),
                                fontSize = 10.sp
                            )
                        }
                        Spacer(Modifier.height(10.dp))
                    }
                    androidx.compose.foundation.lazy.items(logsDiagnostico.size) { i ->
                        val l = logsDiagnostico[i]
                        val color = when {
                            l.contains("❌") -> Color(0xFFFF6B6B)
                            l.contains("READY") -> Color(0xFF4ADE80)
                            l.contains("BUFFERING") -> Color(0xFFFACC15)
                            l.contains("IDLE") || l.contains("ENDED") -> Color(0xFF94A3B8)
                            l.contains("🔵") -> Color(0xFF38BDF8)
                            l.contains("🔄") -> Color(0xFFA78BFA)
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

        if (usarWebView && m3u8Url == null) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {'''

if old in content:
    content = content.replace(old, new, 1)
    print("✅ Botón + Panel DIAG insertados antes del WebView")
else:
    print("❌ No encontré el bloque del WebView")
    print("   Buscando alternativas...")
    
    # Alternativa: buscar el primer AnimatedVisibility de mostrandoSinSenal
    old2 = '''        // ═══════════════════════════════════════════════════════
        // OVERLAY "SIN SEÑAL, BUSCANDO..." (3 seg)
        // ═══════════════════════════════════════════════════════'''
    if old2 in content:
        print("   Encontré el marcador alternativo: 'SIN SEÑAL'")
        content = content.replace(old2, new.replace('        if (usarWebView && m3u8Url == null) {\n            AndroidView(\n                factory = { ctx ->\n                    WebView(ctx).apply {', '') + old2, 1)
        print("   ✅ Insertado antes de 'SIN SEÑAL'")
    else:
        print("   ❌ No encontré ningún marcador alternativo")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "🐛 DIAG" "$FILE" | xargs -I {} echo "  Apariciones de '🐛 DIAG': {}"

echo ""
echo "✅✅✅ Listo"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"