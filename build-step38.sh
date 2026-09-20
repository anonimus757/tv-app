#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

# ─────────────────────────────────────────────────────────────
# 1) FIX CRASH: EventDetailScreen key duplicada
# ─────────────────────────────────────────────────────────────
echo "📝 Fix crash en EventDetailScreen.kt..."

cp "$PKG_DIR/EventDetailScreen.kt" "$PKG_DIR/EventDetailScreen.kt.bak38"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(file_path) as f: content = f.read()

# Cambiar key para que use índice + url (evita colisiones)
old = '''                itemsIndexed(
                    items = evento.embeds,
                    key = { _, it -> it.url }
                ) { index, embed ->'''
new = '''                itemsIndexed(
                    items = evento.embeds,
                    key = { idx, it -> "emb_${idx}_${it.url}" }
                ) { index, embed ->'''

if old in content:
    content = content.replace(old, new)
    print("✅ EventDetailScreen: key único con índice")
else:
    print("⚠️  No encontré el patrón en EventDetailScreen")

with open(file_path, "w") as f: f.write(content)
PYEOF

# ─────────────────────────────────────────────────────────────
# 2) FIX CRASH: PlayerScreen panel lateral key duplicada
# ─────────────────────────────────────────────────────────────
echo "📝 Fix crash en PlayerScreen.kt..."

cp "$PKG_DIR/PlayerScreen.kt" "$PKG_DIR/PlayerScreen.kt.bak38"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f: content = f.read()

# Cambiar items(evento.embeds, ...) por itemsIndexed con key única
old = '''            items(evento.embeds, key = { "emb_" + it.url }) { emb ->
                val isFirst = evento.embeds.isNotEmpty() && emb.url == evento.embeds.first().url
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    onClick = { onCanalClick(emb) }
                )
            }'''
new = '''            itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" }) { idx, emb ->
                val isFirst = idx == 0
                PanelItem(
                    modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                    titulo = emb.nombre,
                    subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                    seleccionado = emb.url == embedActual.url,
                    onClick = { onCanalClick(emb) }
                )
            }'''

if old in content:
    content = content.replace(old, new)
    print("✅ PlayerScreen: key única con índice")
else:
    print("⚠️  No encontré el patrón en PlayerScreen")

# También arreglar 'otros eventos' que puede tener keys duplicados
old2 = '''                items(otros.take(30), key = { "ev_" + it.descripcion + it.fuente + it.hora }) { ev ->'''
new2 = '''                itemsIndexed(otros.take(30), key = { idx, it -> "ev_${idx}_${it.descripcion}_${it.fuente}_${it.hora}" }) { _, ev ->'''

if old2 in content:
    content = content.replace(old2, new2)
    print("✅ PlayerScreen: otros eventos con key única")

# Agregar import itemsIndexed si no está
if "import androidx.compose.foundation.lazy.itemsIndexed" not in content:
    content = content.replace(
        "import androidx.compose.foundation.lazy.items",
        "import androidx.compose.foundation.lazy.items\nimport androidx.compose.foundation.lazy.itemsIndexed"
    )
    print("✅ PlayerScreen: import itemsIndexed")

with open(file_path, "w") as f: f.write(content)
PYEOF

# ─────────────────────────────────────────────────────────────
# 3) Notif solo Firebase (quitar scraping)
# ─────────────────────────────────────────────────────────────
echo "📝 Notif solo Firebase en HomeScreen.kt..."

cp "$PKG_DIR/HomeScreen.kt" "$PKG_DIR/HomeScreen.kt.bak38"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f: content = f.read()

# Cambiar el reagendar para que solo use Firebase
old = 'try { EventNotifScheduler.reagendar(context, eventosFirebase + eventosScraping) } catch (_: Exception) {}'
new = 'try { EventNotifScheduler.reagendar(context, eventosFirebase) } catch (_: Exception) {}'

if old in content:
    content = content.replace(old, new)
    print("✅ Notif solo Firebase")
else:
    print("⚠️  No encontré el patrón de reagendar")

with open(file_path, "w") as f: f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q 'key = { idx, it -> "emb_${idx}_${it.url}" }' "$PKG_DIR/EventDetailScreen.kt" && echo "  ✓ EventDetailScreen con key única"
grep -q 'itemsIndexed(evento.embeds, key = { idx, it -> "emb_${idx}_${it.url}" })' "$PKG_DIR/PlayerScreen.kt" && echo "  ✓ PlayerScreen con key única"
grep -q 'EventNotifScheduler.reagendar(context, eventosFirebase)' "$PKG_DIR/HomeScreen.kt" && echo "  ✓ Notif solo Firebase"

echo ""
echo "✅✅✅ Paso 38 completo — Fix crash + Notif solo Firebase"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"