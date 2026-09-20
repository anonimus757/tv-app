#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"

cp "$FILE" "$FILE.bak-vertical"

echo "📝 Adaptando FilaEventos y HeaderFutTV al modo vertical..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) FilaEventos → condicional (Column en vertical, LazyRow si no)
# ═══════════════════════════════════════════════════════════

old_fila = '''@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    enVivo: Boolean = false
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        itemsIndexed(items = lista, key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }) { index, ev ->
            Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 200 + index * 60, slideFromDp = 20f)) {
                EventoCardPremium(ev, enVivo = enVivo) { onEventoClick(ev, lista) }
            }
        }
    }
}'''

new_fila = '''@Composable
private fun FilaEventos(
    lista: List<Evento>,
    onEventoClick: (Evento, List<Evento>) -> Unit,
    enVivo: Boolean = false
) {
    val esTV = rememberEsTV()
    val config = LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT && !esTV

    if (esVertical) {
        // 📱 En vertical → lista apilada de cards compactas
        Column(
            Modifier.fillMaxWidth().padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            lista.forEachIndexed { index, ev ->
                Box(
                    Modifier.fadeInOnLoad(
                        durationMs = 400,
                        delayMs = 150 + index * 50,
                        slideFromDp = 15f
                    )
                ) {
                    EventoCardPremium(ev, enVivo = enVivo) { onEventoClick(ev, lista) }
                }
            }
        }
    } else {
        // 📺 En TV o celu horizontal → LazyRow como siempre
        LazyRow(
            contentPadding = PaddingValues(horizontal = 40.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            itemsIndexed(items = lista, key = { _, it -> "${it.fuente}_${it.fecha}_${it.hora}_${it.descripcion}" }) { index, ev ->
                Box(Modifier.fadeInOnLoad(durationMs = 400, delayMs = 200 + index * 60, slideFromDp = 20f)) {
                    EventoCardPremium(ev, enVivo = enVivo) { onEventoClick(ev, lista) }
                }
            }
        }
    }
}'''

if old_fila in content:
    content = content.replace(old_fila, new_fila, 1)
    print("✅ FilaEventos condicional")
else:
    print("⚠️  No encontré FilaEventos exacta")

# ═══════════════════════════════════════════════════════════
# 2) HeaderFutTV → adaptativo
# ═══════════════════════════════════════════════════════════

old_header = '''@Composable
private fun HeaderFutTV(
    textoBienvenida: String,
    totalEventos: Int,
    totalCanales: Int,
    refrescando: Boolean,
    onRefrescar: () -> Unit,
    onIrAAjustes: () -> Unit,
    onIrABusqueda: () -> Unit
) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    Row(
        Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 24.dp).fadeInOnLoad(durationMs = 400),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("⚽", fontSize = 32.sp)
        Spacer(Modifier.width(10.dp))
        Text("FutTV", color = AppColors.GoldBright, fontSize = 34.sp,
            fontWeight = FontWeight.Black, letterSpacing = 3.sp)
        Spacer(Modifier.width(16.dp))
        Box(
            Modifier.alpha(pulse)
                .clip(RoundedCornerShape(8.dp))
                .background(AppColors.Gold.copy(alpha = 0.15f))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                .padding(horizontal = 10.dp, vertical = 4.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = AppIcons.enVivo,
                    contentDescription = null,
                    tint = AppColors.Gold,
                    modifier = Modifier.size(8.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text("EN VIVO", color = AppColors.Gold, fontSize = 11.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
            }
        }
        Spacer(Modifier.weight(1f))
        Text("$totalEventos eventos · $totalCanales canales",
            color = AppColors.TextSecondary, fontSize = 12.sp)
        Spacer(Modifier.width(16.dp))

        BotonHeader(icono = AppIcons.buscar, onClick = onIrABusqueda, label = "Buscar")
        Spacer(Modifier.width(8.dp))
        BotonHeader(icono = AppIcons.ajustes, onClick = onIrAAjustes, label = "Ajustes")
        Spacer(Modifier.width(8.dp))
        BotonHeader(
            icono = if (refrescando) AppIcons.cargando else AppIcons.refrescar,
            onClick = { if (!refrescando) onRefrescar() },
            label = "Actualizar"
        )
    }
}'''

