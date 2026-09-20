#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE_HOME="$UI_DIR/HomeScreen.kt"
FILE_PLAYER="$UI_DIR/PlayerScreen.kt"

cp "$FILE_HOME" "$FILE_HOME.bak-final"
cp "$FILE_PLAYER" "$FILE_PLAYER.bak-final"

echo "📝 Fix 1 — Ocultar Hero en celu/tablet (solo TV)..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

old_hero = '''        destacado?.let { ev ->
                item(key = "hero") {
                    HeroCine(ev, esHoy = esHoy) {
                        onEventoClick(ev, fbDelDia.ifEmpty { scDelDia })
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }'''

new_hero = '''        // 🆕 Hero SOLO en TV. En celu/tablet se oculta.
        val esTV = rememberEsTV()
        if (esTV) {
            destacado?.let { ev ->
                item(key = "hero") {
                    HeroCine(ev, esHoy = esHoy) {
                        onEventoClick(ev, fbDelDia.ifEmpty { scDelDia })
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }
        }'''

if old_hero in content:
    content = content.replace(old_hero, new_hero, 1)
    print("✅ Hero oculto en celu/tablet")
else:
    print("⚠️  No encontré el bloque del Hero, buscando variante...")
    import re
    pattern = r'destacado\?\.let \{ ev ->\s*item\(key = "hero"\) \{.*?\n\s*\}\n\s*\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_hero + content[match.end():]
        print("✅ Hero oculto (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 2 — Soporte para .ts directo y streamxhd.com..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 2a) Agregar streamxhd.com a la lista de páginas dinámicas
# ═══════════════════════════════════════════════════════════
old_esPag = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // SOLO sitios que realmente no se pueden extraer (usan MSE/Blob)
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com")
}'''

new_esPag = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // Sitios que usan JavaScript para cargar el m3u8
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com") ||
           low.contains("streamxhd.st") ||
           low.contains("stream-xhd") ||
           low.contains("streamx-hd")
}'''

if old_esPag in content:
    content = content.replace(old_esPag, new_esPag)
    print("✅ streamxhd.com agregado a páginas dinámicas")
else:
    print("⚠️  No encontré esPaginaDinamica exacta, intentando regex...")
    pattern = r'private fun esPaginaDinamica\(url: String\): Boolean \{[^}]*\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_esPag + content[match.end():]
        print("✅ esPaginaDinamica actualizada (regex)")

# ═══════════════════════════════════════════════════════════
# 2b) Detectar .ts y crear ProgressiveMediaSource
# ═══════════════════════════════════════════════════════════
old_media = '''            val src = HlsMediaSource.Factory(ds)
                .setAllowChunklessPreparation(false)
                .setUseSessionKeys(false)
                .createMediaSource(MediaItem.fromUri(Uri.parse(url)))'''

new_media = '''            // 🆕 Detectar si es un archivo .ts directo
            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

            val src = if (esTS) {
                // Es un MPEG-TS directo → usar ProgressiveMediaSource
                androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(ds)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            } else {
                // Es un HLS (.m3u8) → usar HlsMediaSource como siempre
                HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            }'''

# Buscar el bloque de HlsMediaSource en LaunchedEffect(m3u8Url, reloadTrigger)
count = content.count(old_media)
if count > 0:
    content = content.replace(old_media, new_media)
    print(f"✅ Soporte .ts agregado ({count} lugares)")

# También en el auto-cambio de candidato
old_media2 = '''                val src = HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(nuevaUrl)))'''

new_media2 = '''                val esTS = nuevaUrl.substringBefore("?").endsWith(".ts", ignoreCase = true)

                val src = if (esTS) {
                    androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(ds)
                        .createMediaSource(MediaItem.fromUri(Uri.parse(nuevaUrl)))
                } else {
                    HlsMediaSource.Factory(ds)
                        .setAllowChunklessPreparation(false)
                        .setUseSessionKeys(false)
                        .createMediaSource(MediaItem.fromUri(Uri.parse(nuevaUrl)))
                }'''

if old_media2 in content:
    content = content.replace(old_media2, new_media2)
    print("✅ Soporte .ts en auto-cambio de candidato")

# Import de ProgressiveMediaSource
if "import androidx.media3.exoplayer.source.ProgressiveMediaSource" not in content:
    content = content.replace(
        "import androidx.media3.exoplayer.source.HlsMediaSource",
        "import androidx.media3.exoplayer.source.HlsMediaSource\nimport androidx.media3.exoplayer.source.ProgressiveMediaSource"
    )
    # Si no está el import de HlsMediaSource, agregarlo después de otro
    if "import androidx.media3.exoplayer.source.ProgressiveMediaSource" not in content:
        content = content.replace(
            "import androidx.media3.exoplayer.hls.HlsMediaSource",
            "import androidx.media3.exoplayer.hls.HlsMediaSource\nimport androidx.media3.exoplayer.source.ProgressiveMediaSource"
        )
    print("✅ Import ProgressiveMediaSource")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "val esTV = rememberEsTV()" "$FILE_HOME" && echo "  ✓ Home detecta TV para hero"
grep -q "streamxhd.com" "$FILE_PLAYER" && echo "  ✓ streamxhd.com en páginas dinámicas"
grep -q "ProgressiveMediaSource" "$FILE_PLAYER" && echo "  ✓ Soporte .ts directo"

echo ""
echo "✅✅✅ Fix final aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   📱 Hero: se oculta en celu/tablet, se muestra solo en TV"
echo "   🎬 Reproductor: soporta .ts directo (LionTV)"
echo "   🎬 Reproductor: streamxhd.com va directo al WebView"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"