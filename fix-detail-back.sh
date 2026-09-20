#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/EventDetailScreen.kt"

cp "$FILE" "$FILE.bak-back"

echo "📝 Agregando botón Volver + BackHandler en EventDetailScreen..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Agregar imports necesarios
# ═══════════════════════════════════════════════════════════
if "import androidx.activity.compose.BackHandler" not in content:
    content = content.replace(
        "import androidx.compose.animation.animateColorAsState",
        "import androidx.activity.compose.BackHandler\nimport androidx.compose.animation.animateColorAsState"
    )
    print("✅ Import BackHandler")

if "import androidx.compose.foundation.layout.statusBarsPadding" not in content:
    # No siempre es necesario, chequeo si el archivo ya tiene algo similar
    pass

# ═══════════════════════════════════════════════════════════
# 2) Agregar BackHandler al inicio del composable
# ═══════════════════════════════════════════════════════════
# Buscar el inicio del composable EventDetailScreen
ancla_backhandler = '''@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {'''

nuevo_backhandler = '''@Composable
fun EventDetailScreen(
    evento: Evento,
    onCanalClick: (Embed) -> Unit,
    onBack: () -> Unit
) {
    // ═══════════════════════════════════════════════════════════
    // FIX: Back del celu/TV → volver al Home (no cerrar la app)
    // ═══════════════════════════════════════════════════════════
    BackHandler {
        onBack()
    }
'''

if ancla_backhandler in content:
    content = content.replace(ancla_backhandler, nuevo_backhandler)
    print("✅ BackHandler agregado")
else:
    print("⚠️  No encontré el inicio del composable EventDetailScreen")

# ═══════════════════════════════════════════════════════════
# 3) Agregar botón "Volver" en el header
# ═══════════════════════════════════════════════════════════
# Buscar el Row principal del header donde están imagen + descripción
ancla_header = '''            Row(
                Modifier.fadeInOnLoad(durationMs = 450),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier.size(110.dp).clip(RoundedCornerShape(16.dp))
                        .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                    contentAlignment = Alignment.Center
                ) {'''

nuevo_header = '''            // ═══════════════════════════════════════════════════════════
            // FIX: Botón "Volver" arriba a la izquierda
            // ═══════════════════════════════════════════════════════════
            Row(
                Modifier.fillMaxWidth().fadeInOnLoad(durationMs = 350),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BotonVolverDetalle(onBack)
            }
            Spacer(Modifier.height(24.dp))

            Row(
                Modifier.fadeInOnLoad(durationMs = 450),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier.size(110.dp).clip(RoundedCornerShape(16.dp))
                        .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
                    contentAlignment = Alignment.Center
                ) {'''

if ancla_header in content:
    content = content.replace(ancla_header, nuevo_header)
    print("✅ Botón Volver agregado en el header")
else:
    print("⚠️  No encontré el header principal")

# ═══════════════════════════════════════════════════════════
# 4) Agregar el composable BotonVolverDetalle al final
# ═══════════════════════════════════════════════════════════
if "private fun BotonVolverDetalle" not in content:
    componente = '''

// ═══════════════════════════════════════════════════════════
// FIX: Botón "Volver" para el header del detalle
// ═══════════════════════════════════════════════════════════
@Composable
private fun BotonVolverDetalle(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(10.dp)
            )
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.volver,
            contentDescription = "Volver",
            tint = if (focused) Color.Black else AppColors.Gold,
            modifier = Modifier.size(20.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            "Volver",
            color = if (focused) Color.Black else AppColors.Gold,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
'''

    content = content.rstrip() + "\n" + componente
    print("✅ Componente BotonVolverDetalle agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "BackHandler" "$FILE" && echo "  ✓ BackHandler (no cierra la app)"
grep -q "BotonVolverDetalle" "$FILE" && echo "  ✓ Botón Volver visible"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   • Botón 'Volver' visible arriba a la izquierda"
echo "   • Botón 'Back' del celu/TV → vuelve al Home (no cierra la app)"
echo "   • Ambos respetan el foco del D-pad (dorado al enfocar)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"