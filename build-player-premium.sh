#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
[ ! -f "$PLAYER" ] && { echo "❌ No existe $PLAYER"; exit 1; }
cp "$PLAYER" "${PLAYER}.bak.premium.$(date +%s)"
echo "✅ Backup: ${PLAYER}.bak.premium.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# 1. Agregar imports que falten
# ═══════════════════════════════════════════════════════════
imports_extra = [
    'import androidx.compose.animation.core.FastOutSlowInEasing',
    'import androidx.compose.animation.core.LinearEasing',
    'import androidx.compose.animation.core.RepeatMode',
    'import androidx.compose.animation.core.animateFloat',
    'import androidx.compose.animation.core.infiniteRepeatable',
    'import androidx.compose.animation.core.rememberInfiniteTransition',
    'import androidx.compose.ui.draw.rotate',
]
lineas = c.split('\n')
for imp in imports_extra:
    if imp not in c:
        # Insertar después del último import de animation.core
        idx = -1
        for i, l in enumerate(lineas):
            if l.startswith('import androidx.compose.animation.core'):
                idx = i
        if idx > 0:
            lineas.insert(idx + 1, imp)

c = '\n'.join(lineas)

# ═══════════════════════════════════════════════════════════
# 2. Encontrar el marker "TOP OVERLAY" y reemplazar todo lo de después
# ═══════════════════════════════════════════════════════════
marker = '// TOP OVERLAY'
idx_marker = c.find(marker)
if idx_marker < 0:
    print("❌ No encontré el marker TOP OVERLAY")
    raise SystemExit(1)

# Retroceder hasta el inicio de la línea del ═ anterior
inicio_linea = c.rfind('\n', 0, idx_marker)
if inicio_linea < 0:
    inicio_linea = idx_marker
inicio_seccion = c.rfind('\n', 0, inicio_linea)
if inicio_seccion < 0:
    inicio_seccion = 0
inicio_seccion = c.rfind('\n', 0, inicio_seccion)
if inicio_seccion < 0:
    inicio_seccion = 0
inicio_seccion += 1

# Recortar main_part
main_part = c[:inicio_seccion].rstrip() + '\n\n'

print(f"✅ Lógica principal preservada: {len(main_part)} bytes")

