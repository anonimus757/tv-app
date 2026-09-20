#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
UI_DIR="$PKG_DIR/ui"
DATA_DIR="$PKG_DIR/data"

# ═══════════════════════════════════════════════════════════
# BACKUPS
# ═══════════════════════════════════════════════════════════
echo "💾 Creando backups..."
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak40"
cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak40"
echo "   ✅ Backups creados"

# ═══════════════════════════════════════════════════════════
# 1) BUFFER + REFRESH AUTOMÁTICO + REFRESH SILENCIOSO
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Aplicando mejoras en PlayerScreen.kt..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ── 1a) Buffer optimizado ────────────────────────────────
old_buffer = """        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 20000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()"""

new_buffer = """        // Buffer optimizado: 8s mínimo, 45s máximo
        // - Arranca rápido (2s para primer frame)
        // - Aguanta micro-cortes (45s de buffer)
        // - Rebuffer 5s para recuperarse sin pausar
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 45000, 2000, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()"""

if old_buffer in content:
    content = content.replace(old_buffer, new_buffer)
    print("✅ Buffer optimizado (8s-45s)")
elif "setBufferDurationsMs(8000, 45000" in content:
    print("ℹ️  Buffer ya estaba optimizado")
else:
    print("⚠️  No encontré el bloque de buffer exacto")

# ── 1b) Refresh automático cada 8 min ────────────────────
# Insertar después del LaunchedEffect(m3u8Url) del timer
old_timer_effect = """    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }"""

new_timer_effect = """    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }

    // ═══════════════════════════════════════════════════════
    // REFRESH AUTOMÁTICO CADA 8 MIN
    // Los tokens de los streams expiran cada 10-15 min. Esto renueva
    // el m3u8 en background antes de que caduque, evitando el bug
    // de pausa/reanudación constante.
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) return@LaunchedEffect
        while (true) {
            delay(8 * 60 * 1000L) // 8 minutos
            if (m3u8Url != null && !refrescando && !todosFallaron) {
                addLog("🔄 Auto-refresh de token (background)")
                try {
                    val fresh = M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                    if (fresh != null && fresh != m3u8Url) {
                        cookies = M3u8Extractor.cookieString()
                        // Actualizar el m3u8 SIN mostrar spinner ni cortar el video
                        m3u8Url = fresh
                        addLog("✅ Token renovado silenciosamente")
                    }
                } catch (_: Exception) {
                    addLog("⚠️ Auto-refresh falló, se reintentará en 8 min")
                }
            }
        }
    }"""

if old_timer_effect in content and "Auto-refresh de token" not in content:
    content = content.replace(old_timer_effect, new_timer_effect)
    print("✅ Auto-refresh cada 8 min agregado")
elif "Auto-refresh de token" in content:
    print("ℹ️  Auto-refresh ya estaba")
else:
    print("⚠️  No encontré el bloque del timer exacto")

# ── 1c) Refresh silencioso al cambiar de canal (panel lateral) ──
old_oncanalclick = """                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    embedActual = nuevo
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                },"""

new_oncanalclick = """                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO

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
                },"""

if old_oncanalclick in content and "Preparando canal" not in content:
    content = content.replace(old_oncanalclick, new_oncanalclick)
    print("✅ Refresh silencioso al cambiar de canal")
elif "Preparando canal" in content:
    print("ℹ️  Refresh silencioso ya estaba")
else:
    print("⚠️  No encontré el bloque onCanalClick exacto")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2) EXTRACTOR MÁS AGRESIVO
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Mejorando M3u8Extractor.kt..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Timeouts
if "connectTimeout(15, TimeUnit.SECONDS)" in content:
    content = content.replace("connectTimeout(15, TimeUnit.SECONDS)", "connectTimeout(10, TimeUnit.SECONDS)")
    content = content.replace("readTimeout(15, TimeUnit.SECONDS)", "readTimeout(10, TimeUnit.SECONDS)")
    print("✅ Timeouts a 10s")
elif "connectTimeout(10, TimeUnit.SECONDS)" in content:
    print("ℹ️  Timeouts ya estaban en 10s")

# MAX_PROF
if "private const val MAX_PROF = 8" in content:
    content = content.replace("private const val MAX_PROF = 8", "private const val MAX_PROF = 5")
    print("✅ MAX_PROF = 5")
elif "private const val MAX_PROF = 5" in content:
    print("ℹ️  MAX_PROF ya era 5")

# Patrones extra para reproductores modernos
if "videoUrl\\s*[:=]" not in content and "PATRONES = listOf" in content:
    old_close = '''        Regex("""playbackURL\\s*[:=]\\s*["']([^"']+)["']""")
    )'''
    new_close = '''        Regex("""playbackURL\\s*[:=]\\s*["']([^"']+)["']"""),
        // Patrones para reproductores modernos (HLS.js, JWPlayer, Video.js)
        Regex("""data-src\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""hls\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""manifest\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""videoUrl\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']"""),
        Regex("""streamUrl\\s*[:=]\\s*["']([^"']+\\.m3u8[^"']*)["']""")
    )'''
    if old_close in content:
        content = content.replace(old_close, new_close)
        print("✅ 5 patrones nuevos agregados")
    else:
        print("⚠️  No se pudo agregar patrones nuevos")
else:
    print("ℹ️  Patrones modernos ya presentes o bloque no encontrado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) VERIFICACIÓN
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔎 VERIFICACIÓN FINAL:"
echo ""
echo "PlayerScreen.kt:"
grep -q "setBufferDurationsMs(8000, 45000" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Buffer optimizado (8s-45s)" || echo "  ⚠️  Buffer NO cambiado"
grep -q "Auto-refresh de token" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Auto-refresh cada 8 min" || echo "  ⚠️  Auto-refresh NO agregado"
grep -q "Preparando canal" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Refresh silencioso al cambiar canal" || echo "  ⚠️  Refresh silencioso NO agregado"
echo ""
echo "M3u8Extractor.kt:"
grep -q "connectTimeout(10" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Timeouts de 10s" || echo "  ⚠️  Timeouts NO cambiados"
grep -q "MAX_PROF = 5" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ MAX_PROF = 5" || echo "  ⚠️  MAX_PROF NO cambiado"
grep -q "videoUrl" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ Patrones modernos" || echo "  ⚠️  Patrones NO agregados"

echo ""
echo "✅✅✅ Paso 40 completo — 4 mejoras aplicadas"
echo ""
echo "📌 Qué hace ahora la app:"
echo "   📦 Buffer de 8s a 45s (menos congelamientos)"
echo "   ⏱️  Auto-refresh cada 8 min (elimina pausa/reanudación)"
echo "   🔄 Refresh silencioso al cambiar canal (sin spinner)"
echo "   🎯 Extractor con 5 patrones más (mejor cobertura)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"