#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/BusquedaScreen.kt"

cp "$FILE" "$FILE.bak-voz"

echo "📝 Agregando búsqueda por voz..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/BusquedaScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Imports necesarios
imports_to_add = '''import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
'''

# Encontrar el último import y agregar
last_import = content.rfind("import ")
end_of_line = content.find("\n", last_import)
content = content[:end_of_line+1] + imports_to_add + content[end_of_line+1:]
print("✅ Imports agregados")

# 2) Agregar el launcher y la función de voz al inicio del composable
# Buscamos donde está declarada "query"
anchor = '    var query by remember { mutableStateOf("") }'
voz_code = '''    var query by remember { mutableStateOf("") }

    // ═══════════════════════════════════════════════════════════
    // 🎤 BÚSQUEDA POR VOZ
    // ═══════════════════════════════════════════════════════════
    val voiceLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val texto = result.data?.getStringArrayListExtra(
                RecognizerIntent.EXTRA_RESULTS
            )?.firstOrNull()
            if (!texto.isNullOrBlank()) {
                query = texto
            }
        }
    }

    val abrirVoz: () -> Unit = {
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-ES")
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Decí el equipo o evento")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            voiceLauncher.launch(intent)
        } catch (_: Exception) {}
    }'''

if anchor in content:
    content = content.replace(anchor, voz_code, 1)
    print("✅ Launcher de voz agregado")
else:
    print("⚠️  No encontré la declaración de 'query'")

# 3) Agregar el botón de micrófono al lado del OutlinedTextField
# El OutlinedTextField está solo en un Spacer... necesitamos ponerlo en un Row
old_field = '''            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(60) },
                placeholder = { Text("Boca, River, ESPN, Pelota Libre...", color = AppColors.TextMuted) },
                leadingIcon = {
                    Icon(
                        imageVector = AppIcons.buscar,
                        contentDescription = null,
                        tint = AppColors.Gold,
                        modifier = Modifier.size(20.dp)
                    )
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = TextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedContainerColor = AppColors.SurfaceLight,
                    unfocusedContainerColor = AppColors.SurfaceLight,
                    cursorColor = AppColors.Gold,
                    focusedIndicatorColor = AppColors.Gold,
                    unfocusedIndicatorColor = AppColors.TextMuted,
                    focusedPlaceholderColor = AppColors.TextMuted,
                    unfocusedPlaceholderColor = AppColors.TextMuted
                )
            )'''

new_field = '''            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it.take(60) },
                    placeholder = { Text("Boca, River, ESPN...", color = AppColors.TextMuted) },
                    leadingIcon = {
                        Icon(
                            imageVector = AppIcons.buscar,
                            contentDescription = null,
                            tint = AppColors.Gold,
                            modifier = Modifier.size(20.dp)
                        )
                    },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    colors = TextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedContainerColor = AppColors.SurfaceLight,
                        unfocusedContainerColor = AppColors.SurfaceLight,
                        cursorColor = AppColors.Gold,
                        focusedIndicatorColor = AppColors.Gold,
                        unfocusedIndicatorColor = AppColors.TextMuted,
                        focusedPlaceholderColor = AppColors.TextMuted,
                        unfocusedPlaceholderColor = AppColors.TextMuted
                    )
                )
                Spacer(Modifier.width(10.dp))
                BotonVoz(onClick = abrirVoz)
            }'''

if old_field in content:
    content = content.replace(old_field, new_field, 1)
    print("✅ Botón de voz agregado al campo")
else:
    print("⚠️  No encontré el OutlinedTextField, intentando variante...")
    # Variante: buscar solo el OutlinedTextField con menos contexto
    pattern = r'(OutlinedTextField\(\s*value = query,[\s\S]*?\n\s*\)\s*\n\s*\))'
    match = re.search(pattern, content)
    if match:
        content = content.replace(match.group(1), new_field)
        print("✅ Botón de voz (variante)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# Agregar el composable BotonVoz al final
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/BusquedaScreen.kt"
with open(file_path) as f:
    content = f.read()

if "private fun BotonVoz" not in content:
    componente = '''

// ═══════════════════════════════════════════════════════════
// 🎤 BOTÓN DE BÚSQUEDA POR VOZ
// ═══════════════════════════════════════════════════════════
@Composable
private fun BotonVoz(onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Box(
        Modifier
            .size(56.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.15f))
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else AppColors.Gold.copy(alpha = 0.5f),
                RoundedCornerShape(12.dp)
            )
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text("🎤", fontSize = 24.sp)
    }
}
'''
    content = content.rstrip() + componente + "\n"
    with open(file_path, "w") as f:
        f.write(content)
    print("✅ Composables BotonVoz agregado")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "RecognizerIntent" "$FILE" && echo "  ✓ Reconocimiento de voz"
grep -q "BotonVoz" "$FILE" && echo "  ✓ Botón de voz"
grep -q "abrirVoz" "$FILE" && echo "  ✓ Función abrirVoz"

echo ""
echo "✅✅✅ Búsqueda por voz lista"
echo ""
echo "📌 Cómo funciona:"
echo "   1. En la pantalla de Búsqueda aparece un botón 🎤 al lado del campo"
echo "   2. Al tocarlo → abre el reconocimiento de voz del sistema"
echo "   3. Dictás 'Boca' → se rellena y busca automáticamente"
echo "   4. Funciona en TV (control con mic) y en celu"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"