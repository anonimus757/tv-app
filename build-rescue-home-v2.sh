#!/bin/bash
set -e

echo "🚑 Rescatando archivos rotos..."

# ═══════════════════════════════════════════════════════════
# 1. RESTAURAR M3u8Extractor.kt desde el backup más viejo (el limpio)
# ═══════════════════════════════════════════════════════════

EXTRACTOR="app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"

echo "📂 Backups disponibles de M3u8Extractor.kt:"
ls -lat ${EXTRACTOR}.bak.* 2>/dev/null | head -10 || echo "  (ninguno)"

# El backup más VIEJO es el estado ANTES de meter mano (el más limpio)
BACKUP_MAS_VIEJO=$(ls -tr ${EXTRACTOR}.bak.* 2>/dev/null | head -1)

if [ -z "$BACKUP_MAS_VIEJO" ]; then
    echo "❌ No hay backups de M3u8Extractor.kt. Necesito que me pases el contenido original."
    exit 1
fi

echo "✅ Restaurando desde: $BACKUP_MAS_VIEJO"
cp "$BACKUP_MAS_VIEJO" "$EXTRACTOR"
echo "✅ M3u8Extractor.kt restaurado"

# Verificar que compila en estructura básica
if ! grep -q "suspend fun extraerYTestear" "$EXTRACTOR"; then
    echo "⚠️  OJO: $EXTRACTOR no tiene extraerYTestear. Puede que el backup sea de otra versión."
    echo "   Backup restaurado. Revisalo."
fi

# ═══════════════════════════════════════════════════════════
# 2. FIX HomeScreen.kt línea 390: remember dentro de forEach
# ═══════════════════════════════════════════════════════════

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
cp "$HOME_FILE" "${HOME_FILE}.bak.fix.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Reemplazar el bloque problemático: remember dentro del forEach en LazyColumn
old_block = '''        gruposPorDia.forEach { (dia, lista) ->
            val color = when (dia) {
                "HOY", "MAÑANA" -> AppColors.GoldBright
                "PASADO MAÑANA" -> AppColors.Gold
                "FINALIZADOS" -> AppColors.TextMuted
                else -> AppColors.TextSecondary
            }
            val icono = when (dia) {
                "HOY" -> "📅 HOY"
                "MAÑANA" -> "📅 MAÑANA"
                "PASADO MAÑANA" -> "📅 PASADO MAÑANA"
                "ESTA SEMANA" -> "📅 ESTA SEMANA"
                "PRÓXIMOS" -> "📅 PRÓXIMOS DÍAS"
                "FINALIZADOS" -> "📅 FINALIZADOS"
                else -> "📅 $dia"
            }
            val colapsable = dia in listOf("ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")
            var expandido by remember(dia) { mutableStateOf(!colapsable) }

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

new_block = '''        gruposPorDia.forEach { (dia, lista) ->
            val color = when (dia) {
                "HOY", "MAÑANA" -> AppColors.GoldBright
                "PASADO MAÑANA" -> AppColors.Gold
                "FINALIZADOS" -> AppColors.TextMuted
                else -> AppColors.TextSecondary
            }
            val icono = when (dia) {
                "HOY" -> "📅 HOY"
                "MAÑANA" -> "📅 MAÑANA"
                "PASADO MAÑANA" -> "📅 PASADO MAÑANA"
                "ESTA SEMANA" -> "📅 ESTA SEMANA"
                "PRÓXIMOS" -> "📅 PRÓXIMOS DÍAS"
                "FINALIZADOS" -> "📅 FINALIZADOS"
                else -> "📅 $dia"
            }
            val colapsable = dia in listOf("ESTA SEMANA", "PRÓXIMOS", "FINALIZADOS")

            // Usamos key() para que cada grupo tenga su propio estado de expandido
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
            }
        }'''

if old_block not in c:
    print("⚠️ No encontré el bloque exacto. Buscando por firma más flexible...")
    # Fallback: buscar solo el forEach y ver si tiene remember adentro
    if 'gruposPorDia.forEach' in c and 'var expandido by remember(dia)' in c:
        print("✅ Detecté el patrón, aplicando fix alternativo")
        # Reemplazo simple: remember(dia) → usar key externo
        c = c.replace(
            'var expandido by remember(dia) { mutableStateOf(!colapsable) }',
            'var expandido by remember { mutableStateOf(!colapsable) }'
        )
    else:
        print("❌ No pude detectar el patrón. Abortando modificación de HomeScreen.")
        raise SystemExit(1)
else:
    c = c.replace(old_block, new_block)
    print("✅ HomeScreen.kt: remember(dia) → key(dia) + remember")

# Agregar import de key si no está
if 'import androidx.compose.runtime.key' not in c and 'import androidx.compose.runtime.*' not in c:
    c = c.replace(
        'import androidx.compose.runtime.Composable',
        'import androidx.compose.runtime.Composable\nimport androidx.compose.runtime.key'
    )

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("✅ HomeScreen.kt arreglado")
PYEOF

echo ""
echo "✅✅✅ Rescate completo"
echo ""
echo "📋 Próximos pasos:"
echo "  1. ./gradlew clean"
echo "  2. ./gradlew assembleDebug --no-daemon --max-workers=1"
echo ""
echo "Si falla, pasame el output de:"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1 2>&1 | grep -E '^e:' | head -20"
