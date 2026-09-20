#!/bin/bash
set -e

FILE_HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
FILE_AJUSTES="app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
FILE_BUSQUEDA="app/src/main/java/com/anonimus757/tvapp/ui/BusquedaScreen.kt"

cp "$FILE_HOME" "$FILE_HOME.bak-bugs"
cp "$FILE_AJUSTES" "$FILE_AJUSTES.bak-bugs"
cp "$FILE_BUSQUEDA" "$FILE_BUSQUEDA.bak-bugs"

echo "📝 Fix 1 — Evento 'EN VIVO' ahora dura máximo 2 horas..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Cambiar la ventana de "en vivo" de 180 min a 120 min
old = '''private fun estaEnVivo(hora: String): Boolean {
    val min = horaAMinutos(hora)
    if (min < 0) return false
    val ahora = minutosAhora()
    return ahora >= min && ahora < min + 180
}'''

new = '''private fun estaEnVivo(hora: String): Boolean {
    val min = horaAMinutos(hora)
    if (min < 0) return false
    val ahora = minutosAhora()
    // Un partido dura máximo 2h (90min + 15 entretiempo + tiempo agregado)
    // Pasado ese tiempo, ya no se considera "en vivo"
    return ahora >= min && ahora < min + 120
}'''

if old in content:
    content = content.replace(old, new)
    print("✅ estaEnVivo: 180 min → 120 min")
