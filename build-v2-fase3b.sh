#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-fase3b"

echo "📝 Agregando miniaturas en el panel lateral..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) PanelItem con miniatura
# ═══════════════════════════════════════════════════════════

# Reemplazar PanelItem por una versión con miniatura
old_panelitem = '''@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        when {
            focused -> Color(0x55D4AF37)
            seleccionado -> Color(0x331E3A8A)
            else -> Color(0x22FFFFFF)
        },
        tween(150), label = "piBg"
    )
    val border by animateColorAsState(
        when {
            focused -> Color(0xFFFFD700)
            seleccionado -> Color(0x884ADE80)
            else -> Color.Transparent
        },
        tween(150), label = "piBd"
    )

    Row(
        modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (focused) 2.dp else 0.dp, border, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(10.dp).clip(CircleShape).background(
                when {
                    seleccionado -> Color(0xFF4ADE80)
                    focused -> Color(0xFFFFD700)
                    else -> Color(0xFF64748B)
                }
            )
        )
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium,
                maxLines = 2
            )
            subtitulo?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, color = Color(0xFFFFD700), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (focused) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color(0xFFFFD700),
                modifier = Modifier.size(18.dp)
            )
        }
    }
}'''

new_panelitem = '''@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit,
    miniaturaUrl: String? = null  // 🆕 FASE 3b: URL de la miniatura
) {
    var focused by remember { mutableStateOf(false) }
    val bg by animateColorAsState(
        when {
            focused -> Color(0x55D4AF37)
            seleccionado -> Color(0x331E3A8A)
            else -> Color(0x22FFFFFF)
        },
        tween(150), label = "piBg"
    )
    val border by animateColorAsState(
        when {
            focused -> Color(0xFFFFD700)
            seleccionado -> Color(0x884ADE80)
            else -> Color.Transparent
        },
        tween(150), label = "piBd"
    )

    Row(
        modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(if (focused) 2.dp else 0.dp, border, RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 🆕 FASE 3b: Miniatura (si tiene URL)
        if (miniaturaUrl != null && miniaturaUrl.isNotBlank()) {
            Box(
                Modifier
                    .size(width = 70.dp, height = 42.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFF1A1A1A)),
                contentAlignment = Alignment.Center
            ) {
                coil.compose.AsyncImage(
                    model = miniaturaUrl,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                // Overlay con indicador de "en vivo"
                if (seleccionado) {
                    Box(
                        Modifier
                            .align(Alignment.TopStart)
                            .padding(3.dp)
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF4ADE80))
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
        } else {
            // Sin miniatura → círculo indicador (diseño viejo)
            Box(
                Modifier.size(10.dp).clip(CircleShape).background(
                    when {
                        seleccionado -> Color(0xFF4ADE80)
                        focused -> Color(0xFFFFD700)
                        else -> Color(0xFF64748B)
                    }
                )
            )
            Spacer(Modifier.width(14.dp))
        }

        Column(Modifier.weight(1f)) {
            Text(
                titulo,
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = if (seleccionado || focused) FontWeight.Bold else FontWeight.Medium,
                maxLines = 2
            )
            subtitulo?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, color = Color(0xFFFFD700), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (focused) {
            Icon(
                imageVector = AppIcons.play,
                contentDescription = null,
                tint = Color(0xFFFFD700),
                modifier = Modifier.size(18.dp)
            )
        }
    }
}'''

if old_panelitem in content:
    content = content.replace(old_panelitem, new_panelitem)
    print("✅ PanelItem con miniatura")
else:
    print("⚠️  No encontré PanelItem exacto")

# ═══════════════════════════════════════════════════════════
# 2) Pasar miniatura al PanelItem en el panel lateral
# ═══════════════════════════════════════════════════════════

# En la sección "Este evento" → pasar imagen del evento como miniatura
old_items_canal = '''            itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" }) { idx, emb ->
                val isFirst = idx == 0
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    onClick = { onCanalClick(emb) }
                )
            }'''

new_items_canal = '''            itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" }) { idx, emb ->
                val isFirst = idx == 0
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    miniaturaUrl = evento.imagen,
                    onClick = { onCanalClick(emb) }
                )
            }'''

if old_items_canal in content:
    content = content.replace(old_items_canal, new_items_canal)
    print("✅ Miniatura en canales del evento")

# En la sección "Otros eventos" → pasar imagen del evento
old_items_evento = '''                itemsIndexed(otros.take(30), key = { idx, it -> "ev_${idx}_${it.descripcion}_${it.fuente}_${it.hora}" }) { _, ev ->
                    PanelItem(
                        titulo = ev.descripcion,
                        subtitulo = "${ev.hora} · ${ev.fuente}",
                        seleccionado = false,
                        onClick = { onEventoClick(ev) }
                    )
                }'''

new_items_evento = '''                itemsIndexed(otros.take(30), key = { idx, it -> "ev_${idx}_${it.descripcion}_${it.fuente}_${it.hora}" }) { _, ev ->
                    PanelItem(
                        titulo = ev.descripcion,
                        subtitulo = "${ev.hora} · ${ev.fuente}",
                        seleccionado = false,
                        miniaturaUrl = ev.imagen,
                        onClick = { onEventoClick(ev) }
                    )
                }'''

if old_items_evento in content:
    content = content.replace(old_items_evento, new_items_evento)
    print("✅ Miniatura en otros eventos")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# Home: cards con hover animado (TV)
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Agregando hover animado en HomeScreen (TV)..."

HOME_FILE="$UI_DIR/HomeScreen.kt"
cp "$HOME_FILE" "$HOME_FILE.bak-fase3b"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Agregar elevación + info extra al enfocar (TV)
# Buscar EventoCardPremium y agregar tag de categoría extra al hover

# 1) Agregar info extra (badge de canales LIVE) al hover
# En el bloque de la card, después del título
old_bloque = '''        Row(
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
        }'''

new_bloque = '''        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(color))
            Spacer(Modifier.width(6.dp))
            Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 12.sp)

            // 🆕 FASE 3b: Al enfocar, mostrar fuente (efecto hover)
            if (focused && ev.fuente.isNotBlank()) {
                Spacer(Modifier.width(8.dp))
                Box(
                    Modifier.clip(RoundedCornerShape(4.dp))
                        .background(color.copy(alpha = 0.25f))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        ev.fuente,
                        color = color,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1
                    )
                }
            }

            Spacer(Modifier.weight(1f))
            Icon(
                imageVector = if (focused) AppIcons.play else AppIcons.adelante,
                contentDescription = null,
                tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
                modifier = Modifier.size(18.dp)
            )
        }'''

if old_bloque in content:
    content = content.replace(old_bloque, new_bloque)
    print("✅ Hover cards en TV")
else:
    print("⚠️  No encontré el bloque de info de la card")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "miniaturaUrl" "$FILE" && echo "  ✓ Miniaturas en panel"
grep -q "Hover cards" "$HOME_FILE" && echo "  ✓ Hover cards en TV"

echo ""
echo "✅✅✅ FASE 3b completo — Miniaturas + Hover cards"
echo ""
echo "📌 Qué cambió:"
echo "   • Panel lateral: cada canal tiene su miniatura"
echo "   • Panel lateral: cada evento (otros) tiene miniatura"
echo "   • Home TV: al enfocar una card, aparece la fuente"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"