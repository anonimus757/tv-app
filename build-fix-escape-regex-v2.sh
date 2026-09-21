#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.escapev2.$(date +%s)"
echo "✅ Backup: ${API}.bak.escapev2.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

print("=== ANTES (líneas con problemas) ===")
for i, line in enumerate(c.split('\n'), 1):
    if 'Regex("' in line and '\\s' in line and '\\\\s' not in line:
        print(f"  {i}: {line}")

# Fix: convertir \s en \\s SOLO en strings de Kotlin (doble backslash para regex)
# Buscamos Regex("...[^a-z0-9\s]...") y Regex("\s+")
c = c.replace('Regex("[^a-z0-9\\s]")', 'Regex("[^a-z0-9\\\\s]")')
c = c.replace('Regex("\\s+")', 'Regex("\\\\s+")')

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("=== DESPUÉS ===")
with open(fp, 'r', encoding='utf-8') as f:
    nuevo = f.read()
for i, line in enumerate(nuevo.split('\n'), 1):
    if 'Regex("' in line:
        print(f"  {i}: {line}")
PYEOF

echo ""
echo "✅✅✅ Escapes corregidos v2"
echo ""
echo "Verificá manualmente:"
echo "  grep -n 'Regex(' app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
