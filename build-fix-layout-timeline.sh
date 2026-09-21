#!/bin/bash
set -e

DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.layout.$(date +%s)"
echo "✅ Backup: ${DETAIL}.bak.layout.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# 1. Quitar TimelinePremium de SeccionEnVivo
# ═══════════════════════════════════════════════════════════
viejo_section = '''        if (partido != null) {
            MarcadorBroadcast(partido, esTV, esMovil)
            if (partido.estadisticas != null && partido.enVivo) {
                Spacer(Modifier.height(14.dp))
                StatsCardPremium(
                    partido.estadisticas, esTV, esMovil,
                    expandidas = esTV || statsExpandidas,
                    colapsable = !esTV,
                    onToggle = onToggleStats
                )
            }
            if (partido.eventos.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                TimelinePremium(partido.eventos, partido.localNombre, partido.visitanteNombre, esTV, esMovil)
            }
        } else if (error != null) {'''

nuevo_section = '''        if (partido != null) {
            MarcadorBroadcast(partido, esTV, esMovil, evento)
            if (partido.estadisticas != null && partido.enVivo) {
                Spacer(Modifier.height(14.dp))
                StatsCardPremium(
                    partido.estadisticas, esTV, esMovil,
                    expandidas = esTV || statsExpandidas,
                    colapsable = !esTV,
                    onToggle = onToggleStats
                )
            }
        } else if (error != null) {'''

if viejo_section in c:
    c = c.replace(viejo_section, nuevo_section, 1)
    print("✅ TimelinePremium removido de SeccionEnVivo")
else:
    print("⚠️ No matcheó el bloque de SeccionEnVivo. Aplicando variante...")
    # Variante por si hay espacios
    c = re.sub(
        r'(\s*)if \(partido\.eventos\.isNotEmpty\(\)\) \{\s*\n\s*Spacer\(Modifier\.height\(14\.dp\)\)\s*\n\s*TimelinePremium\(partido\.eventos.*?\n\s*\}',
        '',
        c, count=1, flags=re.DOTALL
    )

# ═══════════════════════════════════════════════════════════
# 2. Agregar TimelinePremium después de los canales
# ═══════════════════════════════════════════════════════════
viejo_canales = '''                    itemsIndexed(
                        items = evento.embeds,
                        key = { idx, it -> "emb_${idx}_${it.url}" }
                    ) { index, embed ->
                        Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                            CanalCardPremium(embed, index + 1, esTV, esMovil) { onCanalClick(embed) }
                        }
                    }
                }'''

nuevo_canales = '''                    itemsIndexed(
                        items = evento.embeds,
                        key = { idx, it -> "emb_${idx}_${it.url}" }
                    ) { index, embed ->
                        Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                            CanalCardPremium(embed, index + 1, esTV, esMovil) { onCanalClick(embed) }
                        }
                    }

                    // 🆕 Timeline DESPUÉS de los canales
                    val p = partido
                    if (p != null && p.eventos.isNotEmpty()) {
                        item(key = "timeline_completo") {
                            Spacer(Modifier.height(8.dp))
                            TimelinePremium(p.eventos, p.localNombre, p.visitanteNombre, esTV, esMovil)
                        }
                    }
                }'''

if viejo_canales in c:
    c = c.replace(viejo_canales, nuevo_canales, 1)
    print("✅ TimelinePremium movido después de canales")
else:
    print("⚠️ No matcheó el bloque de canales")

# ═══════════════════════════════════════════════════════════
# 3. Modificar MarcadorBroadcast para incluir mini info
# ═══════════════════════════════════════════════════════════
# Reemplazar la firma para agregar evento
c = c.replace(
    'private fun MarcadorBroadcast(partido: PartidoEnVivo, esTV: Boolean, esMovil: Boolean) {',
    'private fun MarcadorBroadcast(partido: PartidoEnVivo, esTV: Boolean, esMovil: Boolean, evento: Evento) {'
)

# Agregar MiniEventosEquipo después del bloque de cada equipo
# Local: después del Text(partido.localNombre...)
viejo_local = '''                Text(partido.localNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
            }'''

nuevo_local = '''                Text(partido.localNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(6.dp))
                MiniEventosEquipo(
                    eventos = partido.eventos.filter { ev ->
                        ev.equipo.equals(partido.localNombre, ignoreCase = true) ||
                        partido.localNombre.contains(ev.equipo, ignoreCase = true) ||
                        ev.equipo.contains(partido.localNombre, ignoreCase = true)
                    },
                    esMovil = esMovil
                )
            }'''

if viejo_local in c:
    c = c.replace(viejo_local, nuevo_local, 1)
    print("✅ Mini info agregada al equipo local")
else:
    print("⚠️ No matcheó bloque local")

# Visitante
viejo_visit = '''                Text(partido.visitanteNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
            }'''

nuevo_visit = '''                Text(partido.visitanteNombre, color = Color.White,
                    fontSize = if (esMovil) 13.sp else 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2, textAlign = TextAlign.Center,
                    lineHeight = if (esMovil) 15.sp else 17.sp,
                    overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(6.dp))
                MiniEventosEquipo(
                    eventos = partido.eventos.filter { ev ->
                        ev.equipo.equals(partido.visitanteNombre, ignoreCase = true) ||
                        partido.visitanteNombre.contains(ev.equipo, ignoreCase = true) ||
                        ev.equipo.contains(partido.visitanteNombre, ignoreCase = true)
                    },
                    esMovil = esMovil
                )
            }'''

if viejo_visit in c:
    c = c.replace(viejo_visit, nuevo_visit, 1)
    print("✅ Mini info agregada al equipo visitante")

# ═══════════════════════════════════════════════════════════
# 4. Agregar el composable MiniEventosEquipo antes de StatsCardPremium
# ═══════════════════════════════════════════════════════════
ancla_stats = '// ═══════════════════════════════════════════════════════════════\n// STATS PREMIUM'

mini = '''// ═══════════════════════════════════════════════════════════════
// MINI EVENTOS (debajo de cada equipo)
// ═══════════════════════════════════════════════════════════════

@Composable
private fun MiniEventosEquipo(eventos: List<EventoPartido>, esMovil: Boolean) {
    // Solo goles y tarjetas (no substituciones ni VAR)
    val destacados = eventos
        .filter { it.tipo == "Goal" || it.tipo == "Card" }
        .sortedBy { it.minuto }
        .take(3)

    if (destacados.isEmpty()) return

    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        destacados.forEach { ev ->
            Row(
                Modifier.padding(vertical = 1.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(emojiEvento(ev.tipo, ev.detalle),
                    fontSize = if (esMovil) 11.sp else 12.sp)
                Spacer(Modifier.width(4.dp))
                val apellido = ev.jugador.split(" ").lastOrNull()?.take(12) ?: "—"
                Text(
                    "$apellido ${ev.minuto}'",
                    color = AppColors.TextSecondary,
                    fontSize = if (esMovil) 9.sp else 10.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

'''

if ancla_stats in c and 'private fun MiniEventosEquipo' not in c:
    c = c.replace(ancla_stats, mini + ancla_stats, 1)
    print("✅ Composable MiniEventosEquipo agregado")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ Layout reorganizado correctamente")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
