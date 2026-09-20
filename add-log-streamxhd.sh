#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-log"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-log"

echo "📝 Paso 1 — Creando ExtractorLog (logger global)..."

cat > "$DATA_DIR/ExtractorLog.kt" << 'EOF'
package com.anonimus757.tvapp.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Logger global para la extracción de m3u8.
 * Se ve en el reproductor tocando el botón 🐛 LOG.
 */
object ExtractorLog {
    private val _lineas = MutableStateFlow<List<String>>(emptyList())
    val lineas: StateFlow<List<String>> = _lineas.asStateFlow()

    fun log(msg: String) {
        _lineas.value = (_lineas.value + msg).takeLast(80)
    }

    fun limpiar() {
        _lineas.value = emptyList()
    }
}
EOF

echo "✅ ExtractorLog.kt creado"

echo ""
echo "📝 Paso 2 — Haciendo que M3u8Extractor loguee TODO..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Modificar extraer() para que loguee en ExtractorLog también
# ═══════════════════════════════════════════════════════════
old_extraer = '''    suspend fun extraer(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
        }'''

new_extraer = '''    suspend fun extraer(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        ExtractorLog.limpiar()
        ExtractorLog.log("🚀 EXTRAER: ${urlEmbed.take(80)}")

        val urlReal = decodificarR(urlEmbed) ?: urlEmbed
        if (urlReal != urlEmbed) {
            onLog("🔓 Param ?r decodificado")
            ExtractorLog.log("🔓 ?r decodificado")
        }'''

if old_extraer in content:
    content = content.replace(old_extraer, new_extraer)
    print("✅ extraer() loguea en ExtractorLog")

# ═══════════════════════════════════════════════════════════
# 2) Loguear en decodificarOfuscado el proceso completo
# ═══════════════════════════════════════════════════════════
old_decoder_start = '''    private fun decodificarOfuscado(html: String): String? {
        return try {
            // Verificar que tiene el patrón típico
            if (!html.contains("gV = [") && !html.contains("gV=[")) return null'''

new_decoder_start = '''    private fun decodificarOfuscado(html: String): String? {
        return try {
            ExtractorLog.log("🔍 Decoder: HTML ${html.length} bytes")
            ExtractorLog.log("🔍 ¿Tiene gV? ${html.contains("gV")}")
            ExtractorLog.log("🔍 ¿Tiene playbackURL? ${html.contains("playbackURL")}")
            ExtractorLog.log("🔍 ¿Tiene YIzxD? ${html.contains("YIzxD")}")

            // Verificar que tiene el patrón típico
            if (!html.contains("gV = [") && !html.contains("gV=[")) {
                ExtractorLog.log("❌ No tiene array gV")
                return null
            }'''

if old_decoder_start in content:
    content = content.replace(old_decoder_start, new_decoder_start)
    print("✅ decoder loguea inicio")

# Loguear cuando encuentra el array
old_array = '''            val arrayMatch = arrayRegex.find(html) ?: return null
            val arrayRaw = arrayMatch.groupValues[1]'''
new_array = '''            val arrayMatch = arrayRegex.find(html)
            if (arrayMatch == null) {
                ExtractorLog.log("❌ Regex del array gV no matchea")
                return null
            }
            val arrayRaw = arrayMatch.groupValues[1]
            ExtractorLog.log("✅ Array gV encontrado (${arrayRaw.length} chars)")'''
if old_array in content:
    content = content.replace(old_array, new_array)
    print("✅ log del array gV")

# Loguear cuando extrae las funciones k
old_k = '''            val kMatch = kRegex.find(html) ?: return null
            val fn1 = kMatch.groupValues[1]
            val fn2 = kMatch.groupValues[2]'''
new_k = '''            val kMatch = kRegex.find(html)
            if (kMatch == null) {
                ExtractorLog.log("❌ Regex k no matchea")
                return null
            }
            val fn1 = kMatch.groupValues[1]
            val fn2 = kMatch.groupValues[2]
            ExtractorLog.log("✅ Funciones k: $fn1 + $fn2")'''
if old_k in content:
    content = content.replace(old_k, new_k)
    print("✅ log de funciones k")

# Loguear cuando extrae los números
old_num = '''            val n1 = returnRegex1.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: return null
            val n2 = returnRegex2.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: return null
            val k = n1 + n2'''
new_num = '''            val n1 = returnRegex1.find(html)?.groupValues?.get(1)?.toIntOrNull()
            val n2 = returnRegex2.find(html)?.groupValues?.get(1)?.toIntOrNull()
            if (n1 == null || n2 == null) {
                ExtractorLog.log("❌ No se extrajeron números: n1=$n1 n2=$n2")
                return null
            }
            val k = n1 + n2
            ExtractorLog.log("✅ k = $n1 + $n2 = $k")'''
if old_num in content:
    content = content.replace(old_num, new_num)
    print("✅ log de números")

# Loguear elementos parseados
old_elem = '''            val elementos = elemRegex.findAll(arrayRaw)
                .mapNotNull { match ->'''
new_elem = '''            val totalMatches = elemRegex.findAll(arrayRaw).count()
            ExtractorLog.log("🔍 Elementos encontrados: $totalMatches")

            val elementos = elemRegex.findAll(arrayRaw)
                .mapNotNull { match ->'''
