#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.escape.$(date +%s)"
echo "✅ Backup: ${API}.bak.escape.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Mostrar las líneas problemáticas antes
print("=== ANTES ===")
for i, line in enumerate(c.split('\n'), 1):
    if '\\s' in line or 'Regex(' in line:
        print(f"  {i}: {line}")

# Reemplazos literales: de "\s" a "\\s" en los Regex de Kotlin
# En Kotlin: Regex("\\s") representa la regex \s
# Necesitamos que en el archivo quede: Regex("\\s")
c = c.replace('Regex("[^a-z0-9\\s]")', 'Regex("[^a-z0-9\\\\s]")')
c = c.replace('Regex("\\s+")', 'Regex("\\\\s+")')

# También por si quedaron otros casos
c = c.replace('.replace(Regex("\\\\s+"'), '.replace(Regex("\\\\s+"')

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("=== DESPUÉS ===")
with open(fp, 'r', encoding='utf-8') as f:
    nuevo = f.read()
for i, line in enumerate(nuevo.split('\n'), 1):
    if 'Regex(' in line or ('\\\\s' in line and 'replace' in line):
        print(f"  {i}: {line}")
PYEOF

echo ""
echo "✅✅✅ Escapes corregidos"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
