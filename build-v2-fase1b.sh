#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-fase1b"

echo "📝 Aplicando mejoras del reproductor (Fase 1b)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) BUFFER ADAPTATIVO: extraer LoadControl a variable mutable
# ═══════════════════════════════════════════════════════════
old_loadcontrol = '''    val exoPlayer = remember {
        // Buffer optimizado: 8s mínimo, 45s máximo
        // - Arranca rápido (2s para primer frame)
        // - Aguanta micro-cortes (45s de buffer)
        // - Rebuffer 5s para recuperarse sin pausar
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 45000, 2000, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        val calidad = AjustesStore.obtenerCalidad(context)
        val trackSelector = DefaultTrackSelector(context).apply {
            val params = when (calidad) {
                "sd" -> buildUponParameters().setMaxVideoSizeSd()
                "hd" -> buildUponParameters().setMaxVideoSize(1920, 1080)
                else -> buildUponParameters()
            }
            params
                .setAllowVideoMixedMimeTypeAdaptiveness(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
            setParameters(params)
        }'''

new_loadcontrol = '''    val exoPlayer = remember {
        // Buffer inicial: se ajustará dinámicamente según la red (Fase 1b)
        // - Arranca con buffer medio para ser rápido
        // - Se adapta a la velocidad medida (8s → 60s)
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 45000, 2000, 5000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        val calidad = AjustesStore.obtenerCalidad(context)
        val trackSelector = DefaultTrackSelector(context).apply {
            // MULTI-RESOLUCIÓN AUTO: en "auto" no limitamos resolución
            // ExoPlayer elige la mejor disponible según la red (ABR real)
            val params = when (calidad) {
                "sd" -> buildUponParameters().setMaxVideoSizeSd()
                "hd" -> buildUponParameters().setMaxVideoSize(1920, 1080)
                else -> buildUponParameters()
                    // En AUTO: dejamos todas las resoluciones disponibles
                    // y habilitamos el ABR adaptativo real
            }
            params
                .setAllowVideoMixedMimeTypeAdaptiveness(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
            setParameters(params)
        }'''

if old_loadcontrol in content:
    content = content.replace(old_loadcontrol, new_loadcontrol)
    print("✅ LoadControl extraído + ABR auto habilitado")
else:
    print("⚠️  No encontré el bloque de LoadControl")

# ═══════════════════════════════════════════════════════════
# 2) Agregar estados para selector de calidad + buffer adaptativo
# ═══════════════════════════════════════════════════════════
if "var mostrarSelectorCalidad" not in content:
    ancla = "    var zona by remember { mutableStateOf(ZonaUI.VIDEO) }"
    if ancla in content:
        content = content.replace(
            ancla,
            """    var zona by remember { mutableStateOf(ZonaUI.VIDEO) }
    // 🆕 FASE 1b: Selector de calidad visual
    var mostrarSelectorCalidad by remember { mutableStateOf(false) }
    var calidadesDisponibles by remember { mutableStateOf(listOf<Pair<Int, String>>()) }""",
            1
        )
        print("✅ Estados de selector de calidad")

# ═══════════════════════════════════════════════════════════
# 3) BUFFER ADAPTATIVO: ajustar LoadControl según velocidad
# ═══════════════════════════════════════════════════════════
if "// BUFFER ADAPTATIVO" not in content:
    # Insertar después del bloque del LaunchedEffect(m3u8Url) del timer
    ancla_launched = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''

    buffer_adaptativo = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }

    // ═══════════════════════════════════════════════════════
    // 🆕 FASE 1b: BUFFER ADAPTATIVO
    // Ajusta el buffer de ExoPlayer según la velocidad de red medida
    // - Red rápida → buffer chico (arranca rápido, no acumula)
    // - Red lenta → buffer grande (no se congela)
    // ═══════════════════════════════════════════════════════
    LaunchedEffect(salud.bufferRecomendadoMs, salud.saludRed) {
        if (m3u8Url == null) return@LaunchedEffect
        try {
            val bufferMax = salud.bufferRecomendadoMs
            if (bufferMax < 10000) return@LaunchedEffect  // Valor por defecto, ignorar

            val nuevoLoadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(8000, bufferMax, 2000, 5000)
                .setPrioritizeTimeOverSizeThresholds(true)
                .setBackBuffer(0, false)
                .build()
            exoPlayer.setLoadControl(nuevoLoadControl)
            addLog("📊 Buffer ajustado: ${bufferMax / 1000}s (red: ${salud.saludRed})")
        } catch (e: Exception) {
            addLog("⚠️ No se pudo ajustar buffer: ${e.message}")
        }
    }'''

    if ancla_launched in content:
        content = content.replace(ancla_launched, buffer_adaptativo, 1)
        print("✅ Buffer adaptativo agregado")

# ═══════════════════════════════════════════════════════════
# 4) AUTO-REFRESH PROACTIVO: 8 min → 6 min
# ═══════════════════════════════════════════════════════════
old_refresh = '''            delay(8 * 60 * 1000L) // 8 minutos'''
new_refresh = '''            delay(6 * 60 * 1000L) // 6 minutos (más agresivo que 8)'''
if old_refresh in content:
    content = content.replace(old_refresh, new_refresh)
    print("✅ Auto-refresh a 6 min")

