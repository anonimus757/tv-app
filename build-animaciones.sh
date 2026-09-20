#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
DATA_DIR="app/src/main/java/com/anonimus757/tvapp/ui/animations"

# ═══════════════════════════════════════════════════════════
# 1) Helper de gradiente animado
# ═══════════════════════════════════════════════════════════
echo "📝 Creando helper de gradiente animado..."

cat > "$DATA_DIR/AnimatedBackgrounds.kt" << 'EOF'
package com.anonimus757.tvapp.ui.animations

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Fondo con gradiente dorado que se mueve lentamente.
 * Muy sutil — da sensación de "vida" sin distraer.
 */
@Composable
fun AnimatedGoldBackground(
    modifier: Modifier = Modifier,
    baseColor: Color = Color(0xFF050505),
    accentColor: Color = Color(0xFFD4AF37),
    durationMs: Int = 8000
) {
    val transition = rememberInfiniteTransition(label = "bg")
    val offsetX by transition.animateFloat(
        initialValue = -1000f,
        targetValue = 2500f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bgOffsetX"
    )
    val offsetY by transition.animateFloat(
        initialValue = 500f,
        targetValue = -1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMs + 3000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bgOffsetY"
    )

    Box(
        modifier
            .fillMaxSize()
            .background(baseColor)
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        accentColor.copy(alpha = 0.06f),
                        accentColor.copy(alpha = 0.02f),
                        Color.Transparent
                    ),
                    center = Offset(offsetX, offsetY),
                    radius = 1800f
                )
            )
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        accentColor.copy(alpha = 0.04f),
                        Color.Transparent
                    ),
                    center = Offset(2500f - offsetX, -offsetY + 800f),
                    radius = 1500f
                )
            )
    )
}
EOF

echo "✅ AnimatedBackgrounds.kt creado"

# ═══════════════════════════════════════════════════════════
# 2) Aplicar al HomeScreen
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Aplicando gradiente animado en HomeScreen..."

HOME_FILE="$UI_DIR/HomeScreen.kt"
cp "$HOME_FILE" "$HOME_FILE.bak-anim"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Import del helper
if "import com.anonimus757.tvapp.ui.animations.AnimatedGoldBackground" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.animations.fadeInOnLoad",
        "import com.anonimus757.tvapp.ui.animations.AnimatedGoldBackground\nimport com.anonimus757.tvapp.ui.animations.fadeInOnLoad"
    )
    print("✅ Import de AnimatedGoldBackground")

# Reemplazar el Box del fondo principal
old_bg = '''    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, AppColors.BackgroundGradient)
                )
            )
    ) {
        when {
            cargandoInicial -> SkeletonHome(status)'''

new_bg = '''    Box(Modifier.fillMaxSize()) {
        // Fondo animado (sutil)
        AnimatedGoldBackground()

        when {
            cargandoInicial -> SkeletonHome(status)'''

if old_bg in content:
    content = content.replace(old_bg, new_bg, 1)
    print("✅ Fondo del Home con gradiente animado")
else:
    print("⚠️  No encontré el Box del fondo principal, buscando variante...")
    # Buscar variante
    import re
    pattern = r'Box\(\s*Modifier\s*\.fillMaxSize\(\)\s*\.background\(\s*Brush\.verticalGradient\(\s*listOf\(AppColors\.Background,\s*AppColors\.BackgroundGradient\)\s*\)\s*\)\s*\)\s*\{'
    match = re.search(pattern, content)
    if match:
        content = content[:match.start()] + '''Box(Modifier.fillMaxSize()) {
        AnimatedGoldBackground()
''' + content[match.end():]
        print("✅ Fondo animado (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) Aplicar al EventDetailScreen también
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Aplicando gradiente animado en EventDetailScreen..."

DETAIL_FILE="$UI_DIR/EventDetailScreen.kt"
cp "$DETAIL_FILE" "$DETAIL_FILE.bak-anim"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(file_path) as f:
    content = f.read()

if "import com.anonimus757.tvapp.ui.animations.AnimatedGoldBackground" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.animations.fadeInOnLoad",
        "import com.anonimus757.tvapp.ui.animations.AnimatedGoldBackground\nimport com.anonimus757.tvapp.ui.animations.fadeInOnLoad"
    )

old_bg = '''    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(AppColors.Background, AppColors.BackgroundGradient))
            )
    ) {'''

new_bg = '''    Box(Modifier.fillMaxSize()) {
        AnimatedGoldBackground()
'''

if old_bg in content:
    content = content.replace(old_bg, new_bg, 1)
    print("✅ Fondo animado en Detail")
else:
    print("ℹ️  Detail no modificado (formato distinto)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 4) Animación de entrada del reproductor
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Agregando animación de entrada al reproductor..."

PLAYER_FILE="$UI_DIR/PlayerScreen.kt"
cp "$PLAYER_FILE" "$PLAYER_FILE.bak-anim"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Estado para fade-in del video
if "var videoAlpha" not in content:
    ancla = "    var mostrarControles by remember { mutableStateOf(true) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    // 🎬 Animación de entrada del video\n    var videoAlpha by remember { mutableFloatStateOf(0f) }",
            1
        )
        print("✅ Estado videoAlpha")

# 2) Animar cuando aparece el video
if "// Animar cuando aparece el video" not in content:
    ancla2 = '''    LaunchedEffect(m3u8Url) {
        if (m3u8Url == null) { segundosActivo = 0; return@LaunchedEffect }
        segundosActivo = 0
        while (true) { delay(1000); segundosActivo++ }
    }'''
    nuevo2 = ancla2 + '''

    // 🎬 Animación de entrada: cuando el video aparece, hace fade-in
    LaunchedEffect(m3u8Url) {
        if (m3u8Url != null) {
            videoAlpha = 0f
            delay(100)
            videoAlpha = 1f
        } else {
            videoAlpha = 0f
        }
    }

    // Interpolación del alpha
    val alphaAnimado by androidx.compose.animation.core.animateFloatAsState(
        targetValue = videoAlpha,
        animationSpec = androidx.compose.animation.core.tween(800),
        label = "videoFadeIn"
    )'''
    if ancla2 in content:
        content = content.replace(ancla2, nuevo2, 1)
        print("✅ LaunchedEffect de fade-in")

# 3) Aplicar alpha al PlayerView
old_pv = '''            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize()
            )'''

new_pv = '''            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        player = exoPlayer
                        useController = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                        setBackgroundColor(AndroidColor.BLACK)
                    }
                },
                modifier = Modifier.fillMaxSize().alpha(alphaAnimado)
            )'''

if old_pv in content:
    content = content.replace(old_pv, new_pv, 1)
    print("✅ Alpha al PlayerView")
else:
    print("⚠️  No encontré PlayerView principal")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$DATA_DIR/AnimatedBackgrounds.kt" ] && echo "  ✓ AnimatedBackgrounds.kt"
grep -q "AnimatedGoldBackground" "$HOME_FILE" && echo "  ✓ Home con gradiente animado"
grep -q "AnimatedGoldBackground" "$DETAIL_FILE" && echo "  ✓ Detail con gradiente animado"
grep -q "alphaAnimado" "$PLAYER_FILE" && echo "  ✓ Fade-in del video"

echo ""
echo "✅✅✅ Animaciones agregadas"
echo ""
echo "📌 Qué cambió:"
echo "   🎨 Home/Detail: gradiente dorado que se mueve lento (sutil)"
echo "   🎬 Reproductor: el video hace fade-in desde negro (800ms)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"