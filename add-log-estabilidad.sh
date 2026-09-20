#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-log-estabilidad"

echo "📝 Agregando log de diagnóstico (solo agrega, no modifica)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Import de LazyColumn (por si no está)
# ═══════════════════════════════════════════════════════════
if "import androidx.compose.foundation.lazy.items" not in content:
    # Ya existe probablemente, pero por si acaso
    pass

# ═══════════════════════════════════════════════════════════
# 2) Estado para el log
# ═══════════════════════════════════════════════════════════
if "var logsDiagnostico" not in content:
    ancla = "    var toast by remember { mutableStateOf<String?>(null) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    var logsDiagnostico by remember { mutableStateOf(listOf<String>()) }\n    var mostrarLogDiag by remember { mutableStateOf(false) }",
            1
        )
        print("✅ Estado logsDiagnostico agregado")

# ═══════════════════════════════════════════════════════════
# 3) Función de log
# ═══════════════════════════════════════════════════════════
if "val logDiag: (String) -> Unit" not in content:
    ancla = "    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + '''

    // 🆕 LOG DE DIAGNÓSTICO (visible en el reproductor)
    val logDiag: (String) -> Unit = { msg ->
        val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())
        logsDiagnostico = (logsDiagnostico + "[$t] $msg").takeLast(40)
    }''',
            1
        )
        print("✅ Función logDiag agregada")

# ═══════════════════════════════════════════════════════════
# 4) Log en el listener de errores
# ═══════════════════════════════════════════════════════════
# Buscar el bloque "override fun onPlayerError"
old_error = '''override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName'''

new_error = '''override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        logDiag("❌ ERROR: $code")'''

if old_error in content:
    content = content.replace(old_error, new_error, 1)
    print("✅ Log en onPlayerError")

# ═══════════════════════════════════════════════════════════
# 5) Log en cambios de estado de reproducción
# ═══════════════════════════════════════════════════════════
old_state = '''override fun onPlaybackStateChanged(state: Int) {
                        when (state) {'''

new_state = '''override fun onPlaybackStateChanged(state: Int) {
                        val nombreEstado = when (state) {
                            1 -> "IDLE"
                            2 -> "BUFFERING"
                            3 -> "READY"
                            4 -> "ENDED"
                            else -> "?"
                        }
                        logDiag("📺 Estado: $nombreEstado")
                        when (state) {'''

if old_state in content:
    content = content.replace(old_state, new_state, 1)
    print("✅ Log en onPlaybackStateChanged")

# ═══════════════════════════════════════════════════════════
# 6) Log cuando se carga un nuevo m3u8
# ═══════════════════════════════════════════════════════════
old_carga = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."'''

new_carga = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        logDiag("🔵 Cargando URL (trigger=$reloadTrigger)")
        try {
            status = "Cargando..."'''

if old_carga in content:
    content = content.replace(old_carga, new_carga, 1)
    print("✅ Log en carga de URL")

# ═══════════════════════════════════════════════════════════
# 7) Log cuando cambia embedActual
# ═══════════════════════════════════════════════════════════
old_embed = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}'''

new_embed = '''    LaunchedEffect(embedActual) {
        logDiag("🔄 Canal: ${embedActual.nombre}")
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}'''

if old_embed in content:
    content = content.replace(old_embed, new_embed, 1)
    print("✅ Log en cambio de embed")

# ═══════════════════════════════════════════════════════════
# 8) Botón flotante + Panel de log
# ═══════════════════════════════════════════════════════════
if "🐛 DIAG" not in content:
    # Buscar el último cierre del Box principal (antes del último "}")
    # Lo insertamos justo antes del último AnimatedVisibility del WebView o del cierre del Box

    # Estrategia: buscar "modifier = Modifier.size(1.dp)" que es el WebView, y meter el botón ANTES
    marker = '''                modifier = Modifier.size(1.dp)
            )
        }
    }
}'''

    reemplazo = '''                modifier = Modifier.size(1.dp)
            )
        }

        // ═══════════════════════════════════════════════════════
        // 🐛 LOG DE DIAGNÓSTICO (tocar para ver/ocultar)
        // ═══════════════════════════════════════════════════════
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 100.dp, end = 16.dp)
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
                        Text(
                            "🐛 DIAGNÓSTICO (${logsDiagnostico.size} líneas)",
                            color = Color(0xFFFF6B6B),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black
                        )
                        Spacer(Modifier.height(10.dp))
                    }
                    items(logsDiagnostico.size) { i ->
                        val l = logsDiagnostico[i]
                        val color = when {
                            l.contains("❌") -> Color(0xFFFF6B6B)
                            l.contains("📺 Estado: READY") -> Color(0xFF4ADE80)
                            l.contains("📺 Estado: BUFFERING") -> Color(0xFFFACC15)
                            l.contains("📺 Estado: IDLE") || l.contains("📺 Estado: ENDED") -> Color(0xFF94A3B8)
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
    }
}'''

    if marker in content:
        content = content.replace(marker, reemplazo, 1)
        print("✅ Botón + Panel de diagnóstico agregados")
    else:
        print("⚠️  No encontré el cierre del Box (marca 'modifier = Modifier.size(1.dp)')")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "logsDiagnostico" "$FILE" && echo "  ✓ Estado logsDiagnostico"
grep -q "val logDiag" "$FILE" && echo "  ✓ Función logDiag"
grep -q "🐛 DIAG" "$FILE" && echo "  ✓ Botón DIAG agregado"

echo ""
echo "✅✅✅ Log de diagnóstico agregado (solo agrega, no modifica)"
echo ""
echo "📌 Cómo usarlo:"
echo "   1. Instalá el APK"
echo "   2. Entrá al canal que se corta"
echo "   3. Tocá el botón '🐛 DIAG' arriba a la derecha"
echo "   4. Esperá a que se corte"
echo "   5. Cuando se corte, mirá el log y pegame las últimas 20 líneas"
echo ""
echo "📌 Colores del log:"
echo "   🔵 Azul   = Carga de URL"
echo "   🔄 Violeta = Cambio de canal"
echo "   📺 Estados = IDLE/BUFFERING/READY/ENDED"
echo "   ❌ Rojo   = Error"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"