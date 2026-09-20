#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/HomeScreen.kt"

# 1) Revertir al backup
if [ -f "$FILE.bak-preview" ]; then
    cp "$FILE.bak-preview" "$FILE"
    echo "✅ Revertido a versión estable"
else
    echo "❌ No hay backup .bak-preview"
    exit 1
fi

echo "📝 Aplicando fix v2 (más robusto)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Imports
imports_block = '''import android.graphics.Color as AndroidColor
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

# Encontrar el último import y agregar
last_import = content.rfind("import ")
end_of_line = content.find("\n", last_import)
content = content[:end_of_line+1] + imports_block + content[end_of_line+1:]
print("✅ Imports agregados")

# 2) Reemplazar TODA la función EventoCardPremium por una versión limpia
# Buscar desde "private fun EventoCardPremium(" hasta el próximo "}\n\n@Composable" o similar
pattern = r'(@Composable\s+private fun EventoCardPremium\([^\)]*\)\s*\{.*?\n\})'
match = re.search(pattern, content, re.DOTALL)

if not match:
    print("❌ No encontré EventoCardPremium")
    exit(1)

nueva_funcion = '''@Composable
private fun EventoCardPremium(
    ev: Evento,
    enVivo: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val esTV = rememberEsTV()

    // 🆕 Preview en TV: si mantiene el foco 10 seg y está EN VIVO → reproduce
    var mostrarVideoPreview by remember { mutableStateOf(false) }

    LaunchedEffect(focused, enVivo, esTV) {
        if (focused && enVivo && esTV) {
            delay(10000)
            if (focused) {
                mostrarVideoPreview = true
            }
        } else {
            mostrarVideoPreview = false
        }
    }

    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "cc"
    )

    val anchoCard = if (esTV) 360.dp else 260.dp
    val altoCard = if (esTV) 220.dp else 170.dp

    Column(
        Modifier
            .width(anchoCard)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(16.dp))
            .background(AppColors.Card)
            .border(borderWidth, borderColor, RoundedCornerShape(16.dp))
    ) {
        Box(
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
            }

            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                    )
                )
            )

            // Badge LIVE
            if (enVivo || (FechaHelper.esHoy(ev.fecha) && estaEnVivo(ev.hora))) {
                Box(
                    Modifier.align(Alignment.TopStart).padding(10.dp).alpha(pulse)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFEF4444))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(6.dp).clip(CircleShape).background(Color.White))
                        Spacer(Modifier.width(5.dp))
                        Text("LIVE", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    }
                }
            }

            // Badge hora
            Box(
                Modifier.align(Alignment.TopEnd).padding(10.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(AppColors.Gold)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text(
                    FechaHelper.badgeCard(ev.fecha, ev.hora),
                    color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black
                )
            }

            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 19.sp,
                modifier = Modifier.align(Alignment.BottomStart).padding(12.dp)
            )
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(color))
            Spacer(Modifier.width(6.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 12.sp)
            Spacer(Modifier.weight(1f))
            Icon(
                imageVector = if (focused) AppIcons.play else AppIcons.adelante,
                contentDescription = null,
                tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}'''

content = content[:match.start()] + nueva_funcion + content[match.end():]
print("✅ EventoCardPremium reemplazado")

# 3) Agregar CardVideoPreview al final
card_video = '''

// ═══════════════════════════════════════════════════════════
// 🎬 PREVIEW DE CARD EN VIVO (solo TV, mudo, 10 seg de foco)
// ═══════════════════════════════════════════════════════════
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
private fun CardVideoPreview(evento: Evento, modifier: Modifier = Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var videoUrl by remember { mutableStateOf<String?>(null) }

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
                volume = 0f
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
grep -c "private fun EventoCardPremium" "$FILE" | xargs -I {} echo "  EventoCardPremium: {} (debe ser 1)"
grep -c "private fun CardVideoPreview" "$FILE" | xargs -I {} echo "  CardVideoPreview: {} (debe ser 1)"
grep -c "val esTV = rememberEsTV()" "$FILE" | xargs -I {} echo "  esTV: {} (debe ser 1)"

echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"