#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-flujo"

echo "📝 Implementando flujo final + sacando LOG..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# PASO 1 — SACAR EL PANEL DE LOG
# ═══════════════════════════════════════════════════════════

# 1a) Sacar el bloque del panel de log (botón + panel)
log_panel_pattern = r'\n        // ═+\n        // LOG PANEL \(DEBUG\).*?// FIN LOG PANEL\n        // ═+\n'
content = re.sub(log_panel_pattern, '\n', content, flags=re.DOTALL)

# 1b) Sacar también el botón suelto del LOG si quedó
button_log_pattern = r'\n        Box\(\n            Modifier\n                \.align\(Alignment\.TopStart\)\n                \.padding\(16\.dp\)\n                \.clip\(RoundedCornerShape\(10\.dp\)\)\n                \.background\(Color\(0xCC000000\)\)\n                \.border\(1\.dp, Color\(0xFFFF6B6B\), RoundedCornerShape\(10\.dp\)\)\n                \.clickable \{ mostrarLogPanel = !mostrarLogPanel \}\n                \.padding\(horizontal = 12\.dp, vertical = 8\.dp\)\n        \) \{\n            Text\(\n                if \(mostrarLogPanel\) "🐛 LOG ▼" else "🐛 LOG ▲",.*?\n            \)\n        \}\n'
content = re.sub(button_log_pattern, '\n', content, flags=re.DOTALL)

# 1c) Sacar los estados del log
content = re.sub(r'\n    var mostrarLogPanel by remember \{ mutableStateOf\(false\) \}', '', content)
content = re.sub(r'\n    var logs by remember \{ mutableStateOf\(listOf<String>\(\)\) \}', '', content)
content = re.sub(r'\n    var webViewTimeout by remember \{ mutableStateOf\(false\) \}', '', content)

# 1d) Restaurar addLog simple (sin panel)
content = content.replace(
    '''    val addLog: (String) -> Unit = { msg ->
        Log.d(TAG, msg)
        logs = (logs + msg).takeLast(50)
    }''',
    '''    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }'''
)

# 1e) Por si quedó otra variante
content = re.sub(
    r'    val addLog: \(String\) -> Unit = \{ msg ->\n        Log\.d\(TAG, msg\)\n        logs = .*?\n    \}',
    '    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }',
    content,
    flags=re.DOTALL
)

print("✅ Panel de log eliminado")

# ═══════════════════════════════════════════════════════════
# PASO 2 — AGREGAR ESTADOS DEL NUEVO FLUJO
# ═══════════════════════════════════════════════════════════

