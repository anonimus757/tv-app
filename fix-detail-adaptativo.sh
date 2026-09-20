#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/EventDetailScreen.kt"

cp "$FILE" "$FILE.bak-adaptativo"

echo "📝 Reescribiendo EventDetailScreen.kt con tamaños adaptativos..."

cat > "$FILE" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento
import com.anonimus757.tvapp.data.FechaHelper
import com.anonimus757.tvapp.ui.animations.fadeInOnLoad
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons
import com.anonimus757.tvapp.ui.util.rememberEsTV

@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    // ═══════════════════════════════════════════════════════════
    // FIX: Back del celu/TV → volver al Home (no cerrar la app)
    // ═══════════════════════════════════════════════════════════
    BackHandler {
        onBack()
    }

    val esTV = rememberEsTV()
    val color = AppColors.fuenteColor(evento.groupTitle)

    // ═══════════════════════════════════════════════════════════
    // Tamaños adaptativos: TV más grandes, celu más compactos
    // ═══════════════════════════════════════════════════════════
    val paddingH = if (esTV) 48.dp else 18.dp
    val paddingV = if (esTV) 36.dp else 20.dp
    val headerImgSize = if (esTV) 110.dp else 72.dp
    val headerImgInner = if (esTV) 80.dp else 54.dp
    val headerGap = if (esTV) 26.dp else 14.dp
    val tituloSize = if (esTV) 32.sp else 20.sp
    val tituloLineHeight = if (esTV) 38.sp else 24.sp
    val badgeSize = if (esTV) 13.sp else 11.sp
    val metaSize = if (esTV) 14.sp else 12.sp
    val iconoMeta = if (esTV) 14.dp else 12.dp
    val gapHeaderContenido = if (esTV) 44.dp else 20.dp
    val elegirSize = if (esTV) 22.sp else 16.sp
    val iconoElegirSize = if (esTV) 22.dp else 18.dp
    val gapAntesLista = if (esTV) 20.dp else 12.dp
    val cardPaddingH = if (esTV) 24.dp else 14.dp
    val cardPaddingV = if (esTV) 20.dp else 14.dp
    val playCircleSize = if (esTV) 50.dp else 42.dp
    val playIconSize = if (esTV) 26.dp else 20.dp
    val playGap = if (esTV) 20.dp else 14.dp
    val canalNombreSize = if (esTV) 20.sp else 15.sp
    val canalHintSize = if (esTV) 14.sp else 12.sp

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(AppColors.Background, AppColors.BackgroundGradient))
            )
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = paddingH, vertical = paddingV)
        ) {

            // ═══════════════════════════════════════════════════════════
            // Botón "Volver"
            // ═══════════════════════════════════════════════════════════
            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(durationMs = 350),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BotonVolverDetalle(onBack, esTV)
            }
            Spacer(Modifier.height(if (esTV) 24.dp else 14.dp))

            // ═══════════════════════════════════════════════════════════
            // Header del evento
            // ═══════════════════════════════════════════════════════════
            Row(
                Modifier.fadeInOnLoad(durationMs = 450),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier
                        .size(headerImgSize)
                        .clip(RoundedCornerShape(if (esTV) 16.dp else 12.dp))
                        .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                    contentAlignment = Alignment.Center
                ) {
                    if (evento.imagen.isNotBlank()) {
                        AsyncImage(
                            model = evento.imagen,
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.size(headerImgInner)
                        )
                    } else {
                        Text("⚽", fontSize = if (esTV) 46.sp else 32.sp)
                    }
                }
                Spacer(Modifier.width(headerGap))
                Column(Modifier.weight(1f)) {
                    Text(
                        evento.descripcion,
                        color = AppColors.TextPrimary,
                        fontSize = tituloSize,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        lineHeight = tituloLineHeight,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.height(if (esTV) 10.dp else 6.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(color.copy(alpha = 0.2f))
                                .padding(horizontal = if (esTV) 10.dp else 7.dp, vertical = if (esTV) 4.dp else 3.dp)
                        ) {
                            Text(
                                "${AppColors.fuenteIcono(evento.groupTitle)} ${evento.groupTitle}",
                                color = color,
                                fontSize = badgeSize,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1
                            )
                        }
                        Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
                        Icon(
                            imageVector = AppIcons.reloj,
                            contentDescription = null,
                            tint = AppColors.GoldBright,
                            modifier = Modifier.size(iconoMeta)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            FechaHelper.badgeCard(evento.fecha, evento.hora),
                            color = AppColors.GoldBright,
                            fontSize = metaSize,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        evento.fuente,
                        color = AppColors.TextSecondary,
                        fontSize = metaSize
                    )
                }
            }

            Spacer(Modifier.height(gapHeaderContenido))

            // ═══════════════════════════════════════════════════════════
            // "Elige un canal"
            // ═══════════════════════════════════════════════════════════
            Row(
                Modifier.fadeInOnLoad(durationMs = 450, delayMs = 100),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = AppIcons.canales,
                    contentDescription = null,
                    tint = AppColors.GoldBright,
                    modifier = Modifier.size(iconoElegirSize)
                )
                Spacer(Modifier.width(if (esTV) 10.dp else 6.dp))
                Text(
                    if (esTV) "Elige un canal para reproducir" else "Elegí un canal",
                    color = AppColors.TextPrimary,
                    fontSize = elegirSize,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.width(if (esTV) 12.dp else 8.dp))
                Box(
                    Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(AppColors.Gold.copy(alpha = 0.2f))
                        .padding(horizontal = if (esTV) 10.dp else 7.dp, vertical = if (esTV) 3.dp else 2.dp)
                ) {
                    Text(
                        "${evento.embeds.size}",
                        color = AppColors.Gold,
                        fontSize = if (esTV) 12.sp else 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            Spacer(Modifier.height(gapAntesLista))

            // ═══════════════════════════════════════════════════════════
            // Lista de canales
            // ═══════════════════════════════════════════════════════════
            LazyColumn(verticalArrangement = Arrangement.spacedBy(if (esTV) 12.dp else 8.dp)) {
                itemsIndexed(
                    items = evento.embeds,
                    key = { idx, it -> "emb_${idx}_${it.url}" }
                ) { index, embed ->
                    Box(
                        Modifier.fadeInOnLoad(
                            durationMs = 400,
                            delayMs = 150 + index * 50,
                            slideFromDp = 16f
                        )
                    ) {
                        CanalCardPro(
                            embed = embed,
                            esTV = esTV,
                            paddingH = cardPaddingH,
                            paddingV = cardPaddingV,
                            playCircleSize = playCircleSize,
                            playIconSize = playIconSize,
                            playGap = playGap,
                            nombreSize = canalNombreSize,
                            hintSize = canalHintSize,
                            onClick = { onCanalClick(embed) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CanalCardPro(
    embed: Embed,
    esTV: Boolean,
    paddingH: androidx.compose.ui.unit.Dp,
    paddingV: androidx.compose.ui.unit.Dp,
    playCircleSize: androidx.compose.ui.unit.Dp,
    playIconSize: androidx.compose.ui.unit.Dp,
    playGap: androidx.compose.ui.unit.Dp,
    nombreSize: androidx.compose.ui.unit.TextUnit,
    hintSize: androidx.compose.ui.unit.TextUnit,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 2.dp else 1.dp,
        animationSpec = tween(180),
        label = "canalBorderWidth"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.2f),
        animationSpec = tween(180),
        label = "canalBorderColor"
    )
    val bgColor by animateColorAsState(
        targetValue = if (focused) AppColors.CardFocus else AppColors.Card,
        animationSpec = tween(180),
        label = "canalBg"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = if (esTV) 1.02f else 1.01f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(if (esTV) 14.dp else 12.dp))
            .background(bgColor)
            .border(borderWidth, borderColor, RoundedCornerShape(if (esTV) 14.dp else 12.dp))
            .padding(horizontal = paddingH, vertical = paddingV),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(playCircleSize)
                .clip(CircleShape)
                .background(if (focused) AppColors.GoldBright else AppColors.Gold),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color.Black,
                modifier = Modifier.size(playIconSize)
            )
        }
        Spacer(Modifier.width(playGap))
        Text(
            embed.nombre,
            color = AppColors.TextPrimary,
            fontSize = nombreSize,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        // En celu no mostramos el texto "OK para reproducir" (muy largo)
        if (esTV) {
            Text(
                if (focused) "Reproducir" else "OK para reproducir",
                color = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                fontSize = hintSize,
                fontWeight = if (focused) FontWeight.SemiBold else FontWeight.Normal
            )
        } else {
            Icon(
                imageVector = if (focused) AppIcons.play else AppIcons.adelante,
                contentDescription = null,
                tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun BotonVolverDetalle(onClick: () -> Unit, esTV: Boolean) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(if (esTV) 10.dp else 8.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(
                if (esTV) 2.dp else 1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(if (esTV) 10.dp else 8.dp)
            )
            .clickable { onClick() }
            .padding(
                horizontal = if (esTV) 16.dp else 12.dp,
                vertical = if (esTV) 10.dp else 8.dp
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(if (esTV) 20.dp else 16.dp)
        )
        Spacer(Modifier.width(if (esTV) 8.dp else 6.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else AppColors.Gold,
            fontSize = if (esTV) 14.sp else 13.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
EOF

echo "✅ EventDetailScreen.kt reescrito"

echo ""
echo "🔎 Verificando:"
grep -q "rememberEsTV" "$FILE" && echo "  ✓ Detección TV/Celu"
grep -q "val paddingH = if (esTV)" "$FILE" && echo "  ✓ Tamaños adaptativos"
grep -q "if (esTV) \"Elige un canal para reproducir\"" "$FILE" && echo "  ✓ Textos adaptativos"

echo ""
echo "✅✅✅ Fix adaptativo completo"
echo ""
echo "📌 Qué cambia según dispositivo:"
echo ""
echo "   📱 CELU:"
echo "      • Padding: 18×20 (antes 48×36)"
echo "      • Imagen: 72dp (antes 110dp)"
echo "      • Título: 20sp (antes 32sp)"
echo "      • Cards: padding 14×14 (antes 24×20)"
echo "      • Botón play: 42dp (antes 50dp)"
echo "      • Textos secundarios se ocultan si no aportan"
echo ""
echo "   📺 TV:"
echo "      • Se mantiene igual que antes (grande, cómodo de lejos)"
echo ""
echo "🚀 Compilá mañana:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"