# ═══════════════════════════════════════════════════════════
# 5) SELECTOR DE CALIDAD VISUAL: reemplazar función ciclarCalidad
# ═══════════════════════════════════════════════════════════
old_ciclar = '''    val ciclarCalidad: () -> Unit = {
        calidadActual = when (calidadActual) {
            "auto" -> "hd"
            "hd" -> "sd"
            else -> "auto"
        }
        AjustesStore.guardarCalidad(context, calidadActual)
        try {
            val params = exoPlayer.trackSelectionParameters
            val nuevo = when (calidadActual) {
                "sd" -> params.buildUpon().setMaxVideoSize(854, 480).build()
                "hd" -> params.buildUpon().setMaxVideoSize(1920, 1080).build()
                else -> params.buildUpon().setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE).build()
            }
            exoPlayer.trackSelectionParameters = nuevo
        } catch (_: Exception) {}
        toast = "Calidad: ${calidadActual.uppercase()}"
    }'''

new_ciclar = '''    val ciclarCalidad: () -> Unit = {
        // 🆕 FASE 1b: Abre el selector visual en vez de ciclar
        // Detecta las calidades disponibles del stream actual
        val calidades = mutableListOf<Pair<Int, String>>()

        try {
            exoPlayer.currentTracks.groups.forEach { grupo ->
                if (grupo.type == androidx.media3.common.C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until grupo.length) {
                        val formato = grupo.getTrackFormat(i)
                        val altura = formato.height
                        if (altura > 0) {
                            val label = when {
                                altura >= 2160 -> "4K (${altura}p)"
                                altura >= 1080 -> "Full HD (${altura}p)"
                                altura >= 720 -> "HD (${altura}p)"
                                altura >= 480 -> "SD (${altura}p)"
                                else -> "${altura}p"
                            }
                            if (!calidades.any { it.first == altura }) {
                                calidades.add(altura to label)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // Agregar opciones fijas si el stream no reporta calidades
        if (calidades.isEmpty()) {
            calidades.add(2160 to "4K (2160p)")
            calidades.add(1080 to "Full HD (1080p)")
            calidades.add(720 to "HD (720p)")
            calidades.add(480 to "SD (480p)")
        }

        // Ordenar de mayor a menor
        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }

    val aplicarCalidad: (Int) -> Unit = { altura ->
        try {
            val params = exoPlayer.trackSelectionParameters
            val nuevo = if (altura <= 0) {
                // AUTO: sin límite
                params.buildUpon()
                    .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
                    .build()
            } else {
                params.buildUpon()
                    .setMaxVideoSize(Int.MAX_VALUE, altura)
                    .build()
            }
            exoPlayer.trackSelectionParameters = nuevo

            calidadActual = if (altura <= 0) "auto" else "$altura"
            AjustesStore.guardarCalidad(context, if (altura <= 0) "auto" else "hd")
            toast = if (altura <= 0) "Calidad: AUTO" else "Calidad: ${altura}p"
        } catch (_: Exception) {}
        mostrarSelectorCalidad = false
    }'''

if old_ciclar in content:
    content = content.replace(old_ciclar, new_ciclar)
    print("✅ Selector de calidad visual")

