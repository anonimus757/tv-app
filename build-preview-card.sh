#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/HomeScreen.kt"

cp "$FILE" "$FILE.bak-preview"

echo "📝 Agregando preview de card en TV (10 seg, EN VIVO, mudo)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Imports
# ═══════════════════════════════════════════════════════════
imports_to_add = '''import android.graphics.Color as AndroidColor
import android.net.Uri
import android.view.ViewGroup
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.ui.PlayerView
import com.anonimus757.tvapp.data.CanalCache
import com.anonimus757.tvapp.data.M3u8Extractor
'''

matches = list(re.finditer(r'^import .+$', content, re.MULTILINE))
if matches and "CardVideoPreview" not in content:
    insert_pos = matches[-1].end()
    content = content[:insert_pos] + "\n" + imports_to_add + content[insert_pos:]
    print("✅ Imports agregados")

# ═══════════════════════════════════════════════════════════
# 2) Modificar EventoCardPremium para agregar el preview
# ═══════════════════════════════════════════════════════════

# 2a) Cambiar la firma para agregar parámetros de preview
old_firma = '''@Composable
private fun EventoCardPremium(ev: Evento, enVivo: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }'''

new_firma = '''@Composable
private fun EventoCardPremium(
    ev: Evento,
    enVivo: Boolean,
    onClick: () -> Unit,
    mostrarPreview: Boolean = false
) {
    var focused by remember { mutableStateOf(false) }
    val esTV = com.anonimus757.tvapp.ui.util.rememberEsTV()

    // 🆕 Preview en TV: si mantiene el foco 10 seg y está EN VIVO → reproduce
    var mostrarVideoPreview by remember { mutableStateOf(false) }

    LaunchedEffect(focused, enVivo, esTV) {
        if (focused && enVivo && esTV) {
            delay(10000) // 10 segundos con el foco puesto
            if (focused) {
                mostrarVideoPreview = true
            }
        } else {
            mostrarVideoPreview = false
        }
    }'''

if old_firma in content:
    content = content.replace(old_firma, new_firma, 1)
    print("✅ Firma de EventoCardPremium actualizada")

# 2b) Reemplazar el bloque de imagen para incluir el video condicional
old_imagen_block = '''        Box(
            Modifier.fillMaxWidth().height(altoCard).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().alpha(0.75f)
                )
            } else {
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Text("⚽", fontSize = 70.sp)
                }
            }'''

new_imagen_block = '''        Box(
            Modifier.fillMaxWidth().height(altoCard).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
        ) {
            // 🆕 Preview en vivo (solo TV, solo EN VIVO, tras 10 seg de foco)
            if (mostrarVideoPreview && ev.embeds.isNotEmpty()) {
                CardVideoPreview(evento = ev, modifier = Modifier.fillMaxSize())
            } else if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().alpha(0.75f)
                )
            } else {
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))
                    ),
                    contentAlignment = Alignment.Center
                ) {
                    Text("⚽", fontSize = 70.sp)
                }
            }'''

if old_imagen_block in content:
    content = content.replace(old_imagen_block, new_imagen_block, 1)
    print("✅ Bloque de imagen con video condicional")
else:
    print("⚠️  No encontré el bloque de imagen exacto, intentando regex...")
    # Intento con regex
    pattern = r'(Box\(\s*Modifier\.fillMaxWidth\(\)\.height\(altoCard\).*?contentAlignment = Alignment\.Center\s*\)\s*\{\s*Text\("⚽", fontSize = 70\.sp\)\s*\}\s*\})'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_imagen_block + content[match.end():]
        print("✅ Bloque de imagen actualizado (regex)")

# ═══════════════════════════════════════════════════════════
# 3) Agregar el composable CardVideoPreview al final
# ═══════════════════════════════════════════════════════════
card_video = '''

// ═══════════════════════════════════════════════════════════
// 🎬 PREVIEW DE CARD EN VIVO (solo TV, mudo, 10 seg de foco)
// ═══════════════════════════════════════════════════════════
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
private fun CardVideoPreview(evento: Evento, modifier: Modifier = Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var videoUrl by remember { mutableStateOf<String?>(null) }

    // Extraer m3u8 (usa cache si está disponible)
    LaunchedEffect(evento.descripcion) {
        if (evento.embeds.isEmpty()) return@LaunchedEffect
        val primerCanal = evento.embeds.first()
        val cached = CanalCache.get(primerCanal.url)
        if (cached != null) {
            videoUrl = cached
        } else {
            try {
                val m3u8 = M3u8Extractor.extraer(primerCanal.url, primerCanal.referer) {}
                if (m3u8 != null) {
                    CanalCache.put(primerCanal.url, m3u8)
                    videoUrl = m3u8
                }
            } catch (_: Exception) {}
        }
    }

    val previewPlayer = remember {
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(1500, 10000, 1000, 2000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()
        ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build().apply {
                volume = 0f  // 🔇 MUDO
                playWhenReady = true
            }
    }

    DisposableEffect(Unit) {
        onDispose {
            try { previewPlayer.stop() } catch (_: Exception) {}
            try { previewPlayer.release() } catch (_: Exception) {}
        }
    }

    LaunchedEffect(videoUrl) {
        val url = videoUrl ?: return@LaunchedEffect
        try {
            previewPlayer.stop()
            previewPlayer.clearMediaItems()

            val referer = evento.embeds.firstOrNull()?.referer ?: ""
            val headers = mutableMapOf(
                "User-Agent" to "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36"
            )
            if (referer.isNotBlank()) {
                headers["Referer"] = referer
                headers["Origin"] = referer.trimEnd('/')
            }

            val ds = DefaultHttpDataSource.Factory()
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(8000)
                .setReadTimeoutMs(8000)

            val src = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(false)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

            previewPlayer.setMediaSource(src)
            previewPlayer.prepare()
        } catch (_: Exception) {}
    }

    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                player = previewPlayer
                useController = false
                isFocusable = false
                isFocusableInTouchMode = false
                descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                setBackgroundColor(AndroidColor.BLACK)
            }
        },
        modifier = modifier
    )
}
'''

content = content.rstrip() + card_video + "\n"

with open(file_path, "w") as f:
    f.write(content)

print("✅ CardVideoPreview agregado")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "CardVideoPreview" "$FILE" && echo "  ✓ CardVideoPreview definido"
grep -q "delay(10000)" "$FILE" && echo "  ✓ Delay de 10 seg"
grep -q "rememberEsTV" "$FILE" && echo "  ✓ Detecta TV"
grep -q "volume = 0f" "$FILE" && echo "  ✓ Mudo"

echo ""
echo "✅✅✅ Preview de card en TV listo"
echo ""
echo "📌 Cómo funciona:"
echo "   1. Solo en TV (en celu queda igual)"
echo "   2. Enfocás una card EN VIVO"
echo "   3. Después de 10 seg sin mover → reproduce preview mudo"
echo "   4. Cambiás de foco → vuelve a la imagen"
echo "   5. Usa CanalCache → si ya se extrajo, es instantáneo"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"