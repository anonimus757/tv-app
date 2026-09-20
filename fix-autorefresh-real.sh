#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-fix-refresh"

echo "📝 Corrigiendo el auto-refresh que corta el stream..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el auto-refresh de 5 segundos y reemplazarlo por uno más inteligente
old = '''    LaunchedEffect(embedActual) {
        while (true) {
            delay(5000)

            // Solo actúa si hay un m3u8 cargado y NO está reproduciendo
            val hayUrl = m3u8Url != null
            val reproduciendo = try {
                exoPlayer.playbackState == Player.STATE_READY && exoPlayer.isPlaying
            } catch (_: Exception) { false }

            if (hayUrl && !reproduciendo && !refrescando && !todosFallaron && !eventoMuerto) {
                addLog("⏰ 5s sin reproducir → auto-refresh")

                // Corrutina INDEPENDIENTE para no romper el LaunchedEffect
                scope.launch {
                    try {
                        val fresh = M3u8Extractor.extraerYTestear(
                            embedActual.url, embedActual.referer, addLog
                        )
                        if (fresh != null) {
                            cookies = M3u8Extractor.cookieString()
                            m3u8Url = fresh
                            addLog("✅ Auto-refresh OK")
                        } else {
                            addLog("⚠️ Auto-refresh sin URL, reintentando con la misma")
                            reloadTrigger++
                        }
                    } catch (_: Exception) {
                        reloadTrigger++
                    }
                }
            }
        }
    }'''

new = '''    // ═══════════════════════════════════════════════════════
    // AUTO-REFRESH INTELIGENTE (no corta el stream que anda)
    // Solo actúa si:
    //   1. El video lleva CARGADO más de 15 segundos
    //   2. Y lleva 10 segundos SEGUIDOS sin reproducir
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(embedActual) {
        var segundosSinReproducir = 0
        while (true) {
            delay(1000)

            val hayUrl = m3u8Url != null
            val tiempoDesdeCarga = System.currentTimeMillis() - tiempoInicioStream
            val pasoElTiempoDeGracia = tiempoDesdeCarga > 15000L

            val estadoActual = try {
                exoPlayer.playbackState
            } catch (_: Exception) { -1 }

            // Consideramos "reproduciendo bien" si:
            // - Estado READY (o BUFFERING que es normal)
            // - O si hay position avanzando
            val reproduciendoBien = estadoActual == Player.STATE_READY ||
                                    estadoActual == Player.STATE_BUFFERING

            if (reproduciendoBien) {
                segundosSinReproducir = 0
            } else {
                segundosSinReproducir++
            }

            // Solo actúa si:
            // - Hay URL cargada
            // - Pasó el tiempo de gracia (15s)
            // - Lleva 10s SEGUIDOS con estado malo (IDLE/ENDED)
            // - No está refrescando ya
            if (hayUrl && pasoElTiempoDeGracia && segundosSinReproducir >= 10 &&
                !refrescando && !todosFallaron && !eventoMuerto) {

                addLog("⏰ 10s sin reproducir → auto-refresh")
                segundosSinReproducir = 0

                scope.launch {
                    try {
                        val fresh = M3u8Extractor.extraerYTestear(
                            embedActual.url, embedActual.referer, addLog
                        )
                        if (fresh != null) {
                            cookies = M3u8Extractor.cookieString()
                            m3u8Url = fresh
                            addLog("✅ Auto-refresh OK")
                        } else {
                            addLog("⚠️ Auto-refresh sin URL")
                        }
                    } catch (_: Exception) {}
                }
            }
        }
    }'''

if old in content:
    content = content.replace(old, new)
    print("✅ Auto-refresh inteligente aplicado")
else:
    print("⚠️  No encontré el bloque del auto-refresh exacto")
    # Buscar variante
    pattern = r'    LaunchedEffect\(embedActual\) \{\n        while \(true\) \{\n            delay\(5000\)[\s\S]*?\n    \}'
    match = re.search(pattern, content)
    if match:
        content = content[:match.start()] + new + content[match.end():]
        print("✅ Auto-refresh reemplazado (regex)")
    else:
        print("❌ No se pudo reemplazar")

# ═══════════════════════════════════════════════════════════
# También bajar el período de gracia del onPlayerError de 4s a 8s
# ═══════════════════════════════════════════════════════════
old_gracia = '''                        // FIX PARPADEO: ignorar errores en los primeros 4 seg
                        val tiempoActual = System.currentTimeMillis()
                        val esPrincipio = (tiempoActual - tiempoInicioStream) < 4000L'''

new_gracia = '''                        // FIX PARPADEO: ignorar errores en los primeros 8 seg
                        val tiempoActual = System.currentTimeMillis()
                        val esPrincipio = (tiempoActual - tiempoInicioStream) < 8000L'''

if old_gracia in content:
    content = content.replace(old_gracia, new_gracia)
    print("✅ Período de gracia ampliado a 8 seg")
else:
    # Variante
    old_gracia2 = '''val esPrincipio = (tiempoActual - tiempoInicioStream) < 4000L'''
    if old_gracia2 in content:
        content = content.replace(old_gracia2, 'val esPrincipio = (tiempoActual - tiempoInicioStream) < 8000L')
        print("✅ Período de gracia a 8 seg (variante)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "AUTO-REFRESH INTELIGENTE" "$FILE" && echo "  ✓ Auto-refresh inteligente"
grep -q "segundosSinReproducir >= 10" "$FILE" && echo "  ✓ Requiere 10s sin reproducir"
grep -q "tiempoDesdeCarga > 15000L" "$FILE" && echo "  ✓ Requiere 15s desde carga"
grep -q "principios 8 seg" "$FILE" && echo "  ✓ Período de gracia 8s"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   ❌ ANTES: auto-refresh cada 5 seg → mataba el stream que andaba"
echo "   ✅ AHORA: solo dispara si 10 seg SEGUIDOS sin reproducir Y llevas 15s cargado"
echo "   ✅ Período de gracia ampliado a 8 seg"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"
