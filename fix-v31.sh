#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"

cp "$FILE" "$FILE.bak-fix-v31"

echo "📝 Agregando EventoCardVerticalCompacta al final del archivo..."

# Primero verificar si ya está
if grep -q "private fun EventoCardVerticalCompacta" "$FILE"; then
    echo "ℹ️  Ya existía, la quito y la vuelvo a agregar..."
    # La sacamos para reescribirla limpia
    python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Quitar la función vieja (con regex no-greedy)
pattern = r'\n// ═+\n// 🆕 CARD VERTICAL COMPACTA.*?(?=\n// ═|\Z)'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open(file_path, "w") as f:
    f.write(content)
print("✅ Función vieja removida")
PYEOF
fi

# Ahora agregarla limpia
cat >> "$FILE" << 'EOF'


// ═══════════════════════════════════════════════════════════
// 🆕 CARD VERTICAL COMPACTA (celu en modo parado)
// Estilo lista: imagen a la izquierda, info a la derecha
// ═══════════════════════════════════════════════════════════
@Composable
private fun EventoCardVerticalCompacta(
    ev: Evento,
    enVivo: Boolean,
    focused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    onClick: () -> Unit
) {
    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(
        targetValue = if (focused) 2.dp else 1.dp,
        animationSpec = tween(180),
        label = "vcbw"
    )
    val borderColor by animateColorAsState(
        targetValue = if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        animationSpec = tween(180),
        label = "vcbc"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .onFocusChanged { onFocusChange(it.isFocused) }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(borderWidth, borderColor, RoundedCornerShape(12.dp))
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(width = 80.dp, height = 80.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(60.dp)
                )
            } else {
                Text("⚽", fontSize = 36.sp)
            }

            if (enVivo || (FechaHelper.esHoy(ev.fecha) && estaEnVivo(ev.hora))) {
                Box(
                    Modifier.align(Alignment.TopEnd).padding(4.dp).alpha(pulse)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color(0xFFEF4444))
                        .padding(horizontal = 4.dp, vertical = 1.dp)
                ) {
                    Text("LIVE", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                }
            }
        }

        Spacer(Modifier.width(12.dp))

        Column(Modifier.weight(1f)) {
            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 18.sp
            )
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(5.dp))
                Text(
                    FechaHelper.badgeCard(ev.fecha, ev.hora),
                    color = AppColors.GoldBright,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.width(8.dp))
                Text("·", color = AppColors.TextMuted, fontSize = 11.sp)
                Spacer(Modifier.width(8.dp))
                Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 11.sp)
            }
        }

        Icon(
            imageVector = if (focused) AppIcons.play else AppIcons.adelante,
            contentDescription = null,
            tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            modifier = Modifier.size(18.dp)
        )
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -c "private fun EventoCardVerticalCompacta" "$FILE" | xargs -I {} echo "  EventoCardVerticalCompacta: {} (debe ser 1)"
tail -5 "$FILE"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"