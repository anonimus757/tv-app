#!/bin/bash
set -e

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/HomeScreen.kt"

cp "$FILE" "$FILE.bak-preview-fix"

echo "📝 Fix del preview de cards..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Sacar el val esTV que agregué en EventoCardPremium (ya existe uno antes)
content = content.replace(
    '''    var focused by remember { mutableStateOf(false) }
    val esTV = com.anonimus757.tvapp.ui.util.rememberEsTV()

    // 🆕 Preview en TV: si mantiene el foco 10 seg y está EN VIVO → reproduce
    var mostrarVideoPreview by remember { mutableStateOf(false) }''',
    '''    var focused by remember { mutableStateOf(false) }

    // 🆕 Preview en TV: si mantiene el foco 10 seg y está EN VIVO → reproduce
    var mostrarVideoPreview by remember { mutableStateOf(false) }''',
    1
)
print("✅ esTV duplicado removido")

# 2) Mover 'mostrarPreview' ANTES de 'onClick' para no romper trailing lambda
content = content.replace(
    '''private fun EventoCardPremium(
    ev: Evento,
    enVivo: Boolean,
    onClick: () -> Unit,
    mostrarPreview: Boolean = false
) {''',
    '''private fun EventoCardPremium(
    ev: Evento,
    enVivo: Boolean,
    mostrarPreview: Boolean = false,
    onClick: () -> Unit
) {''',
    1
)
print("✅ Orden de parámetros corregido")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -n "val esTV = com.anonimus757.tvapp.ui.util.rememberEsTV()" "$FILE" || echo "  ✓ Sin duplicado de esTV"
grep -A4 "private fun EventoCardPremium(" "$FILE" | head -5

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"