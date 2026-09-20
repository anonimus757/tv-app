#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
DATA_DIR="$PKG_DIR/data"
UI_DIR="$PKG_DIR/ui"
UTIL_DIR="$UI_DIR/util"
MANIFEST="app/src/main/AndroidManifest.xml"

echo "💾 Backups..."
cp "$MANIFEST" "$MANIFEST.bak-orient"
cp "$DATA_DIR/AjustesStore.kt" "$DATA_DIR/AjustesStore.kt.bak-orient"
cp "$PKG_DIR/MainActivity.kt" "$PKG_DIR/MainActivity.kt.bak-orient"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-orient"
cp "$UI_DIR/AjustesScreen.kt" "$UI_DIR/AjustesScreen.kt.bak-orient"
cp "$UTIL_DIR/DetectorDispositivo.kt" "$UTIL_DIR/DetectorDispositivo.kt.bak-orient"
echo "✅ Backups creados"

# ═══════════════════════════════════════════════════════════
# 1) DetectorDispositivo: agregar helper findActivity
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Extendiendo DetectorDispositivo con findActivity..."

cat >> "$UTIL_DIR/DetectorDispositivo.kt" << 'EOF'

/**
 * Busca la Activity desde un Context (puede estar envuelta en ContextWrapper).
 * Devuelve null si no encuentra.
 */
fun android.content.Context.findActivity(): android.app.Activity? {
    var ctx: android.content.Context? = this
    while (ctx is android.content.ContextWrapper) {
        if (ctx is android.app.Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
EOF

echo "✅ findActivity agregado"

# ═══════════════════════════════════════════════════════════
# 2) AndroidManifest: quitar landscape, agregar configChanges
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Actualizando AndroidManifest..."

python3 << 'PYEOF'
file_path = "app/src/main/AndroidManifest.xml"
with open(file_path) as f:
    content = f.read()

# Reemplazar android:screenOrientation="landscape" por configChanges
if 'android:screenOrientation="landscape"' in content:
    content = content.replace(
        'android:screenOrientation="landscape"',
        'android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|smallestScreenSize|uiMode|density"'
    )
    print("✅ screenOrientation reemplazado por configChanges")
else:
    print("ℹ️  No tenía screenOrientation=landscape")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) AjustesStore: preferencia de orientación
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 AjustesStore: agregando preferencia de orientación..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/AjustesStore.kt"
with open(file_path) as f:
    content = f.read()

# Agregar constantes y métodos
if "KEY_ORIENTACION" not in content:
    # Insertar al final de la clase (antes del último })
    insert = '''
    private const val KEY_ORIENTACION = "orientacion"

    /** auto | vertical | horizontal */
    fun obtenerOrientacion(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ORIENTACION, "auto") ?: "auto"

    fun guardarOrientacion(context: Context, o: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_ORIENTACION, o).apply()
    }
}
'''
    # Quitar el último } del archivo y agregar el nuevo
    content = content.rstrip()
    if content.endswith("}"):
        content = content[:-1] + insert
    with open(file_path, "w") as f:
        f.write(content)
    print("✅ Preferencia de orientación agregada")
else:
    print("ℹ️  Ya existía")
PYEOF

# ═══════════════════════════════════════════════════════════
# 4) MainActivity: aplicar orientación al arrancar
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 MainActivity: aplicando orientación..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/MainActivity.kt"
with open(file_path) as f:
    content = f.read()

# Imports
if "import android.content.pm.ActivityInfo" not in content:
    content = content.replace(
        "import android.os.Build",
        "import android.content.pm.ActivityInfo\nimport android.os.Build"
    )
if "import com.anonimus757.tvapp.data.AjustesStore" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.FirebaseManager",
        "import com.anonimus757.tvapp.data.AjustesStore\nimport com.anonimus757.tvapp.data.FirebaseManager"
    )
if "import com.anonimus757.tvapp.ui.util.DetectorDispositivo" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.*",
        "import com.anonimus757.tvapp.ui.*\nimport com.anonimus757.tvapp.ui.util.DetectorDispositivo"
    )

# Aplicar orientación al inicio de onCreate
old = '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        lifecycleScope.launch {'''

