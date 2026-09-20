#!/bin/bash
set -e

FILE_HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
FILE_AJUSTES="app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"

cp "$FILE_HOME" "$FILE_HOME.bak-bugs2"
cp "$FILE_AJUSTES" "$FILE_AJUSTES.bak-bugs2"

echo "📝 Fix 1 — Hero más compacto en vertical..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

pattern = r'@Composable\nprivate fun HeroCine\([^)]*\) \{.*?\n\}\n'
match = re.search(pattern, content, re.DOTALL)

if match:
    nueva_hero = '''@Composable
private fun HeroCine(evento: Evento, esHoy: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val pulse = rememberPulseAlpha(min = 0.4f, max = 1f, durationMs = 800)
    val enVivo = esHoy && estaEnVivo(evento.hora)

    val esTV = rememberEsTV()
    val config = LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT && !esTV

    // Tamaños adaptativos según orientación
    val alturaHero = if (esVertical) 240.dp else 300.dp
    val paddingH = if (esVertical) 14.dp else 40.dp
    val paddingInterno = if (esVertical) 14.dp else 28.dp
    val tituloSize = if (esVertical) 22.sp else 42.sp
    val tituloLineHeight = if (esVertical) 26.sp else 46.sp
    val badgeSize = if (esVertical) 9.sp else 12.sp
    val metaSize = if (esVertical) 11.sp else 18.sp
    val botonTextoSize = if (esVertical) 12.sp else 15.sp
    val botonPaddingV = if (esVertical) 9.dp else 12.dp
    val botonPaddingH = if (esVertical) 16.dp else 24.dp
    val gapTitulo = if (esVertical) 6.dp else 10.dp
    val gapMeta = if (esVertical) 8.dp else 18.dp

    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else Color.Transparent,
        tween(180), label = "heroBorder"
    )
    val borderWidth by animateDpAsState(if (focused) 3.dp else 0.dp, tween(180), label = "heroW")

    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = paddingH)
            .fadeInOnLoad(durationMs = 500, delayMs = 150)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.01f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(20.dp))
            .border(borderWidth, borderColor, RoundedCornerShape(20.dp))
            .height(alturaHero)
    ) {
        if (evento.imagen.isNotBlank()) {
            AsyncImage(
                model = evento.imagen,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(0.55f)
            )
        }

        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    colors = listOf(
                        Color.Black.copy(alpha = 0.95f),
                        Color.Black.copy(alpha = 0.6f),
                        Color.Transparent
                    )
                )
            )
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                )
            )
        )

        Column(
            Modifier.fillMaxSize().padding(paddingInterno),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Badges arriba
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (enVivo) {
                    Box(
                        Modifier.alpha(pulse)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFFEF4444))
                            .padding(horizontal = if (esVertical) 7.dp else 12.dp, vertical = if (esVertical) 3.dp else 5.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(if (esVertical) 5.dp else 8.dp).clip(CircleShape).background(Color.White))
                            Spacer(Modifier.width(4.dp))
                            Text("EN VIVO", color = Color.White, fontSize = badgeSize,
                                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                        }
                    }
                    Spacer(Modifier.width(6.dp))
                } else {
                    Box(
                        Modifier.clip(RoundedCornerShape(6.dp))
                            .background(AppColors.Gold)
                            .padding(horizontal = if (esVertical) 7.dp else 12.dp, vertical = if (esVertical) 3.dp else 5.dp)
                    ) {
                        Text("⭐ DESTACADO", color = Color.Black, fontSize = badgeSize,
                            fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                    }
                    Spacer(Modifier.width(6.dp))
                }
                Box(
                    Modifier.clip(RoundedCornerShape(6.dp))
                        .background(Color(0xAA000000))
                        .padding(horizontal = if (esVertical) 7.dp else 10.dp, vertical = if (esVertical) 3.dp else 5.dp)
                ) {
                    Text("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                        color = AppColors.Gold, fontSize = badgeSize,
                        fontWeight = FontWeight.SemiBold, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
            }

            // Info abajo
            Column {
                Text(
                    evento.descripcion,
                    color = Color.White,
                    fontSize = tituloSize,
                    fontWeight = FontWeight.Black,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = tituloLineHeight
                )
                Spacer(Modifier.height(gapTitulo))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = AppIcons.reloj,
                        contentDescription = null,
                        tint = AppColors.GoldBright,
                        modifier = Modifier.size(if (esVertical) 12.dp else 16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        FechaHelper.badgeCard(evento.fecha, evento.hora),
                        color = AppColors.GoldBright, fontSize = metaSize, fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.width(if (esVertical) 10.dp else 18.dp))
                    Icon(
                        imageVector = AppIcons.canales,
                        contentDescription = null,
                        tint = Color(0xFFD1D5DB),
                        modifier = Modifier.size(if (esVertical) 12.dp else 16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("${evento.embeds.size} ${if (evento.embeds.size == 1) "canal" else "canales"}",
                        color = Color(0xFFD1D5DB), fontSize = metaSize)
                }
                Spacer(Modifier.height(gapMeta))
                Box(
                    Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (focused) AppColors.GoldBright else AppColors.Gold)
                        .padding(horizontal = botonPaddingH, vertical = botonPaddingV)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.play,
                            contentDescription = null,
                            tint = Color.Black,
                            modifier = Modifier.size(if (esVertical) 14.dp else 18.dp)
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            if (enVivo) "VER AHORA" else "VER DETALLES",
                            color = Color.Black, fontSize = botonTextoSize,
                            fontWeight = FontWeight.Black, letterSpacing = 1.sp
                        )
                    }
                }
            }
        }
    }
}
'''
    content = content[:match.start()] + nueva_hero + content[match.end():]
    print("✅ HeroCine reescrito más compacto")