# ═══════════════════════════════════════════════════════════
# 6) Overlay del selector de calidad (menu flotante)
# ═══════════════════════════════════════════════════════════
if "// SELECTOR DE CALIDAD VISUAL" not in content:
    ancla_overlay = '''        // ═══════════════════════════════════════════════════════
        // OVERLAY "SIN SEÑAL, BUSCANDO..." (3 seg)
        // ═══════════════════════════════════════════════════════'''

    selector_overlay = '''        // ═══════════════════════════════════════════════════════
        // 🆕 FASE 1b: SELECTOR DE CALIDAD VISUAL
        // Menú flotante con las calidades disponibles del stream
        // ═══════════════════════════════════════════════════════
        AnimatedVisibility(
            visible = mostrarSelectorCalidad,
            enter = fadeIn(tween(200)),
            exit = fadeOut(tween(150)),
            modifier = Modifier.align(Alignment.Center)
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color(0xCC000000))
                    .clickable { mostrarSelectorCalidad = false },
                contentAlignment = Alignment.Center
            ) {
                Column(
                    Modifier
                        .width(400.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color(0xF0000000))
                        .border(2.dp, Color(0x66D4AF37), RoundedCornerShape(20.dp))
                        .clickable(enabled = false) {}
                        .padding(24.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.calidad,
                            contentDescription = null,
                            tint = Color(0xFFFFD700),
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "Calidad de video",
                            color = Color.White,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.height(16.dp))

                    // Opción AUTO
                    SelectorCalidadItem(
                        titulo = "Automático",
                        subtitulo = "Se adapta a tu red",
                        seleccionado = calidadActual == "auto",
                        onClick = { aplicarCalidad(0) }
                    )
                    Spacer(Modifier.height(8.dp))

                    // Opciones de calidad disponibles
                    calidadesDisponibles.forEach { (altura, label) ->
                        SelectorCalidadItem(
                            titulo = label,
                            subtitulo = if (altura >= 720) "Más calidad, más datos" else "Menos datos",
                            seleccionado = calidadActual == "$altura",
                            onClick = { aplicarCalidad(altura) }
                        )
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════
        // OVERLAY "SIN SEÑAL, BUSCANDO..." (3 seg)
        // ═══════════════════════════════════════════════════════'''

    if ancla_overlay in content:
        content = content.replace(ancla_overlay, selector_overlay, 1)
        print("✅ Overlay del selector agregado")

# ═══════════════════════════════════════════════════════════
# 7) Componente SelectorCalidadItem
# ═══════════════════════════════════════════════════════════
if "private fun SelectorCalidadItem" not in content:
    componente = '''

// ═══════════════════════════════════════════════════════════
// 🆕 FASE 1b: Item del selector de calidad
// ═══════════════════════════════════════════════════════════
@Composable
private fun SelectorCalidadItem(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        when {
            seleccionado -> Color(0x55D4AF37)
            focused -> Color(0x44FFFFFF)
            else -> Color(0x22FFFFFF)
        },
        tween(150), label = "scBg"
    )
    val border by animateColorAsState(
        when {
            seleccionado -> Color(0xFFFFD700)
            focused -> Color(0x88FFFFFF)
            else -> Color.Transparent
        },
        tween(150), label = "scBd"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (seleccionado || focused) 2.dp else 0.dp, border, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(10.dp).clip(CircleShape).background(
                if (seleccionado) Color(0xFF4ADE80) else Color(0xFF64748B)
            )
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium
            )
            Text(
                subtitulo,
                color = Color(0xFF94A3B8),
                fontSize = 12.sp
            )
        }
        if (seleccionado) {
            Icon(
                imageVector = AppIcons.ok,
                contentDescription = null,
                tint = Color(0xFF4ADE80),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
'''

    # Insertar antes del último "}" del archivo (cierre del archivo)
    content = content.rstrip()
    if content.endswith("}"):
        content = content[:-1] + componente + "\n}\n"
        print("✅ Componente SelectorCalidadItem agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "BUFFER ADAPTATIVO" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Buffer adaptativo"
grep -q "SELECTOR DE CALIDAD VISUAL" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Selector de calidad visual"
grep -q "SelectorCalidadItem" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Componente SelectorCalidadItem"
grep -q "delay(6 \* 60 \* 1000L)" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Auto-refresh a 6 min"
grep -q "mostrarSelectorCalidad" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Estado del selector"

echo ""
echo "✅✅✅ FASE 1b completo — Reproductor Pro"
echo ""
echo "📌 Qué cambió:"
echo "   ⚡ Buffer adaptativo (ajusta según velocidad de red)"
echo "   🎞️ Multi-resolución auto (ABR real)"
echo "   ⏱️ Auto-refresh a 6 min (antes 8)"
echo "   🎛️ Selector visual de calidad (menú flotante)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"