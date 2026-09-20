#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

# ═══════════════════════════════════════════════════════════
# PASO 1 — Restaurar la versión que funcionaba (fix-cero-espera)
# ═══════════════════════════════════════════════════════════
echo "🔄 Restaurando versión funcional (con candidatos)..."

if [ -f "$UI_DIR/PlayerScreen.kt.bak-flujo" ]; then
    cp "$UI_DIR/PlayerScreen.kt.bak-flujo" "$UI_DIR/PlayerScreen.kt"
    echo "✅ Restaurado desde .bak-flujo (versión con candidatos)"
else
    echo "❌ No encontré .bak-flujo"
    exit 1
fi

echo ""
echo "📝 Agregando overlay de Sin Señal + Evento Muerto (SIN tocar la lógica de reproducción)..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Agregar estados para los overlays
# ═══════════════════════════════════════════════════════════
if "var mostrandoSinSenal" not in content:
    ancla = "    var urlsCandidatas by remember { mutableStateOf(listOf<String>()) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + """
    // Overlays de estado
    var mostrandoSinSenal by remember { mutableStateOf(false) }
    var eventoMuerto by remember { mutableStateOf(false) }""",
            1
        )
        print("✅ Estados agregados")

# ═══════════════════════════════════════════════════════════
# 2) SACAR el panel de LOG
# ═══════════════════════════════════════════════════════════

import re

# Sacar botón LOG
button_pattern = r'\n        Box\(\n            Modifier\n                \.align\(Alignment\.TopStart\).*?🐛 LOG.*?\n            \)\n        \}\n'
content = re.sub(button_pattern, '\n', content, flags=re.DOTALL)

# Sacar panel LOG completo
panel_pattern = r'\n        if \(mostrarLogPanel\) \{.*?// FIN LOG PANEL\n        // ═+\n'
content = re.sub(panel_pattern, '\n', content, flags=re.DOTALL)

# Sacar el estado mostrarLogPanel
content = re.sub(r'\n    var mostrarLogPanel by remember \{ mutableStateOf\(false\) \}', '', content)

# Restaurar addLog simple
content = re.sub(
    r'    val addLog: \(String\) -> Unit = \{ msg ->\n        Log\.d\(TAG, msg\)\n        logs = .*?\n    \}',
    '    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }',
    content,
    flags=re.DOTALL
)

# Sacar estado logs
content = re.sub(r'\n    var logs by remember \{ mutableStateOf\(listOf<String>\(\)\) \}', '', content)

print("✅ Log Panel eliminado")

# ═══════════════════════════════════════════════════════════
# 3) MODIFICAR el onPlayerError para mostrar overlays después de reintentos
# ═══════════════════════════════════════════════════════════

# Buscar la sección donde dice "todosFallaron = true" y "Todos los canales fallaron"
# y reemplazarla con la lógica nueva: primero "Sin señal" → cambio de canal → "Evento muerto"

# Buscar el bloque donde se agotan los canales del evento
old_block = '''                                if (siguiente == null) {
                                    addLog("❌ Todos los canales fallaron")
                                    todosFallaron = true
                                    exoError = "Todos los canales fallaron. Probá más tarde."
                                    return@launch
                                }'''

new_block = '''                                if (siguiente == null) {
                                    addLog("📡 Evento sin señal")
                                    eventoMuerto = true
                                    todosFallaron = true
                                    exoError = null
                                    return@launch
                                }'''

if old_block in content:
    content = content.replace(old_block, new_block)
    print("✅ Mensaje 'todos fallaron' → overlay 'Evento sin señal'")

# Buscar el otro bloque similar (por si hay 2)
old_block2 = '''                                            if (siguiente == null) {
                                                todosFallaron = true
                                                exoError = "Todos los canales fallaron. Probá más tarde."
                                                return@launch
                                            }'''

new_block2 = '''                                            if (siguiente == null) {
                                                addLog("📡 Evento sin señal")
                                                eventoMuerto = true
                                                todosFallaron = true
                                                exoError = null
                                                return@launch
                                            }'''

if old_block2 in content:
    content = content.replace(old_block2, new_block2)
    print("✅ Segundo bloque 'todos fallaron' → overlay")

# ═══════════════════════════════════════════════════════════
# 4) AGREGAR el overlay ANTES de cambiar de canal (3 seg de "Sin señal")
# ═══════════════════════════════════════════════════════════

# Buscar donde dice "Cambiando a ${siguiente.nombre}" y meter el delay de "Sin señal"
old_cambio1 = '''                                canalesIntentados = canalesIntentados + embedActual.url
                                addLog("➡️  Cambiando a ${siguiente.nombre}")
                                avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                exoError = null
                                status = "Cambiando de canal..."
                                delay(2000)
                                avisoCambio = null
                                reintentos = 0
                                embedActual = siguiente'''

new_cambio1 = '''                                canalesIntentados = canalesIntentados + embedActual.url
                                addLog("📡 Sin señal, buscando otro canal...")
                                mostrandoSinSenal = true
                                exoError = null
                                delay(3000)
                                mostrandoSinSenal = false
                                addLog("➡️  Cambiando a ${siguiente.nombre}")
                                reintentos = 0
                                urlsCandidatas = emptyList()
                                indiceCandidato = 0
                                contadorErrores = 0
                                embedActual = siguiente'''

if old_cambio1 in content:
    content = content.replace(old_cambio1, new_cambio1)
    print("✅ Overlay 'Sin señal' agregado antes del cambio de canal (bloque 1)")
else:
    print("⚠️  Bloque de cambio 1 no encontrado, buscando variante...")

# Variante 2 (por el segundo bloque)
old_cambio2 = '''                                            canalesIntentados = canalesIntentados + embedActual.url
                                            addLog("➡️  Cambiando a ${siguiente.nombre}")
                                            avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                            exoError = null
                                            status = "Cambiando de canal..."
                                            delay(2000)
                                            avisoCambio = null
                                            reintentos = 0
                                            embedActual = siguiente'''

new_cambio2 = '''                                            canalesIntentados = canalesIntentados + embedActual.url
                                            addLog("📡 Sin señal, buscando otro canal...")
                                            mostrandoSinSenal = true
                                            exoError = null
                                            delay(3000)
                                            mostrandoSinSenal = false
                                            addLog("➡️  Cambiando a ${siguiente.nombre}")
                                            reintentos = 0
                                            urlsCandidatas = emptyList()
                                            indiceCandidato = 0
                                            embedActual = siguiente'''

if old_cambio2 in content:
    content = content.replace(old_cambio2, new_cambio2)
    print("✅ Overlay 'Sin señal' agregado (bloque 2)")

# ═══════════════════════════════════════════════════════════
# 5) RESETEAR overlays cuando reproduce OK
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
                                mostrandoSinSenal = false
                                eventoMuerto = false
                                canalesIntentados = canalesIntentados - embedActual.url'''

if old_ready in content:
    content = content.replace(old_ready, new_ready)
    print("✅ Reset de overlays al reproducir OK")

# ═══════════════════════════════════════════════════════════
# 6) RESETEAR eventoMuerto al cambiar de canal manualmente
# ═══════════════════════════════════════════════════════════

old_manual = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO'''

new_manual = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    eventoMuerto = false
                    mostrandoSinSenal = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO'''

if old_manual in content:
    content = content.replace(old_manual, new_manual)
    print("✅ Reset de overlay al cambiar de canal manual")

# ═══════════════════════════════════════════════════════════
# 7) AGREGAR los 2 overlays visuales
# ═══════════════════════════════════════════════════════════

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
            }
        }

        // ═══════════════════════════════════════════════════════
        // OVERLAY "EVENTO SIN SEÑAL" (final)
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
                    .padding(horizontal = 44.dp, vertical = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("📡", fontSize = 48.sp)
                Spacer(Modifier.height(12.dp))
                Text(
                    "Evento sin señal",
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

# Insertar antes del bloque del WebView
ancla = "        if (usarWebView && m3u8Url == null) {"
if ancla in content and "OVERLAY \"SIN SEÑAL" not in content:
    content = content.replace(ancla, overlay_code + "\n" + ancla, 1)
    print("✅ Overlays visuales agregados")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "mostrarLogPanel" "$UI_DIR/PlayerScreen.kt" && echo "  ⚠️  Quedó LOG" || echo "  ✓ Log Panel eliminado"
grep -q "mostrandoSinSenal" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado Sin señal"
grep -q "eventoMuerto" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado Evento muerto"
grep -q "urlsCandidatas" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Sistema de candidatos (respaldo)"
grep -q "Sin señal, buscando otra" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Overlay Sin señal"

echo ""
echo "✅✅✅ LISTO — Base que funciona + overlays nuevos"
echo ""
echo "🎯 Flujo completo:"
echo "   1. Tocás canal → extrae principal + 3 respaldos en paralelo"
echo "   2. Arranca a reproducir YA"
echo "   3. Si falla principal → cambio silencioso a respaldo"
echo "   4. Si fallan los 4 → '📡 Sin señal, buscando otra...' (3 seg)"
echo "   5. Cambia al siguiente canal del evento"
echo "   6. Si no hay más canales → '📡 Evento sin señal · Probá más tarde'"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"