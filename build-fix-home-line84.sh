#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
[ ! -f "$HOME" ] && { echo "❌ No existe $HOME"; exit 1; }
cp "$HOME" "${HOME}.bak.line84.$(date +%s)"
echo "✅ Backup: ${HOME}.bak.line84.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Fix: la línea con "cal.set(...); set(...)" debe ser "cal.set(...); cal.set(...)"
viejo = 'cal.set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)'
nuevo = 'cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)'

if viejo in c:
    c = c.replace(viejo, nuevo)
    print("✅ Fix aplicado: 'set(Calendar.MINUTE, 0)' → 'cal.set(Calendar.MINUTE, 0)'")
else:
    print("⚠️ No encontré el patrón exacto. Buscando variantes...")
    # Variante por si hay espacios distintos
    import re
    c2 = re.sub(r'cal\.set\(Calendar\.HOUR_OF_DAY, 0\);\s+set\(Calendar\.MINUTE, 0\)',
                'cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)', c)
    if c2 != c:
        c = c2
        print("✅ Fix aplicado con regex")
    else:
        print("❌ No pude matchear. Revisá la línea 84 a mano.")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ HomeScreen.kt guardado")
PYEOF

echo ""
echo "Verificá la línea 84:"
sed -n '80,90p' app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
