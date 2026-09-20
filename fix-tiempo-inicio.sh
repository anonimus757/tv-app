#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-tiempo"

echo "📝 Agregando variable tiempoInicioStream..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Verificar si ya existe
if "var tiempoInicioStream" in content:
    print("ℹ️  Ya existe, no hago nada")
    exit(0)

# 2) Agregar la variable junto a los otros estados
# Buscar un ancla segura
ancla = "    var reintentos by remember { mutableIntStateOf(0) }"
if ancla in content:
    content = content.replace(
        ancla,
        ancla + "\n    var tiempoInicioStream by remember { mutableLongStateOf(0L) }",
        1
    )
    print("✅ Variable agregada (junto a reintentos)")
else:
    # Ancla alternativa
    ancla2 = "    var mostrarControles by remember { mutableStateOf(true) }"
    if ancla2 in content:
        content = content.replace(
            ancla2,
            ancla2 + "\n    var tiempoInicioStream by remember { mutableLongStateOf(0L) }",
            1
        )
        print("✅ Variable agregada (junto a mostrarControles)")
    else:
        print("❌ No encontré ancla para insertar")

# 3) Verificar que tenga el import de mutableLongStateOf
if "import androidx.compose.runtime.mutableLongStateOf" not in content:
    content = content.replace(
        "import androidx.compose.runtime.mutableIntStateOf",
        "import androidx.compose.runtime.mutableIntStateOf\nimport androidx.compose.runtime.mutableLongStateOf"
    )
    print("✅ Import mutableLongStateOf agregado")

# 4) Inicializarla cuando se carga una URL
old = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."'''
new = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect
        try {
            status = "Cargando..."
            tiempoInicioStream = System.currentTimeMillis()'''
if old in content:
    content = content.replace(old, new, 1)
    print("✅ tiempoInicioStream se actualiza al cargar URL")
else:
    print("⚠️  No encontré el bloque de carga de URL")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -n "var tiempoInicioStream" "$FILE"
grep -n "import androidx.compose.runtime.mutableLongStateOf" "$FILE"
grep -n "tiempoInicioStream = System.currentTimeMillis()" "$FILE"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"