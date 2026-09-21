#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.quitardiag.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

original_len = len(c)
print(f"📄 Archivo: {original_len} bytes")

# ═══════════════════════════════════════════════════════════
# 1. Eliminar el BLOQUE del botón 🐛 DIAG
# ═══════════════════════════════════════════════════════════
patron_boton = re.compile(
    r'\s*//\s*═+\s*\n\s*//\s*🐛 LOG DE DIAGNÓSTICO.*?\n\s*//\s*═+\s*\n\s*Box\(\s*\n\s*Modifier\s*\n\s*\.align\(Alignment\.TopEnd\).*?\n\s*\}\s*\n\s*\}\s*\n',
    re.DOTALL
)
c_nuevo, n1 = patron_boton.subn('\n', c)
if n1 > 0:
    c = c_nuevo
    print(f"✅ Bloque del botón 🐛 eliminado ({n1})")
else:
    print("⚠️ No matcheó el bloque del botón. Probando por texto simple...")
    # Fallback: buscar desde "// 🐛 LOG DE DIAGNÓSTICO" hasta el cierre del Box
    ancla = '// 🐛 LOG DE DIAGNÓSTICO'
    idx = c.find(ancla)
    if idx >= 0:
        # Retroceder al inicio del comentario del bloque ═
        inicio_bloque = c.rfind('// ═', 0, idx)
        if inicio_bloque < 0:
            inicio_bloque = idx - 100
        # Buscar el siguiente "// ════" para saber dónde termina el bloque
        # o el siguiente "@Composable" o "if (usarWebView"
        siguiente = c.find('if (usarWebView', idx)
        if siguiente < 0:
            siguiente = c.find('@Composable', idx)
        if siguiente < 0:
            siguiente = len(c)
        # Cortar desde inicio_bloque hasta siguiente
        c = c[:inicio_bloque] + c[siguiente:]
        print(f"✅ Bloque del botón eliminado por fallback")
    else:
        print("❌ No encontré el bloque del botón")

# ═══════════════════════════════════════════════════════════
# 2. Eliminar el BLOQUE del panel de logs (if mostrarLogDiag)
# ═══════════════════════════════════════════════════════════
patron_panel = re.compile(
    r'\s*if\s*\(mostrarLogDiag\)\s*\{\s*\n\s*Box\(\s*\n\s*Modifier\s*\n\s*\.align\(Alignment\.Center\)\s*\n\s*\.fillMaxSize\(0\.85f\).*?\n\s*\}\s*\n\s*\}\s*\n',
    re.DOTALL
)
c_nuevo, n2 = patron_panel.subn('\n', c)
if n2 > 0:
    c = c_nuevo
    print(f"✅ Bloque del panel de logs eliminado ({n2})")
else:
    print("⚠️ No matcheó el panel por regex. Probando por ancla...")
    ancla = 'if (mostrarLogDiag) {'
    idx = c.find(ancla)
    if idx >= 0:
        # Encontrar el cierre del if balanceando llaves
        i = idx + len(ancla)
        profundidad = 1
        while i < len(c) and profundidad > 0:
            if c[i] == '{': profundidad += 1
            elif c[i] == '}': profundidad -= 1
            i += 1
        c = c[:idx] + c[i:]
        print(f"✅ Panel de logs eliminado por ancla")
    else:
        print("❌ No encontré el panel de logs")

# ═══════════════════════════════════════════════════════════
# 3. Eliminar variables/estados asociados (no rompe nada)
# ═══════════════════════════════════════════════════════════
# logsDiagnostico y mostrarLogDiag ya no se usan pero dejarlos no rompe.
# Mejor los dejamos por si acaso (evita errores de "unused" o algo).

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print(f"📄 Resultado: {len(c)} bytes ({original_len - len(c)} eliminados)")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

if '🐛 DIAG' in final:
    print("⚠️ Todavía queda referencia a 🐛 DIAG")
else:
    print("✅ Ya no hay referencias al botón 🐛 DIAG")
PYEOF

echo ""
echo "Verificá:"
grep -n "🐛 DIAG\|mostrarLogDiag" "$PLAYER" | head -10

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
