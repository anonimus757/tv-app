#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"

cp "$FILE" "$FILE.bak-esTV"

echo "📝 Moviendo esTV fuera del LazyColumn..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Sacar la declaración de esTV de donde está (dentro del LazyColumn)
old_inside = '''        // 🆕 Hero SOLO en TV. En celu/tablet se oculta.
        val esTV = rememberEsTV()
        if (esTV) {
            destacado?.let { ev ->
                item(key = "hero") {
                    HeroCine(ev, esHoy = esHoy) {
                        onEventoClick(ev, fbDelDia.ifEmpty { scDelDia })
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }
        }'''

new_inside = '''        // 🆕 Hero SOLO en TV. En celu/tablet se oculta.
        if (mostrarHero) {
            destacado?.let { ev ->
                item(key = "hero") {
                    HeroCine(ev, esHoy = esHoy) {
                        onEventoClick(ev, fbDelDia.ifEmpty { scDelDia })
                    }
                    Spacer(Modifier.height(28.dp))
                }
            }
        }'''

if old_inside in content:
    content = content.replace(old_inside, new_inside, 1)
    print("✅ Referencia del Hero cambiada a 'mostrarHero'")

# 2) Declarar 'mostrarHero' ARRIBA del LazyColumn
# Buscar la línea donde empieza el LazyColumn de contenido
# o donde se declara el 'destacado' etc.
old_ancla = '''    val destacado = fbEnVivo.firstOrNull() ?: fbDelDia.firstOrNull() ?: scDelDia.firstOrNull()'''

new_ancla = '''    val destacado = fbEnVivo.firstOrNull() ?: fbDelDia.firstOrNull() ?: scDelDia.firstOrNull()
    // 🆕 Hero solo se muestra en TV
    val esTV = rememberEsTV()
    val mostrarHero = esTV'''

if old_ancla in content:
    content = content.replace(old_ancla, new_ancla, 1)
    print("✅ 'esTV' y 'mostrarHero' declarados antes del LazyColumn")
else:
    # Buscar variante: quizás la variable destacado está en otro lado
    import re
    pattern = r'(val destacado = [^\n]+)'
    match = re.search(pattern, content)
    if match:
        content = content[:match.end()] + '\n    val esTV = rememberEsTV()\n    val mostrarHero = esTV' + content[match.end():]
        print("✅ Declarado (regex)")
    else:
        print("❌ No pude ubicar 'destacado'")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -n "val mostrarHero" "$FILE"
grep -n "if (mostrarHero)" "$FILE"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"