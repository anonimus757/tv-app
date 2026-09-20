#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
UI_DIR="$PKG_DIR/ui"
DATA_DIR="$PKG_DIR/data"

# ═══════════════════════════════════════════════════════════
# 1) Subir versionName y versionCode en build.gradle.kts
# ═══════════════════════════════════════════════════════════
echo "📝 Actualizando versión en build.gradle.kts..."

GRADLE="app/build.gradle.kts"
cp "$GRADLE" "$GRADLE.bak-v2"

if grep -q 'versionName = "1.0"' "$GRADLE"; then
    sed -i 's/versionName = "1.0"/versionName = "2.0"/' "$GRADLE"
fi
if grep -q 'versionCode = 1' "$GRADLE"; then
    sed -i 's/versionCode = 1/versionCode = 3/' "$GRADLE"
elif grep -q 'versionCode = 2' "$GRADLE"; then
    sed -i 's/versionCode = 2/versionCode = 3/' "$GRADLE"
fi
grep -E "versionCode|versionName" "$GRADLE" | head -3

# ═══════════════════════════════════════════════════════════
# 2) Extender RemoteConfigRepository con campos de versión
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Extendiendo RemoteConfigRepository..."

cp "$DATA_DIR/RemoteConfigRepository.kt" "$DATA_DIR/RemoteConfigRepository.kt.bak-v2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
with open(file_path) as f:
    content = f.read()

# 2a) Extender AppConfig
old_config = '''data class AppConfig(
    val minutosAutoRefresh: Int = 20,
    val calidadPreferida: String = "auto",     // auto | sd | hd
    val textoBienvenida: String = "⚽ FutTV · En vivo",
    val mensajeSistema: String = "",            // si tiene texto, se muestra banner
    val mostrarHero: Boolean = true,
    val maxReintentosCanal: Int = 3,
    val modoFirebasePrimario: Boolean = true,
    val mostrarScraping: Boolean = true,
    val agendasExternas: List<AgendaExterna> = emptyList()
)'''

new_config = '''data class AppConfig(
    val minutosAutoRefresh: Int = 20,
    val calidadPreferida: String = "auto",     // auto | sd | hd
    val textoBienvenida: String = "⚽ FutTV · En vivo",
    val mensajeSistema: String = "",            // si tiene texto, se muestra banner
    val mostrarHero: Boolean = true,
    val maxReintentosCanal: Int = 3,
    val modoFirebasePrimario: Boolean = true,
    val mostrarScraping: Boolean = true,
    val agendasExternas: List<AgendaExterna> = emptyList(),
    // 🆕 Auto-update
    val versionActual: String = "2.0",           // Última versión publicada
    val versionMinima: String = "1.0",           // Versión mínima soportada
    val urlDescarga: String = "",                // Link de descarga del APK
    val notasVersion: String = "",               // Notas de la versión
    // 🆕 Soporte
    val telegramUrl: String = "https://t.me/futtvsoporte"
)'''

if old_config in content:
    content = content.replace(old_config, new_config)
    print("✅ AppConfig extendido")

# 2b) Extender parsearConfig
old_parse = '''        return AppConfig(
            minutosAutoRefresh = (data["minutosAutoRefresh"] as? Number)?.toInt() ?: 20,
            calidadPreferida = data["calidadPreferida"] as? String ?: "auto",
            textoBienvenida = data["textoBienvenida"] as? String ?: "⚽ FutTV · En vivo",
            mensajeSistema = data["mensajeSistema"] as? String ?: "",
            mostrarHero = data["mostrarHero"] as? Boolean ?: true,
            maxReintentosCanal = (data["maxReintentosCanal"] as? Number)?.toInt() ?: 3,
            modoFirebasePrimario = data["modoFirebasePrimario"] as? Boolean ?: true,
            mostrarScraping = data["mostrarScraping"] as? Boolean ?: true,
            agendasExternas = agendas
        )'''

