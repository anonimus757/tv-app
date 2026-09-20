#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-fix-fase2"

echo "📝 Arreglando orden de precargarSiguiente..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) QUITAR la función suspend del lugar donde está
patron_funcion = r'\n    /\*\*\n     \* 🆕 FASE 2: Precarga el siguiente canal.*?\n    \}\n\n'
content = re.sub(patron_funcion, '\n', content, flags=re.DOTALL)
print("✅ Función suspend removida")

# 2) AGREGAR un val lambda ANTES del LaunchedEffect(embedActual)
# El val lambda necesita ser suspend, así que usamos una corrutina adentro
val_lambda = '''    // 🆕 FASE 2: Lambda de precarga (declarada antes para poder usarla en LaunchedEffect)
    val precargarSiguiente: () -> Unit = {
        scope.launch(Dispatchers.IO) {
            try {
                val siguiente = evento.embeds.firstOrNull {
                    it.url != embedActual.url && CanalCache.get(it.url) == null
                }
                if (siguiente != null) {
                    addLog("🔒 Precargando ${siguiente.nombre}...")
                    val m3u8 = M3u8Extractor.extraer(siguiente.url, siguiente.referer) { /* silencioso */ }
                    if (m3u8 != null) {
                        CanalCache.put(siguiente.url, m3u8)
                        addLog("✅ ${siguiente.nombre} precargado")
                    }
                }
            } catch (_: Exception) {}
        }
    }

'''

# Insertar antes del LaunchedEffect(embedActual)
ancla = '''    LaunchedEffect(embedActual) {
        try { exoPlayer.stop(); exoPlayer.clearMediaItems() } catch (_: Exception) {}'''

if ancla in content and "val precargarSiguiente: () -> Unit" not in content:
    content = content.replace(ancla, val_lambda + ancla, 1)
    print("✅ Lambda precargarSiguiente agregada antes del LaunchedEffect")

# 3) Cambiar las llamadas "scope.launch(Dispatchers.IO) { precargarSiguiente() }"
# por simplemente "precargarSiguiente()"
content = content.replace(
    '''            scope.launch(Dispatchers.IO) {
                precargarSiguiente()
            }''',
    '            precargarSiguiente()'
)
content = content.replace(
    '''                scope.launch(Dispatchers.IO) {
                    precargarSiguiente()
                }''',
    '                precargarSiguiente()'
)

print("✅ Llamadas simplificadas")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "precargarSiguiente" "$FILE" | xargs -I {} echo "  Referencias a precargarSiguiente: {}"
grep -q "val precargarSiguiente: () -> Unit" "$FILE" && echo "  ✓ Lambda bien declarada"

echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"