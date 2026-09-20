#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

echo "📝 Agregando debug en pantalla..."

# Backup
cp "$PKG_DIR/ui/HomeScreen.kt" "$PKG_DIR/ui/HomeScreen.kt.bak"

# 1) Insertar un logger global observable
cat > "$PKG_DIR/data/DebugLog.kt" << 'EOF'
package com.anonimus757.tvapp.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Logger observable en vivo. Se muestra en pantalla con toque largo en el logo FutTV.
 * Ayuda a diagnosticar problemas sin adb.
 */
object DebugLog {
    private val _lineas = MutableStateFlow<List<String>>(emptyList())
    val lineas: StateFlow<List<String>> = _lineas.asStateFlow()

    fun log(msg: String) {
        val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())
        val nueva = "[$t] $msg"
        _lineas.value = (_lineas.value + nueva).takeLast(30)
    }

    fun limpiar() { _lineas.value = emptyList() }
}
EOF

# 2) Hookear DebugLog en FirebaseManager
if ! grep -q "DebugLog.log" "$PKG_DIR/data/FirebaseManager.kt"; then
  python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/FirebaseManager.kt"
with open(file_path) as f: content = f.read()

# Agregar log al éxito
content = content.replace(
    'Log.d(TAG, "✅ Firebase inicializado")',
    'Log.d(TAG, "✅ Firebase inicializado")\n            DebugLog.log("✅ Firebase init OK")'
)

content = content.replace(
    'Log.e(TAG, "❌ init fail: ${e.message}")',
    'Log.e(TAG, "❌ init fail: ${e.message}")\n            DebugLog.log("❌ Firebase init fail: ${e.message}")'
)

content = content.replace(
    'Log.d(TAG, "✅ Login anónimo OK: ${result.user?.uid?.take(8)}...")',
    'Log.d(TAG, "✅ Login anónimo OK: ${result.user?.uid?.take(8)}...")\n            DebugLog.log("✅ Login OK: ${result.user?.uid?.take(8)}...")'
)

content = content.replace(
    'Log.e(TAG, "❌ Login anónimo fail: ${e.message}")',
    'Log.e(TAG, "❌ Login anónimo fail: ${e.message}")\n            DebugLog.log("❌ Login fail: ${e.message}")'
)

content = content.replace(
    'Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")',
    'Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")\n            DebugLog.log("🔔 FCM token OK")'
)

with open(file_path, "w") as f: f.write(content)
print("✅ FirebaseManager hookeado")
PYEOF
fi

# 3) Hookear DebugLog en EventRepository
if ! grep -q "DebugLog.log" "$PKG_DIR/data/EventRepository.kt"; then
  python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(file_path) as f: content = f.read()

# Firestore OK
content = content.replace(
    'Log.d(TAG, "✅ Firestore: ${lista.size} eventos")',
    'Log.d(TAG, "✅ Firestore: ${lista.size} eventos")\n            DebugLog.log("✅ Firestore: ${lista.size} eventos")'
)

# Firestore error
content = content.replace(
    'Log.e(TAG, "❌ Firestore fail: ${e.message}")',
    'Log.e(TAG, "❌ Firestore fail: ${e.message}")\n            DebugLog.log("❌ Firestore fail: ${e.message}")'
)

# Scraping OK
content = content.replace(
    'Log.d(TAG, "✅ Scraping: ${resultado.size} eventos")',
    'Log.d(TAG, "✅ Scraping: ${resultado.size} eventos")\n            DebugLog.log("✅ Scraping: ${resultado.size} eventos")'
)

with open(file_path, "w") as f: f.write(content)
print("✅ EventRepository hookeado")
PYEOF
fi

# 4) Agregar overlay de debug en HomeScreen con toque largo
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f: content = f.read()

# Imports necesarios
if "import androidx.compose.foundation.gestures.detectTapGestures" not in content:
    content = content.replace(
        "import androidx.compose.foundation.focusable",
        "import androidx.compose.foundation.focusable\nimport androidx.compose.foundation.gestures.detectTapGestures\nimport androidx.compose.ui.input.pointer.pointerInput"
    )

