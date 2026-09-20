#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

# Restaurar desde el backup pre-fase1b
if [ ! -f "$FILE.bak-fase1b" ]; then
    echo "❌ No encontré el backup .bak-fase1b"
    exit 1
fi

cp "$FILE.bak-fase1b" "$FILE"
echo "✅ Restaurado desde .bak-fase1b (versión estable)"

echo "📝 Aplicando SOLO el selector de calidad (bien hecho)..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Auto-refresh: 8 min → 6 min
# ═══════════════════════════════════════════════════════════
if "delay(8 * 60 * 1000L)" in content:
    content = content.replace("delay(8 * 60 * 1000L)", "delay(6 * 60 * 1000L)")
    print("✅ Auto-refresh a 6 min")

# ═══════════════════════════════════════════════════════════
# 2) Estados del selector
# ═══════════════════════════════════════════════════════════
if "var mostrarSelectorCalidad" not in content:
    ancla = "    var zona by remember { mutableStateOf(ZonaUI.VIDEO) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + """
    // 🆕 FASE 1b: Selector de calidad visual
    var mostrarSelectorCalidad by remember { mutableStateOf(false) }
    var calidadesDisponibles by remember { mutableStateOf(listOf<Pair<Int, String>>()) }""",
            1
        )
        print("✅ Estados del selector")

# ═══════════════════════════════════════════════════════════
# 3) Reemplazar ciclarCalidad por abrir el selector
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
        // 🆕 FASE 1b: Detecta calidades disponibles y abre el selector
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

        if (calidades.isEmpty()) {
            calidades.add(1080 to "Full HD (1080p)")
            calidades.add(720 to "HD (720p)")
            calidades.add(480 to "SD (480p)")
        }

        calidadesDisponibles = calidades.sortedByDescending { it.first }
        mostrarSelectorCalidad = true
        mostrarControles = false
    }

    val aplicarCalidad: (Int) -> Unit = { altura ->
        try {
            val params = exoPlayer.trackSelectionParameters
            val nuevo = if (altura <= 0) {
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
    print("✅ ciclarCalidad → abrir selector")
else:
    print("⚠️  No encontré el bloque ciclarCalidad")

# ═══════════════════════════════════════════════════════════
# 4) Overlay del selector (dentro del Box principal)
# ═══════════════════════════════════════════════════════════
selector_overlay = '''
        // ═══════════════════════════════════════════════════════
        // 🆕 FASE 1b: SELECTOR DE CALIDAD VISUAL
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

                    // Opciones de calidad
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

ancla_overlay = '''        // ═══════════════════════════════════════════════════════
        // OVERLAY "SIN SEÑAL, BUSCANDO..." (3 seg)
        // ═══════════════════════════════════════════════════════'''

if ancla_overlay in content and "SELECTOR DE CALIDAD VISUAL" not in content:
    content = content.replace(ancla_overlay, selector_overlay, 1)
    print("✅ Overlay del selector agregado")

# ═══════════════════════════════════════════════════════════
# 5) Componente SelectorCalidadItem (AL FINAL DEL ARCHIVO, top-level)
# ═══════════════════════════════════════════════════════════
if "private fun SelectorCalidadItem" not in content:
    componente = '''

// ═══════════════════════════════════════════════════════════
// 🆕 FASE 1b: Item del selector de calidad (top-level)
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

    # Agregar al final del archivo, DESPUÉS del último "}" que cierra PlayerScreen
    content = content.rstrip() + "\n" + componente
    print("✅ Componente SelectorCalidadItem (top-level)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "private fun SelectorCalidadItem" "$FILE" | xargs -I {} echo "  SelectorCalidadItem: {} (debe ser 1)"
grep -q "SELECTOR DE CALIDAD VISUAL" "$FILE" && echo "  ✓ Overlay del selector"
grep -q "delay(6 \* 60 \* 1000L)" "$FILE" && echo "  ✓ Auto-refresh a 6 min"

echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"