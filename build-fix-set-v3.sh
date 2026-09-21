#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME" "${HOME}.bak.fixsetv3.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Fix EXACTO de la línea 83
viejo = 'cal.set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)'
nuevo = 'cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)'

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ Línea 83 arreglada: 'set(Calendar.MINUTE, 0)' → 'cal.set(Calendar.MINUTE, 0)'")
else:
    print("⚠️ No encontré el patrón exacto. Buscando variantes...")
    import re
    # Variante con cualquier espacio
    patron = re.compile(r'cal\.set\(Calendar\.HOUR_OF_DAY,\s*0\);\s*set\(Calendar\.MINUTE,\s*0\)')
    c_nuevo, n = patron.subn('cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)', c)
    if n > 0:
        c = c_nuevo
        print(f"✅ Fix aplicado con regex ({n})")
    else:
        print("❌ No pude encontrar el patrón. Revisá manual.")
        raise SystemExit(1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

# Verificar
with open(fp, 'r', encoding='utf-8') as f:
    lineas = f.read().split('\n')
print("")
print("=== DESPUÉS (líneas 78-88) ===")
for i in range(77, min(89, len(lineas))):
    print(f"  {i+1}: {lineas[i]}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