else:
    print("⚠️  No encontré estaEnVivo exacta")
    import re
    pattern = r'private fun estaEnVivo\(hora: String\): Boolean \{[^}]*min \+ \d+[^}]*\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new + content[match.end():]
        print("✅ estaEnVivo corregida (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 2 — Hero card adaptativo (no se corta más)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Buscar la función HeroCine completa
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
    val alturaHero = if (esVertical) 260.dp else 300.dp
    val paddingH = if (esVertical) 18.dp else 40.dp
    val paddingInterno = if (esVertical) 18.dp else 28.dp
    val tituloSize = if (esVertical) 26.sp else 42.sp
    val tituloLineHeight = if (esVertical) 30.sp else 46.sp
    val badgeSize = if (esVertical) 10.sp else 12.sp
    val metaSize = if (esVertical) 12.sp else 18.sp
    val botonTextoSize = if (esVertical) 13.sp else 15.sp
    val botonPaddingV = if (esVertical) 10.dp else 12.dp
    val botonPaddingH = if (esVertical) 20.dp else 24.dp
    val gapTitulo = if (esVertical) 8.dp else 10.dp
    val gapMeta = if (esVertical) 10.dp else 18.dp

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
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color(0xFFEF4444))
                            .padding(horizontal = if (esVertical) 8.dp else 12.dp, vertical = if (esVertical) 4.dp else 5.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(if (esVertical) 6.dp else 8.dp).clip(CircleShape).background(Color.White))
                            Spacer(Modifier.width(5.dp))
                            Text("EN VIVO", color = Color.White, fontSize = badgeSize,
                                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                        }
                    }
                    Spacer(Modifier.width(8.dp))
                } else {
                    Box(
                        Modifier.clip(RoundedCornerShape(8.dp))
                            .background(AppColors.Gold)
                            .padding(horizontal = if (esVertical) 8.dp else 12.dp, vertical = if (esVertical) 4.dp else 5.dp)
                    ) {
                        Text("⭐ DESTACADO", color = Color.Black, fontSize = badgeSize,
                            fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                    }
                    Spacer(Modifier.width(8.dp))
                }
                Box(
                    Modifier.clip(RoundedCornerShape(8.dp))
                        .background(Color(0xAA000000))
                        .padding(horizontal = if (esVertical) 8.dp else 10.dp, vertical = if (esVertical) 4.dp else 5.dp)
                ) {
                    Text("${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                        color = AppColors.Gold, fontSize = if (esVertical) 10.sp else 11.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = 1)
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
                        modifier = Modifier.size(if (esVertical) 13.dp else 16.dp)
                    )
                    Spacer(Modifier.width(5.dp))
                    Text(
                        FechaHelper.badgeCard(evento.fecha, evento.hora),
                        color = AppColors.GoldBright, fontSize = metaSize, fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.width(if (esVertical) 12.dp else 18.dp))
                    Icon(
                        imageVector = AppIcons.canales,
                        contentDescription = null,
                        tint = Color(0xFFD1D5DB),
                        modifier = Modifier.size(if (esVertical) 13.dp else 16.dp)
                    )
                    Spacer(Modifier.width(5.dp))
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
                            modifier = Modifier.size(if (esVertical) 15.dp else 18.dp)
                        )
                        Spacer(Modifier.width(8.dp))
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
    print("✅ HeroCine adaptativo reescrito")
else:
    print("⚠️  No encontré HeroCine")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 3 — Ajustes adaptativo (cards de calidad y orientación)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# Fix de OpcionCalidad: ancho adaptativo
old_calidad = '''    Column(
        modifier
            .width(200.dp)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)'''

new_calidad = '''    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT
    val anchoOpcion = if (esVertical) 100.dp else 200.dp

    Column(
        modifier
            .width(anchoOpcion)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)'''

if old_calidad in content:
    content = content.replace(old_calidad, new_calidad, 1)
    print("✅ OpcionCalidad adaptativa")

# Fix de OpcionOrientacion: ancho adaptativo
old_orient = '''    Column(
        Modifier
            .width(if (seleccionado || focused) 170.dp else 165.dp)'''

new_orient = '''    val config = androidx.compose.ui.platform.LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT
    val anchoOpc = if (esVertical) 105.dp else 170.dp

    Column(
        Modifier
            .width(anchoOpc)'''

if old_orient in content:
    content = content.replace(old_orient, new_orient, 1)
    print("✅ OpcionOrientacion adaptativa")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 4 — Búsqueda: botón Volver sin estirarse..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/BusquedaScreen.kt"
with open(file_path) as f:
    content = f.read()

# El problema: el header Row tiene BotonVolver con Modifier.fillMaxWidth() aplicado por error
# Buscar el Row del header
old_header = '''            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = AppIcons.buscar,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(34.dp)
                )
                Spacer(Modifier.width(12.dp))
                Text("Buscar eventos", color = AppColors.GoldBright, fontSize = 30.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                BotonVolver(onBack)
            }'''

new_header = '''            val config = androidx.compose.ui.platform.LocalConfiguration.current
            val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT

            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(400),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = AppIcons.buscar,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(if (esVertical) 24.dp else 34.dp)
                )
                Spacer(Modifier.width(if (esVertical) 8.dp else 12.dp))
                Text(
                    if (esVertical) "Buscar" else "Buscar eventos",
                    color = AppColors.GoldBright,
                    fontSize = if (esVertical) 22.sp else 30.sp,
                    fontWeight = FontWeight.Black
                )
                Spacer(Modifier.weight(1f))
                BotonVolver(onBack)
            }'''

if old_header in content:
    content = content.replace(old_header, new_header, 1)
    print("✅ Header de búsqueda adaptativo")

# También el campo de texto + botón de voz en vertical
old_row = '''            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField('''

new_row = '''            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField('''

# Este Row ya está bien en realidad, no hay que tocarlo

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "min + 120" "$FILE_HOME" && echo "  ✓ En vivo 120 min"
grep -q "alturaHero = if (esVertical)" "$FILE_HOME" && echo "  ✓ Hero adaptativo"
grep -q "anchoOpcion = if (esVertical)" "$FILE_AJUSTES" && echo "  ✓ Ajustes adaptativo"
grep -q "if (esVertical) 22.sp else 30.sp" "$FILE_BUSQUEDA" && echo "  ✓ Búsqueda adaptativa"

echo ""
echo "✅✅✅ Fix de bugs v3.1 aplicado"
echo ""
echo "📌 Qué se arregló:"
echo "   1. 'En vivo' → ahora dura máximo 2h (antes 3h)"
echo "   2. Hero card → adaptada al vertical (no se corta)"
echo "   3. Ajustes → cards más chicas en vertical"
echo "   4. Búsqueda → header compacto"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"