# Import DebugLog
if "import com.anonimus757.tvapp.data.DebugLog" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.Evento",
        "import com.anonimus757.tvapp.data.DebugLog\nimport com.anonimus757.tvapp.data.Evento"
    )

# Agregar estado mostrarDebug a HomeScreen
content = content.replace(
    "    var status by remember { mutableStateOf(\"Conectando...\") }",
    "    var status by remember { mutableStateOf(\"Conectando...\") }\n    var mostrarDebug by remember { mutableStateOf(false) }"
)

# Pasar mostrarDebug al ContenidoHome
content = content.replace(
    "else -> ContenidoHome(\n                eventosFirebase = eventosFirebase,",
    "else -> ContenidoHome(\n                mostrarDebug = mostrarDebug,\n                onMostrarDebugChange = { mostrarDebug = it },\n                eventosFirebase = eventosFirebase,"
)

# Firma de ContenidoHome
content = content.replace(
    "private fun ContenidoHome(\n    eventosFirebase: List<Evento>,",
    "private fun ContenidoHome(\n    mostrarDebug: Boolean,\n    onMostrarDebugChange: (Boolean) -> Unit,\n    eventosFirebase: List<Evento>,"
)

# Hacer el logo clickeable con toque largo (dentro de HeaderFutTV se llama)
# Agregar al LazyColumn un item extra para el overlay debug
content = content.replace(
    'item(key = "footer") {',
    '''item(key = "debug_overlay") {
            if (mostrarDebug) {
                DebugOverlay { onMostrarDebugChange(false) }
            }
        }

        item(key = "footer") {'''
)

# Modificar el header para aceptar toque largo (agrego un Box envolvente)
content = content.replace(
    '''        // Header
        item(key = "header") {
            HeaderFutTV(textoBienvenida, totalEventos, totalCanales)
        }''',
    '''        // Header (toque largo en el logo activa debug)
        item(key = "header") {
            Box(
                Modifier.pointerInput(Unit) {
                    detectTapGestures(
                        onLongPress = { onMostrarDebugChange(!mostrarDebug) }
                    )
                }
            ) {
                HeaderFutTV(textoBienvenida, totalEventos, totalCanales)
            }
        }'''
)

# Agregar el composable DebugOverlay al final del archivo
content += '''

@Composable
private fun DebugOverlay(onCerrar: () -> Unit) {
    val lineas by DebugLog.lineas.collectAsState()
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 40.dp, vertical = 20.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xEE000000))
            .border(2.dp, Color(0xFF4ADE80), RoundedCornerShape(12.dp))
            .padding(16.dp)
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🔍 DEBUG", color = Color(0xFF4ADE80), fontSize = 16.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                Text("toque largo en ⚽ FutTV para cerrar", color = Color(0xFF94A3B8), fontSize = 11.sp)
            }
            Spacer(Modifier.height(10.dp))
            if (lineas.isEmpty()) {
                Text("Sin logs todavía", color = Color(0xFF94A3B8), fontSize = 12.sp)
            } else {
                lineas.forEach { l ->
                    Text(
                        l,
                        color = if (l.contains("❌")) Color(0xFFEF4444) else Color(0xFFE2E8F0),
                        fontSize = 11.sp,
                        lineHeight = 15.sp,
                        modifier = Modifier.padding(vertical = 1.dp)
                    )
                }
            }
        }
    }
}
'''

with open(file_path, "w") as f: f.write(content)
print("✅ HomeScreen con overlay debug")
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$PKG_DIR/data/DebugLog.kt" ] && echo "  ✓ DebugLog.kt creado"
grep -q "DebugLog.log" "$PKG_DIR/data/FirebaseManager.kt" && echo "  ✓ FirebaseManager hookeado"
grep -q "DebugLog.log" "$PKG_DIR/data/EventRepository.kt" && echo "  ✓ EventRepository hookeado"
grep -q "DebugOverlay" "$PKG_DIR/ui/HomeScreen.kt" && echo "  ✓ Overlay debug en HomeScreen"

echo ""
echo "✅✅✅ Fix 28d completo — debug en pantalla"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"