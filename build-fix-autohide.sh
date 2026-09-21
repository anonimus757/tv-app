#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.autohide.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── Buscar el LaunchedEffect actual ───
viejo = '''    LaunchedEffect(mostrarControles, panelAbierto, refrescando, zona, avisoCambio, toast) {
        if (mostrarControles && !panelAbierto && !refrescando && zona == ZonaUI.VIDEO && avisoCambio == null && toast == null) {
            delay(4500)
            mostrarControles = false
        }
    }'''

nuevo = '''    LaunchedEffect(mostrarControles, panelAbierto, refrescando, avisoCambio, toast, zona, idxBottom) {
        // Auto-hide de los controles. Se oculta SIEMPRE después de 5s
        // si no hay panel abierto, no está refrescando, no hay aviso/toast.
        // La clave: NO chequea `zona` — funciona sin importar dónde esté el foco.
        if (mostrarControles && !panelAbierto && !refrescando && avisoCambio == null && toast == null) {
            delay(5000)
            mostrarControles = false
            zona = ZonaUI.VIDEO
        }
    }'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ Auto-hide corregido (se oculta siempre tras 5s)")
else:
    print("⚠️ No matcheó el LaunchedEffect. Buscando variantes...")
    import re
    # Buscar cualquier LaunchedEffect que tenga mostrarControles y delay
    patron = re.compile(
        r'LaunchedEffect\(mostrarControles[^)]*\)\s*\{[^}]*delay\(\d+\)[^}]*mostrarControles\s*=\s*false[^}]*\}',
        re.DOTALL
    )
    m = patron.search(c)
    if m:
        c = c[:m.start()] + nuevo.strip() + c[m.end():]
        print("✅ Variante aplicada")
    else:
        print("❌ No pude encontrar el LaunchedEffect")
        raise SystemExit(1)

# ─── También arreglar: cada vez que el user toca una tecla, mostrar controles ───
# Buscar el onKeyEvent y agregar mostrarControles = true al inicio
viejo_key = '''            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                if (panelAbierto) return@onKeyEvent false
'''

nuevo_key = '''            .onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                if (panelAbierto) return@onKeyEvent false
                // Cualquier tecla resetea el timer de auto-hide
                if (mostrarControles) {
                    // ya está visible, el LaunchedEffect lo va a resetear
                } else {
                    mostrarControles = true
                }
'''

if viejo_key in c:
    c = c.replace(viejo_key, nuevo_key, 1)
    print("✅ onKeyEvent actualizado para mostrar controles al presionar teclas")
else:
    print("⚠️ No matcheó el onKeyEvent")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ PlayerScreen.kt actualizado")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