new = '''    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ═══════════════════════════════════════════════════════
        // APLICAR ORIENTACIÓN
        // TV → siempre horizontal
        // Celu/Tablet → según preferencia del usuario
        // ═══════════════════════════════════════════════════════
        try {
            if (DetectorDispositivo.esTV(this)) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                val pref = AjustesStore.obtenerOrientacion(this)
                requestedOrientation = when (pref) {
                    "vertical" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    "horizontal" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
        } catch (_: Exception) {}

        lifecycleScope.launch {'''

if old in content:
    content = content.replace(old, new)
    print("✅ Orientación aplicada en onCreate")
else:
    print("⚠️  No encontré el onCreate exacto")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 5) PlayerScreen: forzar horizontal al entrar
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 PlayerScreen: forzando horizontal en el reproductor..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Imports
if "import android.content.pm.ActivityInfo" not in content:
    content = content.replace(
        "import android.net.Uri",
        "import android.content.pm.ActivityInfo\nimport android.net.Uri"
    )
if "import com.anonimus757.tvapp.data.AjustesStore" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.Embed",
        "import com.anonimus757.tvapp.data.AjustesStore\nimport com.anonimus757.tvapp.data.Embed"
    )
if "import com.anonimus757.tvapp.ui.util.findActivity" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.theme.AppIcons",
        "import com.anonimus757.tvapp.ui.theme.AppIcons\nimport com.anonimus757.tvapp.ui.util.findActivity"
    )

# Insertar DisposableEffect de orientación después del de FLAG_KEEP_SCREEN_ON
old = '''    DisposableEffect(Unit) {
        val window = (view.context as? android.app.Activity)?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }'''

new = '''    DisposableEffect(Unit) {
        val window = (view.context as? android.app.Activity)?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // ═══════════════════════════════════════════════════════
    // FORZAR HORIZONTAL en el reproductor (solo celu/tablet)
    // Al salir, restaura la preferencia del usuario
    // ═══════════════════════════════════════════════════════
    DisposableEffect(Unit) {
        val activity = context.findActivity()
        val esTV = com.anonimus757.tvapp.ui.util.DetectorDispositivo.esTV(context)

        try {
            if (!esTV) {
                activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
        } catch (_: Exception) {}

        onDispose {
            try {
                if (!esTV) {
                    val pref = AjustesStore.obtenerOrientacion(context)
                    activity?.requestedOrientation = when (pref) {
                        "vertical" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "horizontal" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                }
            } catch (_: Exception) {}
        }
    }'''

if old in content and "FORZAR HORIZONTAL en el reproductor" not in content:
    content = content.replace(old, new, 1)
    print("✅ Forzar horizontal en PlayerScreen")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 6) AjustesScreen: nueva sección ORIENTACIÓN (solo celu)
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 AjustesScreen: agregando sección de orientación..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# Imports
if "import android.content.pm.ActivityInfo" not in content:
    content = content.replace(
        "import android.content.Context",
        "import android.content.Context\nimport android.content.pm.ActivityInfo"
    )
if "import com.anonimus757.tvapp.ui.util.findActivity" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.theme.AppIcons",
        "import com.anonimus757.tvapp.ui.theme.AppIcons\nimport com.anonimus757.tvapp.ui.util.findActivity\nimport com.anonimus757.tvapp.ui.util.rememberEsTV"
    )

# Agregar estado de orientación junto a los otros
if "var orientacion by remember" not in content:
    content = content.replace(
        "    var autoRefresh by remember { mutableStateOf(AjustesStore.obtenerAutoRefresh(context)) }",
        "    var autoRefresh by remember { mutableStateOf(AjustesStore.obtenerAutoRefresh(context)) }\n    var orientacion by remember { mutableStateOf(AjustesStore.obtenerOrientacion(context)) }\n    val esTV = rememberEsTV()"
    )
    print("✅ Estado de orientación agregado")

# Insertar la sección antes de AUTO-REFRESH
old_section = '''            Spacer(Modifier.height(32.dp))

            // Sección: AUTO-REFRESH
            SeccionTitulo(icono = AppIcons.refrescar, texto = "ACTUALIZACIÓN AUTOMÁTICA")'''

