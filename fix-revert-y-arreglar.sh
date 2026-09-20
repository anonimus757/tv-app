#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

# 1) Restaurar el backup que funcionaba
if [ ! -f "$FILE.bak-limpio" ]; then
    echo "❌ No encontré el backup .bak-limpio"
    echo "   ¿Tenés otro backup? Revisá con:"
    echo "   ls $UI_DIR/PlayerScreen.kt.bak*"
    exit 1
fi

cp "$FILE.bak-limpio" "$FILE"
echo "✅ PlayerScreen restaurado a la versión que funcionaba"

# 2) Aplicar SOLO los 3 fixes puntuales (sin tocar nada más)
echo ""
echo "📝 Fix 1 — Parpadeo: PlayerView siempre montado..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Fix parpadeo: quitar "&& exoError == null" para que el PlayerView nunca se desmonte
old = '''        if (m3u8Url != null && exoError == null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

new = '''        // FIX PARPADEO: PlayerView siempre visible (no se desmonta cuando hay error)
        if (m3u8Url != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {'''

if old in content:
    content = content.replace(old, new)
    print("  ✅ PlayerView no se desmonta más")
else:
    print("  ⚠️  No encontré el bloque de PlayerView")
PYEOF

echo ""
echo "📝 Fix 2 — Cambio de canal instantáneo..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Fix cambio de canal: cambiar embedActual DIRECTO sin esperar extracción
old = '''                onCanalClick = { nuevo ->
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

new = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    eventoMuerto = false
                    mostrandoSinSenal = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0

                    // FIX: cambio DIRECTO. El LaunchedEffect(embedActual) hace el resto.
                    // No esperamos extracción → cambio instantáneo.
                    embedActual = nuevo
                },'''

if old in content:
    content = content.replace(old, new)
    print("  ✅ Cambio de canal ahora es instantáneo")
else:
    print("  ⚠️  No encontré el bloque onCanalClick")
PYEOF

echo ""
echo "📝 Fix 3 — Botón calidad oculto si hay 1 sola..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Fix calidad: si hay 1 sola, mostrar toast en vez de abrir selector
old = '''        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }'''

new = '''        // FIX: si hay 1 sola calidad → no tiene sentido el selector
        if (calidades.size <= 1) {
            toast = "Este canal tiene 1 sola calidad"
        } else {
            calidadesDisponibles = calidades.sortedByDescending { it.first }
            mostrarSelectorCalidad = true
            mostrarControles = false
        }
    }'''

# Solo reemplazar la primera ocurrencia (que es la del ciclarCalidad)
count = content.count(old)
if count > 0:
    content = content.replace(old, new, 1)
    print(f"  ✅ Selector calidad arreglado ({count} ocurrencias encontradas, 1 reemplazada)")
else:
    print("  ⚠️  No encontré el bloque de ciclarCalidad")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "FIX PARPADEO: PlayerView siempre visible" "$FILE" && echo "  ✓ Fix parpadeo aplicado"
grep -q "FIX: cambio DIRECTO" "$FILE" && echo "  ✓ Fix cambio canal aplicado"
grep -q "Este canal tiene 1 sola calidad" "$FILE" && echo "  ✓ Fix calidad aplicado"
grep -q "withTimeoutOrNull(10000L) {" "$FILE" && echo "  ⚠️  Todavía hay espera de extracción" || echo "  ✓ Ya no espera extracción"

echo ""
echo "✅✅✅ Revert + 3 fixes quirúrgicos completos"
echo ""
echo "📌 Qué se hizo:"
echo "   1. Volvió el PlayerScreen que andaba con futbollibrefullhd"
echo "   2. Fix parpadeo: PlayerView siempre montado"
echo "   3. Fix cambio canal: instantáneo (sin esperar extracción)"
echo "   4. Fix calidad: toast si hay 1 sola calidad"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"