#!/bin/bash
set -e

DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.timelinescroll.$(date +%s)"
echo "✅ Backup: ${DETAIL}.bak.timelinescroll.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── Reemplazar toda la función TimelinePremium ───
patron = re.compile(
    r'@Composable\s+private\s+fun\s+TimelinePremium\s*\([^)]*\)\s*\{.*?\n\}\n\n@Composable\s+private\s+fun\s+CargandoCard',
    re.DOTALL
)

nuevo = '''@Composable
private fun TimelinePremium(
    eventos: List<EventoPartido>,
    localNombre: String, visitanteNombre: String,
    esTV: Boolean, esMovil: Boolean
) {
    val eventosOrdenados = remember(eventos) {
        eventos.sortedByDescending { it.minuto }
    }
    val alturaMax = when {
        esTV -> 480.dp
        esMovil -> 320.dp
        else -> 380.dp
    }

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(
                Brush.verticalGradient(listOf(Color(0xFF15151C), Color(0xFF0A0A0F)))
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.2f), RoundedCornerShape(20.dp))
            .padding(if (esMovil) 16.dp else 20.dp)
    ) {
        // ─── Header ───
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⚡", fontSize = if (esMovil) 16.sp else 18.sp)
            Spacer(Modifier.width(8.dp))
            Text("EVENTOS DEL PARTIDO", color = AppColors.GoldBright,
                fontSize = if (esMovil) 12.sp else 13.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            Spacer(Modifier.width(8.dp))
            Box(
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(AppColors.Gold.copy(alpha = 0.2f))
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            ) {
                Text("${eventosOrdenados.size}", color = AppColors.Gold,
                    fontSize = 11.sp, fontWeight = FontWeight.Black)
            }
            Spacer(Modifier.weight(1f))
            if (eventosOrdenados.size > 3) {
                Text("▼ deslizá", color = AppColors.TextMuted,
                    fontSize = 10.sp, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic)
            }
        }
        Spacer(Modifier.height(14.dp))

        // ─── Lista scrollable con altura máxima ───
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = alturaMax)
                .verticalScroll(rememberScrollState())
        ) {
            eventosOrdenados.forEachIndexed { idx, ev ->
                EventoTimeline(
                    ev = ev,
                    indice = idx,
                    total = eventosOrdenados.size,
                    localNombre = localNombre,
                    esTV = esTV,
                    esMovil = esMovil
                )
            }
        }
    }
}

@Composable
private fun EventoTimeline(
    ev: EventoPartido,
    indice: Int,
    total: Int,
    localNombre: String,
    esTV: Boolean,
    esMovil: Boolean
) {
    var focused by remember { mutableStateOf(false) }
    val color = colorEvento(ev.tipo, ev.detalle)
    val esLocal = ev.equipo.equals(localNombre, ignoreCase = true) ||
            localNombre.contains(ev.equipo, ignoreCase = true) ||
            ev.equipo.contains(localNombre, ignoreCase = true)

    val bgColor by animateColorAsState(
        if (focused) Color.White.copy(alpha = 0.06f) else Color.Transparent,
        tween(180), label = "eventoBg"
    )
    val scale by animateFloatAsState(if (focused) 1.02f else 1f, tween(180), label = "eventoScale")

    Column(
        Modifier
            .fillMaxWidth()
            .scale(scale)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bgColor)
            .padding(vertical = 4.dp, horizontal = 4.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // Minuto
            Box(
                Modifier.width(if (esMovil) 44.dp else 50.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(color.copy(alpha = if (focused) 0.3f else 0.18f))
                    .border(
                        if (focused) 1.5.dp else 1.dp,
                        color.copy(alpha = if (focused) 0.9f else 0.5f),
                        RoundedCornerShape(8.dp)
                    )
                    .padding(vertical = if (esMovil) 5.dp else 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Text("${ev.minuto}'", color = color,
                    fontSize = if (esMovil) 12.sp else 13.sp,
                    fontWeight = FontWeight.Black)
            }
            Spacer(Modifier.width(if (esMovil) 10.dp else 14.dp))

            // Ícono grande
            Box(
                Modifier.size(if (esMovil) 34.dp else 40.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.radialGradient(
                            listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0.15f))
                        )
                    )
                    .border(
                        if (focused) 2.dp else 1.dp,
                        color.copy(alpha = if (focused) 1f else 0.6f),
                        CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(emojiEvento(ev.tipo, ev.detalle),
                    fontSize = if (esMovil) 15.sp else 18.sp)
            }
            Spacer(Modifier.width(if (esMovil) 10.dp else 14.dp))

            // Info
            Column(Modifier.weight(1f)) {
                Text(
                    ev.jugador.ifBlank { ev.detalle },
                    color = if (focused) AppColors.GoldBright else Color.White,
                    fontSize = if (esMovil) 13.sp else 14.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(2.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (esLocal) "🏠" else "✈️",
                        fontSize = if (esMovil) 10.sp else 11.sp
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        ev.equipo,
                        color = AppColors.TextSecondary,
                        fontSize = if (esMovil) 10.sp else 11.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                    if (ev.detalle.isNotBlank() && ev.detalle != "Normal Goal" && ev.detalle != "Yellow Card" && ev.detalle != "Red Card") {
                        Spacer(Modifier.width(6.dp))
                        Text("·", color = AppColors.TextMuted, fontSize = 11.sp)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            ev.detalle,
                            color = AppColors.TextMuted,
                            fontSize = if (esMovil) 9.sp else 10.sp,
                            fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                            maxLines = 1, overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        // Línea conectora (excepto el último)
        if (indice < total - 1) {
            Box(
                Modifier
                    .padding(start = if (esMovil) 22.dp else 25.dp, top = 6.dp)
                    .width(1.dp)
                    .height(if (esMovil) 16.dp else 18.dp)
                    .background(Color.White.copy(alpha = 0.08f))
            )
        } else {
            Spacer(Modifier.height(4.dp))
        }
    }
}

@Composable
private fun CargandoCard'''

c_nuevo, n = re.subn(patron, nuevo, c, count=1, flags=re.DOTALL)

if n == 0:
    print("❌ No matcheó TimelinePremium. Abortando.")
    raise SystemExit(1)

c = c_nuevo

# ─── Agregar imports que faltan ───
imports_extra = [
    'import androidx.compose.foundation.rememberScrollState',
    'import androidx.compose.foundation.verticalScroll',
    'import androidx.compose.foundation.layout.heightIn',
]
lineas = c.split('\n')
for imp in imports_extra:
    if imp not in c:
        # Insertar después del último import de foundation
        idx_ultimo_foundation = -1
        for i, l in enumerate(lineas):
            if l.startswith('import androidx.compose.foundation.'):
                idx_ultimo_foundation = i
        if idx_ultimo_foundation > 0:
            lineas.insert(idx_ultimo_foundation + 1, imp)
            print(f"✅ Import agregado: {imp}")

c = '\n'.join(lineas)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ TimelinePremium actualizado con scroll + focusable")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
