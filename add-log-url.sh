#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-log-url"

echo "📝 Agregando log de la URL que se carga..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Loguear la URL exacta cuando se carga al player
old = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            tiempoInicioStream = System.currentTimeMillis()'''

new = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        logDiag("🎯 URL: ${url.take(120)}")
        try {
            status = "Cargando..."
            tiempoInicioStream = System.currentTimeMillis()'''

if old in content:
    content = content.replace(old, new, 1)
    print("✅ Log de URL agregado")
else:
    print("⚠️  No encontré el bloque de carga")

# 2) Loguear cuando el extractor termina (en el flujo principal)
old2 = '''            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url'''

new2 = '''            if (url != null) {
                logDiag("✅ Extractor OK: ${url.take(100)}")
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url'''

if old2 in content:
    content = content.replace(old2, new2, 1)
    print("✅ Log del extractor agregado")
else:
    print("⚠️  No encontré el bloque del extractor")

# 3) Loguear el primer intento del extractor (antes de extraer)
old3 = '''            status = "Analizando..."
            val url = withTimeoutOrNull(15000L) {'''

new3 = '''            status = "Analizando..."
            logDiag("🔍 Extrayendo de: ${embedActual.url.take(80)}")
            val url = withTimeoutOrNull(15000L) {'''

if old3 in content:
    content = content.replace(old3, new3, 1)
    print("✅ Log de inicio de extracción agregado")
else:
    # Variante con timeout diferente
    old3b = '''            status = "Analizando..."
            val url = withTimeoutOrNull(8000L) {'''
    if old3b in content:
        content = content.replace(old3b, new3.replace("15000L", "8000L"), 1)
        print("✅ Log de inicio de extracción agregado (8000L)")
    else:
        print("⚠️  No encontré el bloque de análisis")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "logDiag" "$FILE" | xargs -I {} echo "  logDiag calls: {}"

echo ""
echo "✅✅✅ Logs agregados"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1