if old_elem in content:
    content = content.replace(old_elem, new_elem)
    print("✅ log de elementos")

# Loguear resultado final
old_result = '''            // Verificar que sea una URL válida
            if (elementos.startsWith("http") && elementos.contains("m3u8")) {
                elementos
            } else if (elementos.startsWith("http")) {
                // Puede ser un .ts u otro formato
                elementos
            } else null'''
new_result = '''            ExtractorLog.log("🔍 Resultado: ${elementos.take(100)}")
            ExtractorLog.log("🔍 Largo: ${elementos.length}")

            // Verificar que sea una URL válida
            if (elementos.startsWith("http") && elementos.contains("m3u8")) {
                ExtractorLog.log("✅ URL m3u8 decodificada OK")
                elementos
            } else if (elementos.startsWith("http")) {
                ExtractorLog.log("✅ URL decodificada (no m3u8): ${elementos.take(80)}")
                elementos
            } else {
                ExtractorLog.log("❌ Resultado no empieza con http")
                ExtractorLog.log("❌ Primeros 50 chars: ${elementos.take(50)}")
                null
            }'''
if old_result in content:
    content = content.replace(old_result, new_result)
    print("✅ log de resultado final")

# Loguear excepciones
old_catch = '''        } catch (e: Exception) {
            android.util.Log.d("M3u8Extractor", "decoder fail: ${e.message}")
            null
        }'''
new_catch = '''        } catch (e: Exception) {
            ExtractorLog.log("❌ Excepción: ${e.message}")
            android.util.Log.d("M3u8Extractor", "decoder fail: ${e.message}")
            null
        }'''
if old_catch in content:
    content = content.replace(old_catch, new_catch)
    print("✅ log de excepción")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Paso 3 — Agregar botón de LOG en el reproductor..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Import
if "import com.anonimus757.tvapp.data.ExtractorLog" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.Embed",
        "import com.anonimus757.tvapp.data.Embed\nimport com.anonimus757.tvapp.data.ExtractorLog"
    )

# Estado
if "var mostrarLogExtractor" not in content:
    ancla = "    var mostrarControles by remember { mutableStateOf(true) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    var mostrarLogExtractor by remember { mutableStateOf(false) }"
        )
        print("✅ Estado mostrarLogExtractor")

# Insertar botón + panel al FINAL del Box principal, antes del cierre
# Buscar la última AnimatedVisibility del WebView
old_cierre = '''                modifier = Modifier.size(1.dp)
            )
        }
    }
}'''

new_cierre = '''                modifier = Modifier.size(1.dp)
            )
        }

        // ═══════════════════════════════════════════════════════
        // 🐛 BOTÓN DE LOG DEL EXTRACTOR (para debug streamxhd)
        // ═══════════════════════════════════════════════════════
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color(0xCC000000))
                .border(2.dp, Color(0xFF4ADE80), RoundedCornerShape(10.dp))
                .clickable { mostrarLogExtractor = !mostrarLogExtractor }
                .padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text(
                "🐛 LOG",
                color = Color(0xFF4ADE80),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
        }

        if (mostrarLogExtractor) {
            val lineas by ExtractorLog.lineas.collectAsState()
            Box(
                Modifier
                    .align(Alignment.Center)
                    .fillMaxSize(0.9f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xEE000000))
                    .border(2.dp, Color(0xFF4ADE80), RoundedCornerShape(12.dp))
                    .padding(14.dp)
            ) {
                androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Text(
                            "🐛 LOG EXTRACTOR (${lineas.size} líneas)",
                            color = Color(0xFF4ADE80),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black
                        )
                        Spacer(Modifier.height(10.dp))
                    }
                    items(lineas.size) { i ->
                        val l = lineas[i]
                        val color = when {
                            l.contains("❌") -> Color(0xFFFF6B6B)
                            l.contains("✅") -> Color(0xFF4ADE80)
                            l.contains("🔍") -> Color(0xFF38BDF8)
                            else -> Color(0xFFCBD5E1)
                        }
                        Text(
                            l,
                            color = color,
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
}'''

if old_cierre in content:
    content = content.replace(old_cierre, new_cierre, 1)
    print("✅ Botón LOG + panel agregados")
else:
    print("⚠️  No encontré el cierre del Box principal, intentando variante...")
    # Buscar la última aparición de "modifier = Modifier.size(1.dp)"
    pattern = r'(modifier = Modifier\.size\(1\.dp\)\s*\n\s*\)\s*\n\s*\}\s*\n\s*\}\s*\n\})'
    match = re.search(pattern, content)
    if match:
        content = content[:match.start()] + new_cierre + content[match.end():]
        print("✅ Botón agregado (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$DATA_DIR/ExtractorLog.kt" ] && echo "  ✓ ExtractorLog.kt"
grep -q "ExtractorLog.log" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ M3u8Extractor loguea"
grep -q "mostrarLogExtractor" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Panel de log en PlayerScreen"

echo ""
echo "✅✅✅ Log de debug del extractor instalado"
echo ""
echo "📌 Cómo usar:"
echo "   1. Entrá a un canal de streamxhd"
echo "   2. Tocá el botón 🐛 LOG arriba a la derecha"
echo "   3. Vas a ver TODOS los pasos del extractor"
echo "   4. Pegame esos logs"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"