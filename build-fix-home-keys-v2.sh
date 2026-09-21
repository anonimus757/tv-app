#!/bin/bash
set -e

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME_FILE" "${HOME_FILE}.bak.keysv2.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

cambios = 0

# ─── PASO 1: Insertar el estado "expandidos" después del remember(eventos) ───
ancla1 = "    val (enVivo, gruposPorDia) = remember(eventos) { agruparEventos(eventos) }"
if ancla1 in c:
    insercion = ancla1 + "\n    // Estado de expansión de cada grupo de fecha (hoisted, fuera del LazyColumn)\n    val expandidos = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateMapOf<String, Boolean>() }"
    c = c.replace(ancla1, insercion, 1)
    print("✅ Paso 1: estado 'expandidos' insertado")
    cambios += 1
else:
    print("⚠️ Paso 1: no encontré el ancla de enVivo/gruposPorDia")
    # Fallback: buscar cualquier línea con "remember(eventos) { agruparEventos"
    import re
    m = re.search(r'^(\s*val\s+\(enVivo,\s*gruposPorDia\)\s*=\s*remember\(eventos\)[^\n]*)$', c, re.MULTILINE)
    if m:
        linea = m.group(1)
        c = c.replace(linea, linea + "\n    val expandidos = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateMapOf<String, Boolean>() }", 1)
        print("✅ Paso 1 (fallback): insertado")
        cambios += 1
    else:
        print("❌ Paso 1: no pude insertar. Abortando.")
        raise SystemExit(1)

# ─── PASO 2: Reemplazar el bloque key(dia) { remember ... } por uso del map ───
viejo_bloque = '''            // Usamos key() para que cada grupo tenga su propio estado de expandido
            key(dia) {
                var expandido by remember { mutableStateOf(!colapsable) }

                item(key = "head_$dia") {
                    HeaderFechaColapsable(
                        titulo = icono,
                        total = lista.size,
                        color = color,
                        colapsable = colapsable,
                        expandido = expandido,
                        onToggle = { expandido = !expandido }
                    )
                }

                if (expandido) {
                    item(key = "row_$dia") {
                        FilaEventos(lista, onEventoClick, esTV, esVertical)
                    }
                }

                item(key = "sp_$dia") { Spacer(Modifier.height(20.dp)) }
            }'''

nuevo_bloque = '''            val expandido = expandidos.getOrPut(dia) { !colapsable }

            item(key = "head_$dia") {
                HeaderFechaColapsable(
                    titulo = icono,
                    total = lista.size,
                    color = color,
                    colapsable = colapsable,
                    expandido = expandido,
                    onToggle = { expandidos[dia] = !expandido }
                )
            }

            if (expandido) {
                item(key = "row_$dia") {
                    FilaEventos(lista, onEventoClick, esTV, esVertical)
                }
            }

            item(key = "sp_$dia") { Spacer(Modifier.height(20.dp)) }'''

if viejo_bloque in c:
    c = c.replace(viejo_bloque, nuevo_bloque, 1)
    print("✅ Paso 2: bloque key(dia) reemplazado")
    cambios += 1
else:
    print("⚠️ Paso 2: no matcheó el bloque exacto, probando variantes...")
    # Probar sin el comentario
    viejo_bloque2 = '''            key(dia) {
                var expandido by remember { mutableStateOf(!colapsable) }

                item(key = "head_$dia") {
                    HeaderFechaColapsable(
                        titulo = icono,
                        total = lista.size,
                        color = color,
                        colapsable = colapsable,
                        expandido = expandido,
                        onToggle = { expandido = !expandido }
                    )
                }

                if (expandido) {
                    item(key = "row_$dia") {
                        FilaEventos(lista, onEventoClick, esTV, esVertical)
                    }
                }

                item(key = "sp_$dia") { Spacer(Modifier.height(20.dp)) }
            }'''
    if viejo_bloque2 in c:
        c = c.replace(viejo_bloque2, nuevo_bloque.replace("            // Usamos key() para que cada grupo tenga su propio estado de expandido\n", ""), 1)
        print("✅ Paso 2 (variante): bloque reemplazado")
        cambios += 1
    else:
        print("❌ Paso 2: no pude matchear. Revisá el archivo manualmente.")
        print("   Contenido de la zona (buscando 'key(dia)')...")
        idx = c.find("key(dia)")
        if idx >= 0:
            print(c[max(0, idx-200):idx+800])
        raise SystemExit(1)

# ─── PASO 3: Asegurar import de mutableStateMapOf (opcional, uso FQN) ───
# Como uso el nombre completo (androidx.compose.runtime.mutableStateMapOf), no hace falta import.
print("ℹ️ Paso 3: uso nombre completo (FQN), no requiere import extra")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print(f"✅ Total cambios aplicados: {cambios}")
print("✅ HomeScreen.kt reescrito correctamente")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

if 'key(dia)' in final:
    print("⚠️ ADVERTENCIA: todavía hay 'key(dia)'")
if 'expandidos.getOrPut' in final:
    print("✅ Verificación: 'expandidos.getOrPut' presente")
else:
    print("⚠️ ADVERTENCIA: no aparece 'expandidos.getOrPut'")
if 'mutableStateMapOf' in final:
    print("✅ Verificación: 'mutableStateMapOf' presente")
PYEOF

echo ""
echo "✅✅✅ Fix keys v2 completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
