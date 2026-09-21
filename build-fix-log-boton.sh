#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# 1. Crear ApiLogs.kt (recolector global)
# ═══════════════════════════════════════════════════════════
mkdir -p app/src/main/java/com/anonimus757/tvapp/data

cat > app/src/main/java/com/anonimus757/tvapp/data/ApiLogs.kt << 'KOTLIN_EOF'
package com.anonimus757.tvapp.data

import androidx.compose.runtime.mutableStateListOf
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Recolector de logs SOLO para el ApiSportsRepository.
 * El botón 🐛 del EventDetailScreen muestra estos logs.
 */
object ApiLogs {
    private const val MAX_LOGS = 100
    val logs = mutableStateListOf<String>()

    private val horaFmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    fun add(mensaje: String) {
        val hora = horaFmt.format(Date())
        logs.add("[$hora] $mensaje")
        if (logs.size > MAX_LOGS) {
            logs.removeAt(0)
        }
        // También mandamos al DebugLog general
        try { DebugLog.log(mensaje) } catch (_: Exception) {}
    }

    fun clear() {
        logs.clear()
    }
}
KOTLIN_EOF

echo "✅ ApiLogs.kt creado"

# ═══════════════════════════════════════════════════════════
# 2. Reemplazar DebugLog.log por ApiLogs.add en ApiSportsRepository
# ═══════════════════════════════════════════════════════════
API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
if [ -f "$API" ]; then
    cp "$API" "${API}.bak.logboton.$(date +%s)"
    python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Reemplazar DebugLog.log(...) por ApiLogs.add(...)
c = c.replace('DebugLog.log(', 'ApiLogs.add(')

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ ApiSportsRepository: DebugLog → ApiLogs")
PYEOF
fi

# ═══════════════════════════════════════════════════════════
# 3. Agregar botón 🐛 LOGS + overlay en EventDetailScreen
# ═══════════════════════════════════════════════════════════
DETAIL="app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
[ ! -f "$DETAIL" ] && { echo "❌ No existe $DETAIL"; exit 1; }
cp "$DETAIL" "${DETAIL}.bak.logboton.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/EventDetailScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── 1. Import ApiLogs ───
if 'import com.anonimus757.tvapp.data.ApiLogs' not in c:
    c = c.replace(
        'import com.anonimus757.tvapp.data.ApiSportsRepository',
        'import com.anonimus757.tvapp.data.ApiLogs\nimport com.anonimus757.tvapp.data.ApiSportsRepository'
    )
    print("✅ Import ApiLogs")

# ─── 2. Import para el botón flotante (LazyRow para los logs) ───
if 'import androidx.compose.foundation.lazy.LazyRow' not in c:
    c = c.replace(
        'import androidx.compose.foundation.lazy.LazyColumn',
        'import androidx.compose.foundation.lazy.LazyColumn\nimport androidx.compose.foundation.lazy.LazyRow\nimport androidx.compose.foundation.lazy.items'
    )
    print("✅ Imports LazyRow + items")

# ─── 3. Estado del overlay + botón en la pantalla principal ───
viejo_final = '''            item(key = "footer") { Spacer(Modifier.height(30.dp)) }
        }
    }
}'''

nuevo_final = '''            item(key = "footer") { Spacer(Modifier.height(60.dp)) }
        }

        // 🐛 Botón flotante de logs (esquina inferior derecha)
        LogsBotonFlotante()
    }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN FLOTANTE 🐛 + OVERLAY DE LOGS
// ═══════════════════════════════════════════════════════════════

@Composable
private fun BoxScope.LogsBotonFlotante() {
    var mostrarLogs by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }

    // Botón flotante
    Box(
        Modifier
            .align(Alignment.BottomEnd)
            .padding(end = 16.dp, bottom = 20.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { mostrarLogs = !mostrarLogs }
            .clip(RoundedCornerShape(20.dp))
            .background(
                if (focused) AppColors.GoldBright
                else Color(0xFF1A1A22).copy(alpha = 0.95f)
            )
            .border(
                1.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(20.dp)
            )
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("🐛", fontSize = 16.sp)
            Spacer(Modifier.width(6.dp))
            Text(
                if (mostrarLogs) "CERRAR" else "LOGS",
                color = if (focused) Color.Black else AppColors.GoldBright,
                fontSize = 12.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 0.5.sp
            )
            // Badge con cantidad de logs
            if (ApiLogs.logs.isNotEmpty()) {
                Spacer(Modifier.width(6.dp))
                Box(
                    Modifier.clip(CircleShape)
                        .background(if (focused) Color.Black else AppColors.Gold)
                        .padding(horizontal = 6.dp, vertical = 1.dp)
                ) {
                    Text(
                        "${ApiLogs.logs.size}",
                        color = if (focused) AppColors.GoldBright else Color.Black,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }
    }

    // Overlay con los logs
    if (mostrarLogs) {
        Box(
            Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = 70.dp)
                .widthIn(max = 420.dp)
                .heightIn(max = 400.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF0A0A0F).copy(alpha = 0.98f))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(16.dp))
        ) {
            Column(Modifier.padding(12.dp)) {
                // Header del overlay
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("🐛 LOGS DE BÚSQUEDA", color = AppColors.GoldBright,
                        fontSize = 12.sp, fontWeight = FontWeight.Black,
                        letterSpacing = 1.sp)
                    Spacer(Modifier.weight(1f))
                    Box(
                        Modifier.clip(RoundedCornerShape(8.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .clickable { ApiLogs.clear() }
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Text("Limpiar", color = AppColors.TextSecondary, fontSize = 10.sp)
                    }
                }
                Spacer(Modifier.height(8.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))
                Spacer(Modifier.height(8.dp))

                if (ApiLogs.logs.isEmpty()) {
                    Text("Sin logs todavía. Abrí un evento en vivo.",
                        color = AppColors.TextMuted, fontSize = 11.sp)
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp),
                        reverseLayout = true
                    ) {
                        items(ApiLogs.logs.reversed()) { log ->
                            Text(
                                log,
                                color = when {
                                    log.contains("✅") -> Color(0xFF4ADE80)
                                    log.contains("❌") -> Color(0xFFFF6B5D)
                                    log.contains("⚠️") -> Color(0xFFFFD93D)
                                    log.contains("📌") -> Color(0xFF60A5FA)
                                    else -> AppColors.TextSecondary
                                },
                                fontSize = 10.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                lineHeight = 14.sp,
                                modifier = Modifier.padding(vertical = 1.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}'''