new_parse = '''        return AppConfig(
            minutosAutoRefresh = (data["minutosAutoRefresh"] as? Number)?.toInt() ?: 20,
            calidadPreferida = data["calidadPreferida"] as? String ?: "auto",
            textoBienvenida = data["textoBienvenida"] as? String ?: "⚽ FutTV · En vivo",
            mensajeSistema = data["mensajeSistema"] as? String ?: "",
            mostrarHero = data["mostrarHero"] as? Boolean ?: true,
            maxReintentosCanal = (data["maxReintentosCanal"] as? Number)?.toInt() ?: 3,
            modoFirebasePrimario = data["modoFirebasePrimario"] as? Boolean ?: true,
            mostrarScraping = data["mostrarScraping"] as? Boolean ?: true,
            agendasExternas = agendas,
            versionActual = data["versionActual"] as? String ?: "2.0",
            versionMinima = data["versionMinima"] as? String ?: "1.0",
            urlDescarga = data["urlDescarga"] as? String ?: "",
            notasVersion = data["notasVersion"] as? String ?: "",
            telegramUrl = data["telegramUrl"] as? String ?: "https://t.me/futtvsoporte"
        )'''

if old_parse in content:
    content = content.replace(old_parse, new_parse)
    print("✅ parsearConfig extendido")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) Crear VersionChecker.kt
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Creando VersionChecker.kt..."

cat > "$DATA_DIR/VersionChecker.kt" << 'EOF'
package com.anonimus757.tvapp.data

import com.anonimus757.tvapp.BuildConfig

/**
 * Compara la versión actual de la app con la versión publicada en Firestore.
 * Si hay una nueva → el usuario recibe un cartel para actualizar.
 */
object VersionChecker {

    /**
     * Compara dos versiones tipo "2.0" o "2.1.3".
     * Devuelve:
     *   -1 → v1 < v2 (hay update)
     *    0 → v1 == v2 (igual)
     *    1 → v1 > v2 (la app es más nueva)
     */
    fun comparar(v1: String, v2: String): Int {
        val partes1 = v1.split(".").map { it.toIntOrNull() ?: 0 }
        val partes2 = v2.split(".").map { it.toIntOrNull() ?: 0 }
        val max = maxOf(partes1.size, partes2.size)

        for (i in 0 until max) {
            val a = partes1.getOrElse(i) { 0 }
            val b = partes2.getOrElse(i) { 0 }
            if (a < b) return -1
            if (a > b) return 1
        }
        return 0
    }

    /**
     * Devuelve true si hay una versión nueva disponible.
     */
    fun hayUpdate(config: AppConfig): Boolean {
        val versionLocal = BuildConfig.VERSION_NAME
        return comparar(versionLocal, config.versionActual) < 0
    }

    /**
     * Devuelve true si la versión local está por debajo de la mínima soportada.
     * En ese caso, el update es OBLIGATORIO.
     */
    fun updateObligatorio(config: AppConfig): Boolean {
        val versionLocal = BuildConfig.VERSION_NAME
        return comparar(versionLocal, config.versionMinima) < 0
    }

    /**
     * Devuelve la versión local de la app.
     */
    fun versionLocal(): String = BuildConfig.VERSION_NAME
}
EOF

echo "✅ VersionChecker.kt creado"

# ═══════════════════════════════════════════════════════════
# 4) Crear UpdateDialog.kt
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Creando UpdateDialog.kt..."

cat > "$UI_DIR/UpdateDialog.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

/**
 * Diálogo que aparece cuando hay una nueva versión de la app.
 */
