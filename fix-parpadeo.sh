#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-parpadeo"

echo "📝 Fix parpadeo del video..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Estado tiempoInicioStream
if "var tiempoInicioStream" not in content:
    ancla = "    var webViewVisible by remember { mutableStateOf(false) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    var tiempoInicioStream by remember { mutableLongStateOf(0L) }",
            1
        )
    else:
        ancla2 = "    var reintentos by remember { mutableIntStateOf(0) }"
        content = content.replace(
            ancla2,
            ancla2 + "\n    var tiempoInicioStream by remember { mutableLongStateOf(0L) }",
            1
        )
    print("✅ Estado tiempoInicioStream")

# 2) PlayerView siempre visible si hay URL
old_pv = '''        if (m3u8Url != null && exoError == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

new_pv = '''        // FIX PARPADEO: PlayerView siempre visible si hay URL
        if (m3u8Url != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

if old_pv in content:
    content = content.replace(old_pv, new_pv)
    print("✅ PlayerView siempre visible")

# 3) Actualizar timestamp al cargar stream
old_load = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."'''

new_load = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            tiempoInicioStream = System.currentTimeMillis()'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("✅ Timestamp actualizado")

# 4) Período de gracia en onPlayerError
old_err = '''                    override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        exoError = "$code: ${e.message?.take(160)}"
                        addLog("❌ $code")
                        if (todosFallaron) return'''

new_err = '''                    override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        addLog("❌ $code")

                        // FIX PARPADEO: ignorar errores en los primeros 4 seg
                        val tiempoActual = System.currentTimeMillis()
                        val esPrincipio = (tiempoActual - tiempoInicioStream) < 4000L

                        if (esPrincipio) {
                            addLog("⏳ Error en arranque, esperando estabilización...")
                            return
                        }

                        exoError = "$code: ${e.message?.take(160)}"
                        if (todosFallaron) return'''

if old_err in content:
    content = content.replace(old_err, new_err)
    print("✅ Período de gracia en onPlayerError")
else:
    print("⚠️  No encontré onPlayerError")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "var tiempoInicioStream" "$FILE" && echo "  ✓ Estado tiempoInicioStream"
grep -q "if (m3u8Url != null) {" "$FILE" && echo "  ✓ PlayerView siempre visible"
grep -q "esPrincipio" "$FILE" && echo "  ✓ Período de gracia"

echo ""
echo "✅✅✅ Fix del parpadeo aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"