new_header = '''@Composable
private fun HeaderFutTV(
    textoBienvenida: String,
    totalEventos: Int,
    totalCanales: Int,
    refrescando: Boolean,
    onRefrescar: () -> Unit,
    onIrAAjustes: () -> Unit,
    onIrABusqueda: () -> Unit
) {
    val pulse = rememberPulseAlpha(min = 0.35f, max = 1f, durationMs = 900)

    val esTV = rememberEsTV()
    val config = LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT && !esTV

    // Tamaños adaptativos
    val paddingH = if (esVertical) 16.dp else 40.dp
    val paddingV = if (esVertical) 14.dp else 24.dp
    val logoSize = if (esVertical) 26.sp else 32.sp
    val tituloSize = if (esVertical) 26.sp else 34.sp
    val gapEntreElementos = if (esVertical) 8.dp else 16.dp
    val gapChico = if (esVertical) 6.dp else 8.dp

    if (esVertical) {
        // 📱 En vertical → 2 filas: logo+badge arriba, botones abajo
        Column(
            Modifier.fillMaxWidth().padding(horizontal = paddingH, vertical = paddingV)
                .fadeInOnLoad(durationMs = 400)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("⚽", fontSize = logoSize)
                Spacer(Modifier.width(8.dp))
                Text(
                    "FutTV",
                    color = AppColors.GoldBright,
                    fontSize = tituloSize,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 2.sp
                )
                Spacer(Modifier.width(10.dp))
                Box(
                    Modifier.alpha(pulse)
                        .clip(RoundedCornerShape(6.dp))
                        .background(AppColors.Gold.copy(alpha = 0.15f))
                        .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.enVivo,
                            contentDescription = null,
                            tint = AppColors.Gold,
                            modifier = Modifier.size(7.dp)
                        )
                        Spacer(Modifier.width(5.dp))
                        Text("EN VIVO", color = AppColors.Gold, fontSize = 10.sp,
                            fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                    }
                }
                Spacer(Modifier.weight(1f))
                // Botones en la misma fila que el logo (a la derecha)
                BotonHeader(icono = AppIcons.buscar, onClick = onIrABusqueda, label = "Buscar")
                Spacer(Modifier.width(gapChico))
                BotonHeader(icono = AppIcons.ajustes, onClick = onIrAAjustes, label = "Ajustes")
                Spacer(Modifier.width(gapChico))
                BotonHeader(
                    icono = if (refrescando) AppIcons.cargando else AppIcons.refrescar,
                    onClick = { if (!refrescando) onRefrescar() },
                    label = "Actualizar"
                )
            }
            Spacer(Modifier.height(6.dp))
            // Contador de eventos abajo, pequeño
            Text(
                "$totalEventos eventos · $totalCanales canales",
                color = AppColors.TextSecondary,
                fontSize = 11.sp
            )
        }
    } else {
        // 📺 En TV o celu horizontal → diseño original en 1 fila
        Row(
            Modifier.fillMaxWidth().padding(horizontal = paddingH, vertical = paddingV)
                .fadeInOnLoad(durationMs = 400),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("⚽", fontSize = logoSize)
            Spacer(Modifier.width(10.dp))
            Text("FutTV", color = AppColors.GoldBright, fontSize = tituloSize,
                fontWeight = FontWeight.Black, letterSpacing = 3.sp)
            Spacer(Modifier.width(gapEntreElementos))
            Box(
                Modifier.alpha(pulse)
                    .clip(RoundedCornerShape(8.dp))
                    .background(AppColors.Gold.copy(alpha = 0.15f))
                    .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = AppIcons.enVivo,
                        contentDescription = null,
                        tint = AppColors.Gold,
                        modifier = Modifier.size(8.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("EN VIVO", color = AppColors.Gold, fontSize = 11.sp,
                        fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                }
            }
            Spacer(Modifier.weight(1f))
            Text("$totalEventos eventos · $totalCanales canales",
                color = AppColors.TextSecondary, fontSize = 12.sp)
            Spacer(Modifier.width(16.dp))

            BotonHeader(icono = AppIcons.buscar, onClick = onIrABusqueda, label = "Buscar")
            Spacer(Modifier.width(8.dp))
            BotonHeader(icono = AppIcons.ajustes, onClick = onIrAAjustes, label = "Ajustes")
            Spacer(Modifier.width(8.dp))
            BotonHeader(
                icono = if (refrescando) AppIcons.cargando else AppIcons.refrescar,
                onClick = { if (!refrescando) onRefrescar() },
                label = "Actualizar"
            )
        }
    }
}'''

if old_header in content:
    content = content.replace(old_header, new_header, 1)
    print("✅ HeaderFutTV adaptativo")
else:
    print("⚠️  No encontré HeaderFutTV exacto")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "En vertical → lista apilada de cards compactas" "$FILE" && echo "  ✓ FilaEventos condicional"
grep -q "En vertical → 2 filas: logo+badge arriba" "$FILE" && echo "  ✓ HeaderFutTV adaptativo"

echo ""
echo "✅✅✅ Fix vertical aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   📱 En vertical:"
echo "      • Cards apiladas una por fila (estilo lista)"
echo "      • Header: logo arriba + botones 🔍⚙️🔄 a la derecha"
echo "      • Contador '54 eventos' chico abajo"
echo "   📺 En TV/horizontal:"
echo "      • Nada cambia, todo igual que antes"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"