#!/bin/bash
set -e

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME_FILE" "${HOME_FILE}.bak.keys.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── FIX 1: Mover el estado de "expandido" FUERA del LazyColumn ───
# Crear un estado map ANTES del LazyColumn en ContenidoMisEventos

# Buscar el inicio de ContenidoMisEventos
m = re.search(
    r'(@Composable\s+private\s+fun\s+ContenidoMisEventos\s*\([^)]*\)\s*\{)',
    c, re.DOTALL
)
if not m:
    print("❌ No encontré ContenidoMisEventos")
    raise SystemExit(1)

# Insertar el estado expandidos DESPUÉS de "val (enVivo, gruposPorDia) = ..."
patron_enVivo = r'(val\s+\(enVivo,\s*gruposPorDia\)\s*=\s*remember\(eventos\)\s*\{\s*agruparEventos\(eventos\)\s*\}\s*\n)(\s*)(val\s+destacado\s*=)'

# En su lugar, insertar estado map + recordar los días colapsables
def reemplazo_enVivo(match):
    antes = match.group(1)
    indent = match.group(2)
    destacado = match.group(3)
    insercion = f'''{antes}
{indent}// Estado de expansión de cada grupo de fecha (fuera del LazyColumn, es un composable scope)
{indent}val expandidos = remember {{ mutableStateMapOf<String, Boolean>() }}
{indent}val gruposPorDiaKey = gruposPorDia.map {{ it.first }}

{indent}{destacado}'''
    return insercion

c2, n = re.subn(patron_enVivo, reemplazo_enVivo, c)
if n == 0:
    print("⚠️ No matcheó el patrón de enVivo/destacado, intentando alternativa...")
    # Alternativa: solo insertar después de la línea de remember(eventos)
    c2, n = re.subn(
        r'(val\s+\(enVivo,\s*gruposPorDia\)\s*=\s*remember\(eventos\)\s*\{\s*agruparEventos\(eventos\)\s*\}\s*\n)',
        r'\1    val expandidos = remember { mutableStateMapOf<String, Boolean>() }\n',
        c
    )
    if n == 0:
        print("❌ No pude insertar el estado expandidos")
        raise SystemExit(1)
    print(f"✅ Inserción alternativa OK ({n})")
else:
    print(f"✅ Estado expandidos insertado ({n})")

c = c2

# ─── FIX 2: Reemplazar el bloque key(dia) { remember(dia) ... } por uso del map ───

# Buscar el bloque desde "val colapsable = dia in listOf(...)" hasta el cierre del forEach
patron_bloque = r'''(\s*val\s+colapsable\s*=\s*dia\s+in\s+listOf\([^)]*\)\s*\n)(\s*)// Usamos key\(dia\).*?\n\s*key\(dia\)\s*\{.*?\n(\s*)\}'''

nuevo_bloque = '''\\1
\\2// Leer/escribir expandido desde el map (state hoisted)
\\2val expandido = expandidos.getOrPut(dia) { !colapsable }

\\2item(key = "head_$dia") {
\\2    HeaderFechaColapsable(
\\2        titulo = icono,
\\2        total = lista.size,
\\2        color = color,
\\2        colapsable = colapsable,
\\2        expandido = expandido,
\\2        onToggle = { expandidos[dia] = !expandido }
\\2    )
\\2}

\\2if (expandido) {
\\2    item(key = "row_$dia") {
\\2        FilaEventos(lista, onEventoClick, esTV, esVertical)
\\2    }
\\2}

\\2item(key = "sp_$dia") { Spacer(Modifier.height(20.dp)) }'''

c3, n2 = re.subn(patron_bloque, nuevo_bloque, c, flags=re.DOTALL)

if n2 == 0:
    print("⚠️ No matcheó el bloque key(dia)...")
    print("   Buscando fragmentos...")
    # Buscar y reemplazar solo la línea de key(dia) y la línea de remember(dia)
    c3 = re.sub(
        r'// Usamos key\(dia\).*?\n\s*key\(dia\)\s*\{',
        'val expandido = expandidos.getOrPut(dia) { !colapsable }',
        c, flags=re.DOTALL
    )
    # Quitar el remember(dia)
    c3 = c3.replace(
        'var expandido by remember { mutableStateOf(!colapsable) }',
        ''
    )
    print("✅ Fix alternativo aplicado")
else:
    print(f"✅ Bloque del forEach reemplazado ({n2})")

c = c3

# ─── FIX 3: Remover el "}" extra que quedó del key(dia) si quedó ───
# Contar llaves del bloque ContenidoMisEventos
# Esto es frágil, mejor buscar el patrón exacto que dejó el script anterior

# Buscar "}" solitario al final del bloque de gruposPorDia (antes del item "footer")
patron_extra = r'(\s*item\(key = "sp_\$dia"\)\s*\{\s*Spacer\(Modifier\.height\(20\.dp\)\)\s*\}\s*\n)(\s*\}\s*\n)(\s*item\(key = "footer"\))'
c = re.sub(patron_extra, r'\1\3', c)

# ─── FIX 4: Asegurar import de mutableStateMapOf ───
if 'mutableStateMapOf' not in c.split('@Composable')[0] and 'import androidx.compose.runtime.mutableStateMapOf' not in c:
    if 'import androidx.compose.runtime.*' not in c:
        c = c.replace(
            'import androidx.compose.runtime.remember',
            'import androidx.compose.runtime.remember\nimport androidx.compose.runtime.mutableStateMapOf'
        )

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("✅ HomeScreen.kt reescrito con estado hoisted")

# Verificación rápida
with open(fp, 'r', encoding='utf-8') as f:
    contenido = f.read()

if 'expandidos.getOrPut' not in contenido:
    print("⚠️ ADVERTENCIA: 'expandidos.getOrPut' no aparece. El fix puede no haberse aplicado bien.")
if 'key(dia)' in contenido:
    print("⚠️ ADVERTENCIA: todavía hay 'key(dia)' sin resolver.")

PYEOF

echo ""
echo "✅✅✅ Fix keys completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