@Composable
fun UpdateDialog(
    versionNueva: String,
    notasVersion: String,
    urlDescarga: String,
    obligatorio: Boolean,
    onCerrar: () -> Unit
) {
    val context = LocalContext.current

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xDD000000))
            .clickable(enabled = !obligatorio) { onCerrar() },
        contentAlignment = Alignment.Center
    ) {
        Column(
            Modifier
                .width(520.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(
                    Brush.verticalGradient(
                        listOf(AppColors.SurfaceLight, AppColors.Surface)
                    )
                )
                .border(2.dp, AppColors.Gold, RoundedCornerShape(24.dp))
                .clickable(enabled = false) {}
                .padding(32.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Icono de cohete
            Text("🚀", fontSize = 64.sp)
            Spacer(Modifier.height(16.dp))

            // Título
            Text(
                "Nueva versión disponible",
                color = AppColors.GoldBright,
                fontSize = 24.sp,
                fontWeight = FontWeight.Black
            )

            Spacer(Modifier.height(8.dp))

            // Versión
            Text(
                "v$versionNueva",
                color = AppColors.TextSecondary,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold
            )

            if (notasVersion.isNotBlank()) {
                Spacer(Modifier.height(20.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0x33D4AF37))
                        .padding(16.dp)
                ) {
                    Column {
                        Text(
                            "¿Qué hay nuevo?",
                            color = AppColors.Gold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = 1.sp
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            notasVersion,
                            color = AppColors.TextPrimary,
                            fontSize = 14.sp,
                            lineHeight = 20.sp
                        )
                    }
                }
            }

            if (obligatorio) {
                Spacer(Modifier.height(16.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color(0x33EF4444))
                        .padding(12.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = AppIcons.advertencia,
                            contentDescription = null,
                            tint = Color(0xFFEF4444),
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "Esta actualización es obligatoria",
                            color = Color(0xFFEF4444),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            Spacer(Modifier.height(28.dp))

            // Botón Actualizar
            BotonUpdate(
                texto = "Actualizar ahora",
                esPrimario = true,
                onClick = {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlDescarga))
                        context.startActivity(intent)
                    } catch (_: Exception) {}
                }
            )

            if (!obligatorio) {
                Spacer(Modifier.height(12.dp))
                BotonUpdate(
                    texto = "Después",
                    esPrimario = false,
                    onClick = onCerrar
                )
            }
        }
    }
}

@Composable
private fun BotonUpdate(
    texto: String,
    esPrimario: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val bg = when {
        esPrimario && focused -> AppColors.GoldBright
        esPrimario -> AppColors.Gold
        focused -> AppColors.CardFocus
        else -> AppColors.Surface
    }
    val color = when {
        esPrimario -> Color.Black
        focused -> AppColors.GoldBright
        else -> AppColors.TextSecondary
    }

    Box(
        Modifier
            .fillMaxWidth()
            .scaleOnFocus(isFocused = focused, focusedScale = 1.02f)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(14.dp))
            .background(bg)
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else Color.Transparent,
                RoundedCornerShape(14.dp)
            )
            .clickable { onClick() }
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            texto,
            color = color,
            fontSize = 16.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 1.sp
        )
    }
}
EOF

echo "✅ UpdateDialog.kt creado"

# ═══════════════════════════════════════════════════════════
# 5) Inyectar UpdateDialog en MainActivity
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Integrando UpdateDialog en MainActivity..."

cp "$PKG_DIR/MainActivity.kt" "$PKG_DIR/MainActivity.kt.bak-v2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/MainActivity.kt"
with open(file_path) as f:
    content = f.read()

# 5a) Imports
if "import com.anonimus757.tvapp.data.VersionChecker" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.RemoteConfigRepository",
        "import com.anonimus757.tvapp.data.RemoteConfigRepository\nimport com.anonimus757.tvapp.data.VersionChecker"
    )
if "import com.anonimus757.tvapp.data.AppConfig" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.VersionChecker",
        "import com.anonimus757.tvapp.data.AppConfig\nimport com.anonimus757.tvapp.data.VersionChecker"
    )

# 5b) Inyectar la lógica de update en el setContent
old_when = '''            var mostrarSplash by remember { mutableStateOf(true) }
            var screen by remember { mutableStateOf<Screen>(Screen.Home) }'''