# ═══════════════════════════════════════════════════════════
# 3. Escribir los nuevos composables premium
# ═══════════════════════════════════════════════════════════
nuevos_composables = '''// ═══════════════════════════════════════════════════════════
// TOP OVERLAY — Premium
// ═══════════════════════════════════════════════════════════

@Composable
private fun TopOverlay(
    evento: Evento,
    embedActual: Embed,
    segundosActivo: Int,
    salud: SignalHealthMonitor.Salud,
    reintentos: Int,
    maxReintentos: Int,
    seleccionado: Boolean,
    refrescando: Boolean,
    onRefrescar: () -> Unit
) {
    val pulse = rememberInfiniteTransition(label = "livePulse")
    val pulseAlpha by pulse.animateFloat(
        initialValue = 0.4f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "pulseAlpha"
    )

    Box(
        Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Black.copy(alpha = 0.88f),
                        Color.Black.copy(alpha = 0.6f),
                        Color.Black.copy(alpha = 0.2f),
                        Color.Transparent
                    )
                )
            )
            .padding(horizontal = 28.dp, vertical = 22.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                // Live indicator row
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.alpha(pulseAlpha).size(8.dp).clip(CircleShape)
                            .background(Color(0xFFFF3B30))
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "EN VIVO",
                        color = Color(0xFFFF6B5D),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 2.sp
                    )
                    Spacer(Modifier.width(16.dp))
                    Text(
                        formatoTiempo(segundosActivo),
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = 1.sp
                    )
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    evento.descripcion,
                    color = Color.White,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = 32.sp,
                    letterSpacing = (-0.4).sp
                )
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(width = 4.dp, height = 14.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(Color(0xFFFFD700))
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        embedActual.nombre,
                        color = Color(0xFFFFD700),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text("  ·  ", color = Color(0xFF64748B), fontSize = 14.sp)
                    Text(evento.hora, color = Color(0xFFCBD5E1), fontSize = 13.sp)
                }
                Spacer(Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PillSalud(salud)
                    PillMinimal(texto = formatoResolucion(salud.alto))
                    PillMinimal(texto = formatoBitrate(salud.bitrateBps))
                }
                if (reintentos > 0) {
                    Spacer(Modifier.height(10.dp))
                    Row(
                        Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color(0x33FACC15))
                            .border(1.dp, Color(0x88FACC15), RoundedCornerShape(8.dp))
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("⟳", color = Color(0xFFFACC15), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "Reintento $reintentos/$maxReintentos",
                            color = Color(0xFFFACC15),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            Spacer(Modifier.width(20.dp))

            BotonRefrescar(
                seleccionado = seleccionado,
                refrescando = refrescando,
                onClick = onRefrescar
            )
        }
    }
}

@Composable
private fun PillMinimal(texto: String) {
    Box(
        Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color.White.copy(alpha = 0.07f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(20.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Text(
            texto,
            color = Color.White.copy(alpha = 0.9f),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.3.sp
        )
    }
}

@Composable
private fun PillSalud(salud: SignalHealthMonitor.Salud) {
    val color = colorSalud(salud.porcentaje)
    Row(
        Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.45f), RoundedCornerShape(20.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            val bloques = 4
            val activos = (salud.porcentaje * bloques / 100).coerceIn(0, bloques)
            for (i in 0 until bloques) {
                Box(
                    Modifier
                        .width(3.dp)
                        .height((4 + i * 3).dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(if (i < activos) color else color.copy(alpha = 0.25f))
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Text(
            "${salud.porcentaje}%",
            color = color,
            fontSize = 12.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp
        )
    }
}

@Composable
private fun BotonRefrescar(
    seleccionado: Boolean,
    refrescando: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        if (seleccionado || focused) 1.06f else 1f,
        tween(180), label = "rScale"
    )

    Row(
        Modifier
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .clickable(enabled = !refrescando) { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.horizontalGradient(
                    when {
                        seleccionado -> listOf(Color(0xFFFFD700), Color(0xFFD4AF37))
                        focused -> listOf(Color.White.copy(alpha = 0.15f), Color.White.copy(alpha = 0.08f))
                        else -> listOf(Color.Black.copy(alpha = 0.5f), Color.Black.copy(alpha = 0.35f))
                    }
                )
            )
            .border(
                width = if (seleccionado || focused) 1.5.dp else 1.dp,
                color = when {
                    seleccionado -> Color(0xFFFFD700)
                    focused -> Color.White.copy(alpha = 0.5f)
                    else -> Color.White.copy(alpha = 0.2f)
                },
                shape = RoundedCornerShape(14.dp)
            )
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (refrescando) {
            CircularProgressIndicator(
                color = if (seleccionado) Color.Black else Color(0xFFFFD700),
                strokeWidth = 2.dp,
                modifier = Modifier.size(18.dp)
            )
        } else {
            Icon(
                imageVector = AppIcons.refrescar,
                contentDescription = "Refrescar",
                tint = if (seleccionado) Color.Black else Color.White,
                modifier = Modifier.size(18.dp)
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(
            if (refrescando) "Refrescando" else "Refrescar",
            color = if (seleccionado) Color.Black else Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.5.sp
        )
    }
}

// ═══════════════════════════════════════════════════════════
// BOTTOM CONTROLS — Premium
// ═══════════════════════════════════════════════════════════

@Composable
private fun BottomControls(
    reproduciendo: Boolean,
    volumen: Float,
    calidad: String,
    canalesCount: Int,
    seleccionado: Boolean,
    idxBottom: Int,
    onTogglePlay: () -> Unit,
    onSubirVol: () -> Unit,
    onBajarVol: () -> Unit,
    onCiclarCalidad: () -> Unit,
    onAbrirPanel: () -> Unit
) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.35f),
                        Color.Black.copy(alpha = 0.7f),
                        Color.Black.copy(alpha = 0.9f)
                    )
                )
            )
            .padding(horizontal = 32.dp, vertical = 22.dp)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(Color.White.copy(alpha = 0.04f))
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(24.dp))
                .padding(horizontal = 10.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            BarButton(
                icono = if (reproduciendo) AppIcons.pausa else AppIcons.play,
                label = null,
                seleccionado = seleccionado && idxBottom == 0,
                grande = true,
                onClick = onTogglePlay
            )
            Spacer(Modifier.width(6.dp))
            BarButton(
                icono = AppIcons.volumenBajo,
                label = null,
                seleccionado = seleccionado && idxBottom == 1,
                onClick = onBajarVol
            )
            Spacer(Modifier.width(4.dp))
            BarButton(
                icono = AppIcons.volumen,
                label = "${(volumen * 100).toInt()}%",
                seleccionado = seleccionado && idxBottom == 2,
                onClick = onSubirVol
            )
            Spacer(Modifier.width(6.dp))
            BarButton(
                icono = AppIcons.calidad,
                label = calidad.uppercase(),
                seleccionado = seleccionado && idxBottom == 3,
                onClick = onCiclarCalidad
            )
            Spacer(Modifier.width(6.dp))
            BarButton(
                icono = AppIcons.canales,
                label = "$canalesCount",
                seleccionado = seleccionado && idxBottom == 4,
                onClick = onAbrirPanel
            )
        }
    }
}

@Composable
private fun BarButton(
    icono: ImageVector,
    label: String?,
    seleccionado: Boolean,
    grande: Boolean = false,
    onClick: () -> Unit
) {
    val scale by animateFloatAsState(
        if (seleccionado) 1.08f else 1f,
        tween(150, easing = FastOutSlowInEasing), label = "bScale"
    )
    val bg by animateColorAsState(
        if (seleccionado) Color(0xFFFFD700) else Color.Transparent,
        tween(150), label = "bBg"
    )

    Column(
        Modifier
            .scale(scale)
            .height(if (grande) 60.dp else 50.dp)
            .widthIn(min = if (grande) 60.dp else 50.dp)
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .padding(horizontal = if (grande) 0.dp else 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = icono,
            contentDescription = label,
            tint = if (seleccionado) Color.Black else Color.White.copy(alpha = 0.95f),
            modifier = Modifier.size(if (grande) 26.dp else 22.dp)
        )
        if (label != null) {
            Spacer(Modifier.height(2.dp))
            Text(
                label,
                color = if (seleccionado) Color.Black else Color.White.copy(alpha = 0.85f),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                letterSpacing = 0.3.sp
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════
// ESTADO (LOADING / ERROR) — Premium
// ═══════════════════════════════════════════════════════════

@Composable
private fun EstadoOverlay(
    error: String?,
    status: String,
    reintentos: Int,
    maxReintentos: Int,
    todosFallaron: Boolean
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .clip(RoundedCornerShape(24.dp))
                .background(
                    Brush.radialGradient(
                        listOf(Color(0xF0050508), Color(0xEE000000))
                    )
                )
                .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(24.dp))
                .padding(horizontal = 44.dp, vertical = 34.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (error == null) {
                Box(
                    Modifier.size(60.dp).clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.05f))
                        .border(1.dp, Color(0xFFFFD700).copy(alpha = 0.3f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(
                        color = Color(0xFFFFD700),
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(28.dp)
                    )
                }
                Spacer(Modifier.height(20.dp))
                Text(
                    status,
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 0.3.sp
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Buscando la mejor señal...",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 12.sp
                )
            } else {
                if (!todosFallaron) {
                    CircularProgressIndicator(
                        color = Color(0xFFFACC15),
                        strokeWidth = 2.5.dp,
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(Modifier.height(20.dp))
                    Text(
                        "Recuperando...",
                        color = Color(0xFFFACC15),
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 0.5.sp
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "Intento $reintentos de $maxReintentos",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 12.sp
                    )
                } else {
                    Box(
                        Modifier.size(64.dp).clip(CircleShape)
                            .background(Color(0xFFEF4444).copy(alpha = 0.15f))
                            .border(1.5.dp, Color(0xFFEF4444).copy(alpha = 0.6f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = AppIcons.advertencia,
                            contentDescription = null,
                            tint = Color(0xFFEF4444),
                            modifier = Modifier.size(30.dp)
                        )
                    }
                    Spacer(Modifier.height(18.dp))
                    Text(
                        "Sin señal",
                        color = Color.White,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 0.5.sp
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Probá otro canal o volvé más tarde",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 13.sp
                    )
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// PANEL LATERAL — Premium
// ═══════════════════════════════════════════════════════════

@Composable
private fun PanelLateral(
    evento: Evento,
    embedActual: Embed,
    todosEventos: List<Evento>,
    onCanalClick: (Embed) -> Unit,
    onEventoClick: (Evento) -> Unit
) {
    val primerItemFocus = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        delay(250)
        try { primerItemFocus.requestFocus() } catch (_: Exception) {}
    }

    Box(
        Modifier
            .width(460.dp)
            .fillMaxHeight()
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color(0xFA0A0A0F),
                        Color(0xF00A0A0F),
                        Color(0xC0000000),
                        Color(0x90000000)
                    )
                )
            )
    ) {
        // Línea dorada vertical a la derecha
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .width(1.dp)
                .fillMaxHeight()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Transparent,
                            Color(0xFFFFD700).copy(alpha = 0.3f),
                            Color(0xFFFFD700).copy(alpha = 0.6f),
                            Color(0xFFFFD700).copy(alpha = 0.3f),
                            Color.Transparent
                        )
                    )
                )
        )

        Column(
            Modifier
                .fillMaxHeight()
                .padding(horizontal = 26.dp, vertical = 30.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFFFFD700)))
                Spacer(Modifier.width(10.dp))
                Text(
                    "CANALES",
                    color = Color(0xFFFFD700),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 3.sp
                )
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color.White.copy(alpha = 0.06f))
                        .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(20.dp))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                ) {
                    Text(
                        "${evento.embeds.size}",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Spacer(Modifier.height(14.dp))
            Text(
                evento.descripcion,
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                lineHeight = 24.sp,
                letterSpacing = (-0.3).sp
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "${evento.hora}  ·  ${evento.fuente}",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 12.sp
            )

            Spacer(Modifier.height(22.dp))

            val otros = todosEventos.filter {
                it.descripcion != evento.descripcion || it.fuente != evento.fuente
            }

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(6.dp),
                contentPadding = PaddingValues(bottom = 20.dp)
            ) {
                itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" }) { idx, emb ->
                    val isFirst = idx == 0
                    PanelItem(
                        modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                        titulo = emb.nombre,
                        subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                        seleccionado = emb.url == embedActual.url,
                        miniaturaUrl = evento.imagen,
                        onClick = { onCanalClick(emb) }
                    )
                }

                if (otros.isNotEmpty()) {
                    item(key = "otros_header") {
                        Spacer(Modifier.height(28.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier.size(4.dp).clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.3f))
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                "OTROS EVENTOS",
                                color = Color.White.copy(alpha = 0.5f),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = 2.sp
                            )
                        }
                        Spacer(Modifier.height(10.dp))
                    }
                    itemsIndexed(
                        otros.take(30),
                        key = { idx, it -> "ev_${idx}_${it.descripcion}_${it.fuente}_${it.hora}" }
                    ) { _, ev ->
                        PanelItem(
                            titulo = ev.descripcion,
                            subtitulo = "${ev.hora}  ·  ${ev.fuente}",
                            seleccionado = false,
                            miniaturaUrl = ev.imagen,
                            onClick = { onEventoClick(ev) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit,
    miniaturaUrl: String? = null
) {
    var focused by remember { mutableStateOf(false) }

    val scale by animateFloatAsState(if (focused) 1.02f else 1f, tween(150), label = "piScale")
    val bg by animateColorAsState(
        when {
            focused -> Color(0x33FFD700)
            seleccionado -> Color(0x22FFD700)
            else -> Color.White.copy(alpha = 0.03f)
        }, tween(150), label = "piBg"
    )
    val border by animateColorAsState(
        when {
            focused -> Color(0xFFFFD700)
            seleccionado -> Color(0xFFFFD700).copy(alpha = 0.4f)
            else -> Color.White.copy(alpha = 0.06f)
        }, tween(150), label = "piBd"
    )

    Row(
        modifier
            .fillMaxWidth()
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(if (focused) 1.5.dp else 1.dp, border, RoundedCornerShape(14.dp))
            .clickable { onClick() }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (miniaturaUrl != null && miniaturaUrl.isNotBlank()) {
            Box(
                Modifier
                    .size(width = 76.dp, height = 46.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFF1A1A22)),
                contentAlignment = Alignment.Center
            ) {
                coil.compose.AsyncImage(
                    model = miniaturaUrl,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                if (seleccionado) {
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))
                            )
                        )
                    )
                    Box(
                        Modifier
                            .align(Alignment.BottomStart)
                            .padding(4.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF4ADE80))
                            .padding(horizontal = 5.dp, vertical = 1.dp)
                    ) {
                        Text("●", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
        } else {
            Box(
                Modifier.size(8.dp).clip(CircleShape).background(
                    when {
                        seleccionado -> Color(0xFF4ADE80)
                        focused -> Color(0xFFFFD700)
                        else -> Color.White.copy(alpha = 0.3f)
                    }
                )
            )
            Spacer(Modifier.width(14.dp))
        }

        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = if (seleccionado) Color(0xFFFFD700) else Color.White,
                fontSize = 14.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium,
                maxLines = 2,
                letterSpacing = 0.2.sp
            )
            if (subtitulo != null) {
                Spacer(Modifier.height(2.dp))
                Text(
                    subtitulo,
                    color = if (seleccionado) Color(0xFF4ADE80) else Color.White.copy(alpha = 0.5f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            }
        }

        if (focused) {
            Box(
                Modifier.size(26.dp).clip(CircleShape)
                    .background(Color(0xFFFFD700)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = AppIcons.play,
                    contentDescription = null,
                    tint = Color.Black,
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════
// Selector de calidad item
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
            seleccionado -> Color(0x33FFD700)
            focused -> Color.White.copy(alpha = 0.08f)
            else -> Color.White.copy(alpha = 0.03f)
        }, tween(150), label = "scBg"
    )
    val border by animateColorAsState(
        when {
            seleccionado -> Color(0xFFFFD700).copy(alpha = 0.6f)
            focused -> Color.White.copy(alpha = 0.3f)
            else -> Color.White.copy(alpha = 0.06f)
        }, tween(150), label = "scBd"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (seleccionado || focused) 1.5.dp else 1.dp, border, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(10.dp).clip(CircleShape)
                .background(if (seleccionado) Color(0xFF4ADE80) else Color.White.copy(alpha = 0.2f))
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium
            )
            Text(subtitulo, color = Color.White.copy(alpha = 0.5f), fontSize = 12.sp)
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

c_final = main_part + nuevos_composables

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c_final)

print(f"✅ PlayerScreen.kt reescrito (lógica intacta + UI premium)")
print(f"   Total: {len(c_final)} bytes")
PYEOF

echo ""
echo "✅✅✅ Player Premium listo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