if "var contadorErrores by remember" not in content:
    ancla = "    var urlsCandidatas by remember { mutableStateOf(listOf<String>()) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + """
    // Contador de errores para el flujo de auto-recovery
    var contadorErrores by remember { mutableIntStateOf(0) }
    // Mensaje temporal "Sin señal, buscando..." (3 seg)
    var mostrandoSinSenal by remember { mutableStateOf(false) }
    // Mensaje final "Evento sin señal"
    var eventoMuerto by remember { mutableStateOf(false) }""",
            1
        )
        print("✅ Estados del nuevo flujo agregados")

# ═══════════════════════════════════════════════════════════
# PASO 3 — REEMPLAZAR EL onPlayerError CON EL NUEVO FLUJO
# ═══════════════════════════════════════════════════════════

# Buscar el bloque completo del onPlayerError actual y reemplazarlo
# El patrón busca desde "override fun onPlayerError" hasta el cierre antes de "override fun onPlaybackStateChanged"
patron_error = r'                    override fun onPlayerError\(e: PlaybackException\) \{.*?\n                    \}\n                    override fun onPlaybackStateChanged'

nuevo_error = '''                    override fun onPlayerError(e: PlaybackException) {
                        val code = e.errorCodeName
                        exoError = "$code: ${e.message?.take(160)}"
                        addLog("❌ $code")

                        if (todosFallaron) return
                        if (eventoMuerto) return

                        scope.launch {
                            contadorErrores++
                            addLog("🔢 Error #$contadorErrores")

                            // ═══════════════════════════════════════════════════
                            // FLUJO DE RECUPERACIÓN
                            // 1-2 → retry misma URL (silencioso)
                            // 3   → auto-refresh (URL fresca)
                            // 4   → retry URL fresca
                            // 5   → "Sin señal, buscando otra..." + cambio de canal
                            // ═══════════════════════════════════════════════════

                            when (contadorErrores) {
                                1, 2 -> {
                                    // Retry silencioso con misma URL
                                    addLog("🔄 Reintento silencioso $contadorErrores/4")
                                    delay(1500L * contadorErrores)
                                    exoError = null
                                    reloadTrigger++
                                }

                                3 -> {
                                    // Auto-refresh: extraer URL fresca
                                    addLog("🔄 Auto-refresh (URL fresca)")

                                    // Si hay candidatos ya extraídos, usar el siguiente
                                    if (urlsCandidatas.size > indiceCandidato + 1) {
                                        indiceCandidato++
                                        delay(500)
                                        exoError = null
                                    } else {
                                        val fresh = try {
                                            M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                                        } catch (ex: Exception) { null }
                                        if (fresh != null) {
                                            cookies = M3u8Extractor.cookieString()
                                            exoError = null
                                            m3u8Url = fresh
                                        } else {
                                            exoError = null
                                            reloadTrigger++
                                        }
                                    }
                                }

                                4 -> {
                                    // Último retry silencioso
                                    addLog("🔄 Reintento final")
                                    delay(1500)
                                    exoError = null
                                    reloadTrigger++
                                }

                                5 -> {
                                    // Mostrar "Sin señal" 3 seg y cambiar de canal
                                    addLog("📡 Canal sin señal → cambiando de canal")
                                    mostrandoSinSenal = true
                                    exoError = null
                                    delay(3000)
                                    mostrandoSinSenal = false

                                    // Buscar siguiente canal del evento
                                    val siguiente = evento.embeds.firstOrNull {
                                        it.url != embedActual.url && it.url !in canalesIntentados
                                    }
                                    if (siguiente != null) {
                                        canalesIntentados = canalesIntentados + embedActual.url
                                        addLog("➡️  Cambiando a ${siguiente.nombre}")
                                        // Resetear contadores para el nuevo canal
                                        contadorErrores = 0
                                        urlsCandidatas = emptyList()
                                        indiceCandidato = 0
                                        reintentos = 0
                                        embedActual = siguiente
                                    } else {
                                        // No hay más canales
                                        addLog("❌ Evento sin señal")
                                        eventoMuerto = true
                                        todosFallaron = true
                                    }
                                }
                            }
                        }
                    }
                    override fun onPlaybackStateChanged'''

match = re.search(patron_error, content, re.DOTALL)
if match:
    content = content[:match.start()] + nuevo_error + content[match.end():]
    print("✅ Nuevo flujo de recuperación aplicado")
else:
    print("⚠️  No encontré el bloque onPlayerError para reemplazar")

# ═══════════════════════════════════════════════════════════
# PASO 4 — RESETEAR CONTADORES AL REPRODUCIR OK
# ═══════════════════════════════════════════════════════════

old_ready = '''                                exoError = null
                                status = "Reproduciendo"
                                addLog("✅ Reproduciendo")
                                reintentos = 0
                                canalesIntentados = canalesIntentados - embedActual.url'''
new_ready = '''                                exoError = null
                                status = "Reproduciendo"
                                addLog("✅ Reproduciendo")
                                reintentos = 0
                                contadorErrores = 0
                                eventoMuerto = false
                                mostrandoSinSenal = false
                                canalesIntentados = canalesIntentados - embedActual.url'''

if old_ready in content:
    content = content.replace(old_ready, new_ready)
    print("✅ Reset de contadores al reproducir OK")

# ═══════════════════════════════════════════════════════════
# PASO 5 — AGREGAR LOS OVERLAYS (Sin señal / Evento muerto)
# ═══════════════════════════════════════════════════════════

# Buscar un lugar donde ponerlos — antes del cierre del Box principal
overlay_code = '''
        // ═══════════════════════════════════════════════════════
        // OVERLAY "SIN SEÑAL, BUSCANDO..." (3 seg)
        // ═══════════════════════════════════════════════════════
        AnimatedVisibility(
            visible = mostrandoSinSenal,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFFFD700), RoundedCornerShape(20.dp))
                    .padding(horizontal = 40.dp, vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(
                    color = Color(0xFFFFD700),
                    strokeWidth = 3.dp,
                    modifier = Modifier.size(42.dp)
                )
                Spacer(Modifier.height(14.dp))
                Text(
                    "📡 Sin señal, buscando otra...",
                    color = Color(0xFFFFD700),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Cambiando de canal en unos segundos",
                    color = Color(0xFF94A3B8),
                    fontSize = 12.sp
                )
            }
        }

        // ═══════════════════════════════════════════════════════
        // OVERLAY "EVENTO SIN SEÑAL" (final, sin recuperación)
        // ═══════════════════════════════════════════════════════
        AnimatedVisibility(
            visible = eventoMuerto,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                Modifier
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFFEF4444), RoundedCornerShape(20.dp))
                    .padding(horizontal = 40.dp, vertical = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(
                    imageVector = AppIcons.advertencia,
                    contentDescription = null,
                    tint = Color(0xFFEF4444),
                    modifier = Modifier.size(52.dp)
                )
                Spacer(Modifier.height(14.dp))
                Text(
                    "📡 Evento sin señal",
                    color = Color(0xFFEF4444),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Probá más tarde",
                    color = Color(0xFF94A3B8),
                    fontSize = 13.sp
                )
            }
        }
'''

# Insertar antes del bloque del WebView (que ya existía)
ancla_overlay = "        if (usarWebView && m3u8Url == null) {"
if ancla_overlay in content and "OVERLAY \"SIN SEÑAL" not in content:
    content = content.replace(ancla_overlay, overlay_code + "\n" + ancla_overlay, 1)
    print("✅ Overlays de Sin señal y Evento muerto agregados")
elif "OVERLAY \"SIN SEÑAL" in content:
    print("ℹ️  Overlays ya existían")
else:
    # Variante: buscar el bloque del WebView con otro espaciado
    if "        if (usarWebView && m3u8Url == null)" in content:
        content = content.replace(
            "        if (usarWebView && m3u8Url == null)",
            overlay_code + "\n        if (usarWebView && m3u8Url == null)",
            1
        )
        print("✅ Overlays agregados (variante)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "mostrarLogPanel" "$UI_DIR/PlayerScreen.kt" && echo "  ⚠️  Quedó algún Log Panel" || echo "  ✓ Log Panel eliminado"
grep -q "contadorErrores" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Contador de errores"
grep -q "mostrandoSinSenal" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado Sin señal"
grep -q "eventoMuerto" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado Evento muerto"
grep -q "Sin señal, buscando otra" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Overlay Sin señal"

echo ""
echo "✅✅✅ Flujo final aplicado"
echo ""
echo "🎯 Nuevo flujo:"
echo "   Error 1-2  → retry silencioso (misma URL)"
echo "   Error 3    → auto-refresh (URL fresca)"
echo "   Error 4    → retry final silencioso"
echo "   Error 5    → '📡 Sin señal, buscando otra...' (3 seg)"
echo "              → cambia al siguiente canal automáticamente"
echo "   Sin más canales → '📡 Evento sin señal · Probá más tarde'"
echo ""
echo "🧹 Log Panel: ELIMINADO"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"