new_when = '''            var mostrarSplash by remember { mutableStateOf(true) }
            var screen by remember { mutableStateOf<Screen>(Screen.Home) }

            // 🆕 Auto-update: chequea versión cada vez que arranca
            val config by com.anonimus757.tvapp.data.RemoteConfigRepository.config.collectAsState()
            var mostrarUpdate by remember { mutableStateOf(false) }
            var notasVersion by remember { mutableStateOf("") }
            var versionNueva by remember { mutableStateOf("") }
            var updateObligatorio by remember { mutableStateOf(false) }
            var urlDescarga by remember { mutableStateOf("") }

            LaunchedEffect(config, mostrarSplash) {
                // Solo chequear cuando terminó el splash
                if (!mostrarSplash && VersionChecker.hayUpdate(config)) {
                    versionNueva = config.versionActual
                    notasVersion = config.notasVersion
                    urlDescarga = config.urlDescarga.ifBlank {
                        "https://github.com/anonimus757/tv-app/releases/latest"
                    }
                    updateObligatorio = VersionChecker.updateObligatorio(config)
                    mostrarUpdate = true
                }
            }'''

if old_when in content:
    content = content.replace(old_when, new_when)
    print("✅ Lógica de update agregada en MainActivity")

# 5c) Mostrar el diálogo al final (antes del cierre del setContent)
old_close = '''            if (mostrarSplash) {
                SplashScreen(onTerminado = { mostrarSplash = false })
            } else {'''

new_close = '''            if (mostrarUpdate) {
                com.anonimus757.tvapp.ui.UpdateDialog(
                    versionNueva = versionNueva,
                    notasVersion = notasVersion,
                    urlDescarga = urlDescarga,
                    obligatorio = updateObligatorio,
                    onCerrar = { mostrarUpdate = false }
                )
            }

            if (mostrarSplash) {
                SplashScreen(onTerminado = { mostrarSplash = false })
            } else {'''

if old_close in content:
    content = content.replace(old_close, new_close)
    print("✅ Diálogo integrado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 6) Botón de Telegram en Ajustes
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Agregando botón de Telegram en Ajustes..."

cp "$UI_DIR/AjustesScreen.kt" "$UI_DIR/AjustesScreen.kt.bak-v2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# 6a) Imports
if "import android.content.Intent" not in content:
    content = content.replace(
        "import android.content.Context",
        "import android.content.Context\nimport android.content.Intent\nimport android.net.Uri"
    )

# 6b) Sección de soporte ANTES de la sección INFO
old_seccion = '''            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")'''

new_seccion = '''            // Sección: SOPORTE
            SeccionTitulo(icono = AppIcons.grupos, texto = "SOPORTE")
            Spacer(Modifier.height(12.dp))
            FilaAccion(
                icono = AppIcons.grupos,
                titulo = "Comunidad en Telegram",
                subtitulo = "Ayuda, soporte y novedades · t.me/futtvsoporte",
                onClick = {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/futtvsoporte"))
                        context.startActivity(intent)
                    } catch (_: Exception) {}
                }
            )

            Spacer(Modifier.height(32.dp))

            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")'''

if old_seccion in content:
    content = content.replace(old_seccion, new_seccion)
    print("✅ Sección Soporte con botón Telegram")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -E "versionName|versionCode" "$GRADLE" | head -3
grep -q "versionActual" "$DATA_DIR/RemoteConfigRepository.kt" && echo "  ✓ RemoteConfig con versión"
[ -f "$DATA_DIR/VersionChecker.kt" ] && echo "  ✓ VersionChecker.kt"
[ -f "$UI_DIR/UpdateDialog.kt" ] && echo "  ✓ UpdateDialog.kt"
grep -q "VersionChecker.hayUpdate" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity chequea update"
grep -q "t.me/futtvsoporte" "$UI_DIR/AjustesScreen.kt" && echo "  ✓ Telegram en Ajustes"

echo ""
echo "✅✅✅ v2.0 CIERRE completo"
echo ""
echo "📌 Qué ganamos:"
echo "   🚀 Auto-update (con diálogo bonito)"
echo "   🚀 Update obligatorio/opcional configurable"
echo "   📱 Botón de Telegram en Ajustes"
echo "   🔢 versionName = 2.0, versionCode = 3"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"