#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
[ ! -f "$API" ] && { echo "❌ No existe $API"; exit 1; }
cp "$API" "${API}.bak.escapev3.$(date +%s)"
echo "✅ Backup: ${API}.bak.escapev3.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

print("=== ANTES (líneas 210-220) ===")
lineas = c.split('\n')
for i in range(209, min(221, len(lineas))):
    print(f"  {i+1}: {lineas[i]}")

# El problema: Kotlin necesita \\s (doble backslash) en el source
# Pero el archivo tiene \s (un solo backslash)
# En Python, para escribir el string literal "\\s" en el archivo, uso raw string

# Leer como bytes y hacer replace seguro
import codecs

# Estrategia: reemplazar la secuencia de 1 backslash + s por 2 backslashes + s
# SOLO dentro de Regex("...")

# Enfoque más robusto: buscar líneas con Regex(" ... \s ... ") y arreglar
import re

def arreglar_linea(linea):
    if 'Regex(' not in linea:
        return linea
    # Reemplazar \s por \\s (SIN tocar \\s que ya esté bien)
    # Usamos regex negativa: no precedido por \
    resultado = re.sub(r'(?<!\\)\\s', r'\\\\s', linea)
    return resultado

lineas = c.split('\n')
lineas_arregladas = [arreglar_linea(l) for l in lineas]
c = '\n'.join(lineas_arregladas)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("=== DESPUÉS ===")
with open(fp, 'r', encoding='utf-8') as f:
    nuevas_lineas = f.read().split('\n')
for i in range(209, min(221, len(nuevas_lineas))):
    print(f"  {i+1}: {nuevas_lineas[i]}")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()
malos = final.count('Regex("[^a-z0-9\\s]")') + final.count('Regex("\\s+")')
print("")
if malos > 0:
    print(f"⚠️ Todavía hay {malos} Regex sin escapar bien")
else:
    print("✅ Todos los Regex están correctamente escapados")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean && ./gradlew assembleDebug --no-daemon --max-workers=1"