else:
    print("⚠️  No encontré HeroCine")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 2 — Ajustes: cards con weight(1f) para repartir ancho..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Fix del Row de calidad: usar weight(1f) en cada card
# ═══════════════════════════════════════════════════════════

# Buscar el Row de "CALIDAD DE VIDEO"
old_row_calidad = '''            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OpcionCalidad(
                    titulo = "Auto",
                    subtitulo = "Se adapta a tu red",
                    seleccionado = calidad == "auto",
                    modifier = Modifier.focusRequester(primerFocus),
                    onClick = {
                        calidad = "auto"
                        AjustesStore.guardarCalidad(context, "auto")
                    }
                )
                OpcionCalidad(
                    titulo = "SD",
                    subtitulo = "480p · menos datos",
                    seleccionado = calidad == "sd",
                    onClick = {
                        calidad = "sd"
                        AjustesStore.guardarCalidad(context, "sd")
                    }
                )
                OpcionCalidad(
                    titulo = "HD",
                    subtitulo = "1080p · más calidad",
                    seleccionado = calidad == "hd",
                    onClick = {
                        calidad = "hd"
                        AjustesStore.guardarCalidad(context, "hd")
                    }
                )
            }'''

new_row_calidad = '''            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                OpcionCalidad(
                    titulo = "Auto",
                    subtitulo = "Se adapta",
                    seleccionado = calidad == "auto",
                    modifier = Modifier.weight(1f).focusRequester(primerFocus),
                    onClick = {
                        calidad = "auto"
                        AjustesStore.guardarCalidad(context, "auto")
                    }
                )
                OpcionCalidad(
                    titulo = "SD",
                    subtitulo = "480p · datos",
                    seleccionado = calidad == "sd",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        calidad = "sd"
                        AjustesStore.guardarCalidad(context, "sd")
                    }
                )
                OpcionCalidad(
                    titulo = "HD",
                    subtitulo = "1080p · calidad",
                    seleccionado = calidad == "hd",
                    modifier = Modifier.weight(1f),
                    onClick = {
                        calidad = "hd"
                        AjustesStore.guardarCalidad(context, "hd")
                    }
                )
            }'''

if old_row_calidad in content:
    content = content.replace(old_row_calidad, new_row_calidad, 1)
    print("✅ Row de calidad con weight(1f)")
else:
    print("⚠️  No encontré el Row de calidad")

