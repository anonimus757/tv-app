#!/bin/bash
set -e

DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.canaleslive.$(date +%s)"
echo "✅ Backup: ${DETAIL}.bak.canaleslive.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Buscar el bloque que muestra canales y envolverlo en if (estado == EN_VIVO)
viejo = '''            // Canales
            item(key = "head_canales") {
                RowCanales(evento, esTV, esMovil)
            }
            itemsIndexed(
                items = evento.embeds,
                key = { idx, it -> "emb_${idx}_${it.url}" }
            ) { index, embed ->
                Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                    CanalCard(embed, esTV, esMovil) { onCanalClick(embed) }
                }
            }'''

nuevo = '''            // Canales SOLO si el evento está EN VIVO
            if (estado == EstadoEvento.EN_VIVO) {
                item(key = "head_canales") {
                    RowCanales(evento, esTV, esMovil)
                }
                itemsIndexed(
                    items = evento.embeds,
                    key = { idx, it -> "emb_${idx}_${it.url}" }
                ) { index, embed ->
                    Box(Modifier.fadeInOnLoad(400, delayMs = 100 + index * 50)) {
                        CanalCard(embed, esTV, esMovil) { onCanalClick(embed) }
                    }
                }
            }'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ Canales envueltos en if (estado == EN_VIVO)")
else:
    print("❌ No matcheó el bloque exacto. Probando variantes...")
    # Variante por si hay diferencia de espacios
    import re
    patron = re.compile(
        r'(\s*// Canales\s*\n\s*item\(key = "head_canales"\)\s*\{.*?\n\s*\}\s*\n\s*itemsIndexed\(.*?\n\s*\}\s*\n\s*\}\s*\n)',
        re.DOTALL
    )
    m = patron.search(c)
    if m:
        bloque = m.group(1)
        # Indentar el bloque con 4 espacios extra y envolverlo
        lineas = bloque.split('\n')
        bloque_indentado = '\n'.join(('    ' + l if l.strip() else l) for l in lineas)
        nuevo_bloque = '\n            // Canales SOLO si el evento está EN VIVO\n            if (estado == EstadoEvento.EN_VIVO) {' + bloque_indentado + '            }\n'
        c = c.replace(bloque, nuevo_bloque, 1)
        with open(fp, 'w', encoding='utf-8') as f:
            f.write(c)
        print("✅ Variante aplicada")
    else:
        print("❌ No pude matchear. Revisá manual.")
        raise SystemExit(1)
PYEOF

echo ""
echo "Verificá:"
grep -n "if (estado == EstadoEvento.EN_VIVO)" "$DETAIL"

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
