#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.quitardiagv2.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

original_len = len(c)
print(f"📄 Original: {original_len} bytes")

# ─── Buscar inicio del bloque (comentario del DIAG) ───
ancla_inicio = '        // ═══════════════════════════════════════════════════════\n        // 🐛 LOG DE DIAGNÓSTICO'
idx_inicio = c.find(ancla_inicio)

if idx_inicio < 0:
    print("❌ No encontré el inicio del bloque DIAG")
    raise SystemExit(1)

print(f"✅ Inicio del bloque en posición {idx_inicio}")

# ─── Buscar fin del bloque (antes de "if (usarWebView") ───
ancla_fin = '        if (usarWebView && m3u8Url == null) {'
idx_fin = c.find(ancla_fin, idx_inicio)

if idx_fin < 0:
    print("❌ No encontré el final del bloque (usarWebView)")
    raise SystemExit(1)

print(f"✅ Fin del bloque en posición {idx_fin}")

# ─── Mostrar qué se va a eliminar ───
bloque = c[idx_inicio:idx_fin]
print(f"📏 Bloque a eliminar: {len(bloque)} bytes")
print(f"   Primeras 3 líneas: {bloque.split(chr(10))[:3]}")

# ─── Verificación: asegurar que NO contiene usarWebView ───
if 'if (usarWebView' in bloque:
    print("❌ ABORTADO: el bloque contiene usarWebView")
    raise SystemExit(1)

if 'AndroidView' in bloque and 'WebView' in bloque:
    print("❌ ABORTADO: el bloque contiene el WebView")
    raise SystemExit(1)

# ─── Eliminar bloque ───
c = c[:idx_inicio] + c[idx_fin:]

# ─── También eliminar las variables que ya no se usan ───
# Línea 261-262: logsDiagnostico y mostrarLogDiag
c = c.replace('    var logsDiagnostico by remember { mutableStateOf(listOf<String>()) }\n', '')
c = c.replace('    var mostrarLogDiag by remember { mutableStateOf(false) }\n', '')

# ─── Eliminar el logDiag lambda (líneas 269-272) ───
import re
patron_lambda = re.compile(
    r'\s*//\s*🆕\s*LOG DE DIAGNÓSTICO \(visible en el reproductor\)\s*\n\s*val\s+logDiag:\s*\(String\)\s*->\s*Unit\s*=\s*\{[^}]*\}\s*\n',
    re.DOTALL
)
c, n_lambda = patron_lambda.subn('\n', c)
if n_lambda > 0:
    print(f"✅ Lambda logDiag eliminado")

# ─── Eliminar TODAS las llamadas a logDiag(...) ───
patron_logdiag = re.compile(r'^\s*logDiag\([^\n]*\)\s*\n', re.MULTILINE)
c, n_logs = patron_logdiag.subn('', c)
print(f"✅ {n_logs} llamadas a logDiag eliminadas")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print(f"📄 Resultado: {len(c)} bytes ({original_len - len(c)} eliminados)")

# ─── Verificación final ───
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

checks = {
    "🐛 DIAG": '🐛 DIAG' in final,
    "mostrarLogDiag": 'mostrarLogDiag' in final,
    "logDiag(": 'logDiag(' in final,
    "logsDiagnostico": 'logsDiagnostico' in final,
    "if (usarWebView": 'if (usarWebView' in final,
    "m3u8Url": 'm3u8Url' in final,
    "cookies": 'cookies' in final,
    "embedActual": 'embedActual' in final,
}
print("")
print("=== Verificación ===")
for k, v in checks.items():
    estado = '✅' if (v and k.startswith('if') or v and k in ('m3u8Url','cookies','embedActual')) else ('❌' if v else '✅')
    # Lógica simple: lo que queremos que NO esté (🐛, mostrarLogDiag, logDiag, logsDiagnostico) debe ser False
    # Lo que queremos que SÍ esté (usarWebView, m3u8Url, cookies, embedActual) debe ser True
    if k in ('🐛 DIAG', 'mostrarLogDiag', 'logDiag(', 'logsDiagnostico'):
        print(f"  {'✅' if not v else '❌'} '{k}' eliminado")
    else:
        print(f"  {'✅' if v else '❌'} '{k}' presente")
PYEOF

echo ""
echo "Verificá:"
grep -c "🐛\|mostrarLogDiag\|logDiag(" "$PLAYER" || echo "  ✅ 0 referencias"

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