new_section = '''            // Sección: ORIENTACIÓN (solo en celu/tablet)
            if (!esTV) {
                Spacer(Modifier.height(32.dp))
                SeccionTitulo(icono = AppIcons.calidad, texto = "ORIENTACIÓN DE PANTALLA")
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OpcionOrientacion(
                        titulo = "Auto",
                        subtitulo = "Sigue al dispositivo",
                        seleccionado = orientacion == "auto",
                        onClick = {
                            orientacion = "auto"
                            AjustesStore.guardarOrientacion(context, "auto")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Vertical",
                        subtitulo = "Celular parado",
                        seleccionado = orientacion == "vertical",
                        onClick = {
                            orientacion = "vertical"
                            AjustesStore.guardarOrientacion(context, "vertical")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            } catch (_: Exception) {}
                        }
                    )
                    OpcionOrientacion(
                        titulo = "Horizontal",
                        subtitulo = "Celular acostado",
                        seleccionado = orientacion == "horizontal",
                        onClick = {
                            orientacion = "horizontal"
                            AjustesStore.guardarOrientacion(context, "horizontal")
                            try {
                                context.findActivity()?.requestedOrientation =
                                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                            } catch (_: Exception) {}
                        }
                    )
                }
            }

            Spacer(Modifier.height(32.dp))

            // Sección: AUTO-REFRESH
            SeccionTitulo(icono = AppIcons.refrescar, texto = "ACTUALIZACIÓN AUTOMÁTICA")'''

if old_section in content:
    content = content.replace(old_section, new_section, 1)
    print("✅ Sección de orientación agregada")
else:
    print("⚠️  No encontré el ancla de AUTO-REFRESH")

# Agregar composable OpcionOrientacion al final
if "private fun OpcionOrientacion" not in content:
    componente = '''

@Composable
private fun OpcionOrientacion(
    titulo: String,
    subtitulo: String,
    seleccionado: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val borderWidth by animateDpAsState(if (focused || seleccionado) 2.dp else 1.dp, tween(180), label = "oo")
    val borderColor by animateColorAsState(
        when {
            focused -> AppColors.GoldBright
            seleccionado -> AppColors.Gold
            else -> AppColors.Gold.copy(alpha = 0.25f)
        },
        tween(180), label = "ooc"
    )
    val bg by animateColorAsState(
        when {
            seleccionado -> AppColors.Gold.copy(alpha = 0.18f)
            focused -> AppColors.CardFocus
            else -> AppColors.Card
        },
        tween(180), label = "oob"
    )

    Column(
        Modifier
            .width(if (seleccionado || focused) 170.dp else 165.dp)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.04f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            titulo,
            color = if (seleccionado || focused) AppColors.GoldBright else AppColors.TextPrimary,
            fontSize = 18.sp,
            fontWeight = FontWeight.Black
        )
        Spacer(Modifier.height(2.dp))
        Text(
            subtitulo,
            color = AppColors.TextSecondary,
            fontSize = 11.sp,
            maxLines = 1
        )
        if (seleccionado) {
            Spacer(Modifier.height(6.dp))
            Icon(
                imageVector = AppIcons.ok,
                contentDescription = null,
                tint = AppColors.AccentGreen,
                modifier = Modifier.size(14.dp)
            )
        }
    }
}
'''
    content = content.rstrip() + componente + "\n"
    print("✅ Componente OpcionOrientacion agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q 'configChanges="orientation' "$MANIFEST" && echo "  ✓ Manifest con configChanges"
grep -q "KEY_ORIENTACION" "$DATA_DIR/AjustesStore.kt" && echo "  ✓ AjustesStore con orientación"
grep -q "requestedOrientation = ActivityInfo" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity aplica orientación"
grep -q "FORZAR HORIZONTAL en el reproductor" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ PlayerScreen fuerza horizontal"
grep -q "ORIENTACIÓN DE PANTALLA" "$UI_DIR/AjustesScreen.kt" && echo "  ✓ Ajustes tiene sección"

echo ""
echo "✅✅✅ Sistema de orientación completo"
echo ""
echo "📌 Cómo funciona:"
echo "   • En TV/TV Box → siempre horizontal"
echo "   • En celu/tablet → depende de la preferencia"
echo "   • Ajustes → Ajustes → ORIENTACIÓN DE PANTALLA (solo en celu)"
echo "   • Reproductor → siempre horizontal (forzado)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"