# Fix del Row de orientación
old_row_orient = '''                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OpcionOrientacion(
                        titulo = "Auto",
                        subtitulo = "Sigue al dispositivo",
                        seleccionado = orientacion == "auto",
                        onClick = {
                            orientacion = "auto"
                            AjustesStore.guardarOrientacion(context, "auto")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Vertical",
                        subtitulo = "Celular parado",
                        seleccionado = orientacion == "vertical",
                        onClick = {
                            orientacion = "vertical"
                            AjustesStore.guardarOrientacion(context, "vertical")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Horizontal",
                        subtitulo = "Celular acostado",
                        seleccionado = orientacion == "horizontal",
                        onClick = {
                            orientacion = "horizontal"
                            AjustesStore.guardarOrientacion(context, "horizontal")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                            } catch (_: Exception) {}
                        }
                    )
                }'''

new_row_orient = '''                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    OpcionOrientacion(
                        titulo = "Auto",
                        subtitulo = "Sigue al celu",
                        seleccionado = orientacion == "auto",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "auto"
                            AjustesStore.guardarOrientacion(context, "auto")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Vertical",
                        subtitulo = "Celular parado",
                        seleccionado = orientacion == "vertical",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "vertical"
                            AjustesStore.guardarOrientacion(context, "vertical")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Horizontal",
                        subtitulo = "Celular acostado",
                        seleccionado = orientacion == "horizontal",
                        modifier = Modifier.weight(1f),
                        onClick = {
                            orientacion = "horizontal"
                            AjustesStore.guardarOrientacion(context, "horizontal")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                            } catch (_: Exception) {}
                        }
                    )
                }'''

if old_row_orient in content:
    content = content.replace(old_row_orient, new_row_orient, 1)
    print("✅ Row de orientación con weight(1f)")
else:
    print("⚠️  No encontré el Row de orientación")

# ═══════════════════════════════════════════════════════════
# Actualizar OpcionCalidad: quitar width fijo, usar fillMaxWidth
# ═══════════════════════════════════════════════════════════
old_opcion_calidad = '''    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT
    val anchoOpcion = if (esVertical) 100.dp else 200.dp

    Column(
        modifier
            .width(anchoOpcion)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)'''

new_opcion_calidad = '''    Column(
        modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)'''

if old_opcion_calidad in content:
    content = content.replace(old_opcion_calidad, new_opcion_calidad, 1)
    print("✅ OpcionCalidad sin width fijo")

# Actualizar OpcionOrientacion: quitar width, usar fillMaxWidth y agregar modifier
old_opcion_orient = '''@Composable
private fun OpcionOrientacion(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    onClick: () -> Unit
) {'''

new_opcion_orient = '''@Composable
private fun OpcionOrientacion(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {'''

if old_opcion_orient in content:
    content = content.replace(old_opcion_orient, new_opcion_orient, 1)
    print("✅ OpcionOrientacion acepta modifier")

old_opcion_orient_body = '''    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT
    val anchoOpc = if (esVertical) 105.dp else 170.dp

    Column(
        Modifier
            .width(anchoOpc)'''

new_opcion_orient_body = '''    Column(
        modifier
            .fillMaxWidth()'''

if old_opcion_orient_body in content:
    content = content.replace(old_opcion_orient_body, new_opcion_orient_body, 1)
    print("✅ OpcionOrientacion sin width fijo")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "alturaHero = if (esVertical) 240" "$FILE_HOME" && echo "  ✓ Hero compacto"
grep -q "Row de calidad con weight" "$FILE_AJUSTES" 2>/dev/null || grep -q "Modifier.weight(1f).focusRequester" "$FILE_AJUSTES" && echo "  ✓ Calidad con weight"
grep -q "Modifier.weight(1f)," "$FILE_AJUSTES" && echo "  ✓ Orientación con weight"

echo ""
echo "✅✅✅ Fix v3.1 bugs #2 aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   🎬 Hero: 240dp alto, título 22sp, botón más chico"
echo "   ⚙️ Calidad: las 3 cards se reparten el ancho (weight 1f)"
echo "   ⚙️ Orientación: las 3 cards se reparten el ancho (weight 1f)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"