if viejo_final in c:
    c = c.replace(viejo_final, nuevo_final, 1)
    print("✅ Botón flotante + overlay agregados")
else:
    print("⚠️ No matcheó el bloque final. Probando variante...")
    # Buscar el último item footer
    patron = re.compile(
        r'item\(key = "footer"\) \{ Spacer\(Modifier\.height\(\d+\.dp\)\) \}\s*\}\s*\}\s*\}',
        re.DOTALL
    )
    m = patron.search(c)
    if m:
        bloque_viejo = m.group(0)
        bloque_nuevo = bloque_viejo.replace(
            '}\n    }\n}',
            '}\n\n        // 🐛 Botón flotante de logs\n        LogsBotonFlotante()\n    }\n}',
            1
        )
        # Insertar la función después del cierre principal
        c = c.replace(bloque_viejo, bloque_nuevo, 1)
        # Agregar la función LogsBotonFlotante al final del archivo
        funcion_logs = '''

@Composable
private fun BoxScope.LogsBotonFlotante() {
    var mostrarLogs by remember { mutableStateOf(false) }
    var focused by remember { mutableStateOf(false) }

    Box(
        Modifier
            .align(Alignment.BottomEnd)
            .padding(end = 16.dp, bottom = 20.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { mostrarLogs = !mostrarLogs }
            .clip(RoundedCornerShape(20.dp))
            .background(if (focused) AppColors.GoldBright else Color(0xFF1A1A22).copy(alpha = 0.95f))
            .border(1.dp, if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("🐛", fontSize = 16.sp)
            Spacer(Modifier.width(6.dp))
            Text(if (mostrarLogs) "CERRAR" else "LOGS",
                color = if (focused) Color.Black else AppColors.GoldBright,
                fontSize = 12.sp, fontWeight = FontWeight.Black)
            if (ApiLogs.logs.isNotEmpty()) {
                Spacer(Modifier.width(6.dp))
                Box(Modifier.clip(CircleShape).background(if (focused) Color.Black else AppColors.Gold)
                    .padding(horizontal = 6.dp, vertical = 1.dp)) {
                    Text("${ApiLogs.logs.size}", color = if (focused) AppColors.GoldBright else Color.Black,
                        fontSize = 10.sp, fontWeight = FontWeight.Black)
                }
            }
        }
    }

    if (mostrarLogs) {
        Box(
            Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 70.dp)
                .widthIn(max = 420.dp).heightIn(max = 400.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF0A0A0F).copy(alpha = 0.98f))
                .border(1.dp, AppColors.Gold.copy(alpha = 0.5f), RoundedCornerShape(16.dp))
        ) {
            Column(Modifier.padding(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("🐛 LOGS DE BÚSQUEDA", color = AppColors.GoldBright,
                        fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                    Spacer(Modifier.weight(1f))
                    Box(Modifier.clip(RoundedCornerShape(8.dp))
                        .background(Color.White.copy(alpha = 0.08f))
                        .clickable { ApiLogs.clear() }
                        .padding(horizontal = 8.dp, vertical = 3.dp)) {
                        Text("Limpiar", color = AppColors.TextSecondary, fontSize = 10.sp)
                    }
                }
                Spacer(Modifier.height(8.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))
                Spacer(Modifier.height(8.dp))
                if (ApiLogs.logs.isEmpty()) {
                    Text("Sin logs todavía.", color = AppColors.TextMuted, fontSize = 11.sp)
                } else {
                    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 320.dp), reverseLayout = true) {
                        items(ApiLogs.logs.reversed()) { log ->
                            Text(log,
                                color = when {
                                    log.contains("✅") -> Color(0xFF4ADE80)
                                    log.contains("❌") -> Color(0xFFFF6B5D)
                                    log.contains("⚠️") -> Color(0xFFFFD93D)
                                    log.contains("📌") -> Color(0xFF60A5FA)
                                    else -> AppColors.TextSecondary
                                },
                                fontSize = 10.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                lineHeight = 14.sp,
                                modifier = Modifier.padding(vertical = 1.dp))
                        }
                    }
                }
            }
        }
    }
}
'''
        c = c + funcion_logs
        print("✅ Variante aplicada")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ EventDetailScreen.kt actualizado")
PYEOF

echo ""
echo "✅✅✅ Botón de logs agregado"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
