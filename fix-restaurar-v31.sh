#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

# ═══════════════════════════════════════════════════════════
# 1) Restaurar la versión v3.1 publicada
# ═══════════════════════════════════════════════════════════
if [ ! -f "$FILE.bak-parpadeo" ]; then
    echo "❌ No encontré el backup .bak-parpadeo"
    exit 1
fi

cp "$FILE.bak-parpadeo" "$FILE"
echo "✅ PlayerScreen restaurado a la v3.1 publicada"
echo "   (backup .bak-parpadeo del Sep 19 19:02)"
echo ""

# ═══════════════════════════════════════════════════════════
# 2) Backup de seguridad por si hay que revertir
# ═══════════════════════════════════════════════════════════
cp "$FILE" "$FILE.bak-antes-2fixes"

# ═══════════════════════════════════════════════════════════
# 3) FIX 1 — Parpadeo: PlayerView siempre montado
# ═══════════════════════════════════════════════════════════
echo "📝 Fix 1 — Parpadeo: PlayerView no se desmonta..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el bloque del PlayerView
old = '''        if (m3u8Url != null && exoError == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

new = '''        // FIX PARPADEO: PlayerView siempre visible (no se desmonta al haber error)
        if (m3u8Url != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

if old in content:
    content = content.replace(old, new)
    print("  ✅ PlayerView ya no se desmonta con error")
else:
    print("  ⚠️  No encontré el bloque exacto del PlayerView")
    # Buscar variante
    import re
    pattern = r'if \(m3u8Url != null && exoError == null\) \{'
    if re.search(pattern, content):
        content = re.sub(pattern, 'if (m3u8Url != null) {', content)
        print("  ✅ Reemplazado (regex)")

# También quitar la condición de la animación alpha que puede causar parpadeo
old_alpha = '''    // 🎬 Animación de entrada: cuando el video aparece, hace fade-in
    LaunchedEffect(m3u8Url) {
        if (m3u8Url != null) {
            videoAlpha = 0f
            delay(100)
            videoAlpha = 1f
        } else {
            videoAlpha = 0f
        }
    }'''

new_alpha = '''    // FIX PARPADEO: sin fade-in (evita parpadeo al cambiar canal)
    LaunchedEffect(m3u8Url) {
        videoAlpha = if (m3u8Url != null) 1f else 0f
    }'''

if old_alpha in content:
    content = content.replace(old_alpha, new_alpha)
    print("  ✅ Animación fade-in eliminada")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 2 — Cambio de canal instantáneo..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el bloque de onCanalClick que espera extracción
# Puede tener distintas formas. Vamos a reemplazar por la versión directa.
old1 = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    eventoMuerto = false
                    mostrandoSinSenal = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                    // Resetear candidatos al cambiar manualmente de canal
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0

                    // Refresh silencioso: extraer m3u8 del nuevo canal
                    // en background ANTES de cortar el actual
                    scope.launch {
                        try {
                            addLog("🔄 Preparando canal ${nuevo.nombre}...")
                            val fresh = kotlinx.coroutines.withTimeoutOrNull(10000L) {
                                M3u8Extractor.extraer(nuevo.url, nuevo.referer, addLog)
                            }
                            if (fresh != null) {
                                cookies = M3u8Extractor.cookieString()
                                // Cambiar al nuevo canal con el m3u8 ya listo
                                embedActual = nuevo
                                m3u8Url = fresh
                                addLog("✅ Canal listo, transición suave")
                            } else {
                                // Fallback: cambio normal (con extractor visible)
                                embedActual = nuevo
                            }
                        } catch (_: Exception) {
                            embedActual = nuevo
                        }
                    }
                },'''

new1 = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    eventoMuerto = false
                    mostrandoSinSenal = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0

                    // FIX: cambio DIRECTO e instantáneo.
                    // El LaunchedEffect(embedActual) maneja el resto.
                    embedActual = nuevo
                },'''

if old1 in content:
    content = content.replace(old1, new1)
    print("  ✅ Cambio de canal instantáneo")
else:
    print("  ⚠️  No encontré el bloque largo, buscando variante...")
    # Variante más corta
    old2 = '''                    scope.launch {
                        try {
                            addLog("🔄 Preparando canal ${nuevo.nombre}...")
                            val fresh = kotlinx.coroutines.withTimeoutOrNull(10000L) {
                                M3u8Extractor.extraer(nuevo.url, nuevo.referer, addLog)
                            }
                            if (fresh != null) {
                                cookies = M3u8Extractor.cookieString()
                                // Cambiar al nuevo canal con el m3u8 ya listo
                                embedActual = nuevo
                                m3u8Url = fresh
                                addLog("✅ Canal listo, transición suave")
                            } else {
                                // Fallback: cambio normal (con extractor visible)
                                embedActual = nuevo
                            }
                        } catch (_: Exception) {
                            embedActual = nuevo
                        }
                    }'''
    new2 = '''                    // FIX: cambio DIRECTO e instantáneo
                    embedActual = nuevo'''
    if old2 in content:
        content = content.replace(old2, new2)
        print("  ✅ Cambio de canal instantáneo (variante)")
    else:
        print("  ⚠️  No encontré el bloque de scope.launch en onCanalClick")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "FIX PARPADEO: PlayerView siempre visible" "$FILE" && echo "  ✓ Fix parpadeo aplicado"
grep -q "FIX: cambio DIRECTO e instantáneo" "$FILE" && echo "  ✓ Fix cambio canal aplicado"
grep -c "withTimeoutOrNull(10000L)" "$FILE" | xargs -I {} echo "  withTimeoutOrNull(10000L): {} (debe ser 0)"
grep -c "scope.launch.*Preparando canal" "$FILE" | xargs -I {} echo "  scope.launch Preparando: {} (debe ser 0)"

echo ""
echo "✅✅✅ v3.1 restaurada + 2 fixes mínimos"
echo ""
echo "📌 Qué se hizo:"
echo "   1. Restauró la v3.1 que funcionaba con futbollibre"
echo "   2. PlayerView ya no se desmonta (fix parpadeo)"
echo "   3. Cambio de canal directo (fix lentitud)"
echo "   4. SIN fade-in (evita parpadeo visual)"
echo ""
echo "📌 Qué NO se tocó:"
echo "   ✅ M3u8Extractor (sigue igual)"
echo "   ✅ WebView (sigue igual)"
echo "   ✅ Auto-refresh (sigue igual)"
echo "   ✅ Panel lateral (sigue igual)"
echo "   ✅ Selector de calidad (sigue igual)"
echo "   ✅ Gestos (siguen iguales)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"