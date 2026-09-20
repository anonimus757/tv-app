#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
UTIL_DIR="app/src/main/java/com/anonimus757/tvapp/ui/util"
mkdir -p "$UTIL_DIR"

echo "📝 Creando DetectorDispositivo.kt..."

cat > "$UTIL_DIR/DetectorDispositivo.kt" << 'EOF'
package com.anonimus757.tvapp.ui.util

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

/**
 * Detecta si el dispositivo es TV o Celu/Tablet.
 * Se usa para ajustar el tamaño de cards, animaciones y layouts.
 */
object DetectorDispositivo {

    /**
     * True si estamos en Android TV o TV Box.
     * Detecta por:
     *   1. Feature "android.software.leanback"
     *   2. Feature "android.hardware.touchscreen" (si NO tiene touch = TV)
     */
    fun esTV(context: Context): Boolean {
        val pm = context.packageManager
        val tieneLeanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val tieneTouch = pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        return tieneLeanback || !tieneTouch
    }

    /**
     * True si estamos en un celu o tablet.
     */
    fun esCelu(context: Context): Boolean = !esTV(context)
}

/**
 * Composable que recuerda si es TV o no durante toda la sesión.
 * Uso: val esTV = rememberEsTV()
 */
@Composable
fun rememberEsTV(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        DetectorDispositivo.esTV(context)
    }
}
EOF

echo "✅ DetectorDispositivo.kt creado"

# ═══════════════════════════════════════════════════════════
# 1) Coil configurado pro (Application class)
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Creando FutTVApp.kt (para configurar Coil)..."

cat > "app/src/main/java/com/anonimus757/tvapp/FutTVApp.kt" << 'EOF'
package com.anonimus757.tvapp

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache

/**
 * Application class para configurar Coil (carga de imágenes).
 *
 * Coil se usa para todos los logos e imágenes de eventos.
 * Configurado con cache de memoria y disco optimizados.
 */
class FutTVApp : Application(), ImageLoaderFactory {

    override fun newImageLoader(): ImageLoader {
        return ImageLoader.Builder(this)
            .memoryCache {
                MemoryCache.Builder(this)
                    .maxSizePercent(0.20)  // 20% de la RAM para cache
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("image_cache"))
                    .maxSizeBytes(50 * 1024 * 1024)  // 50 MB en disco
                    .build()
            }
            .crossfade(true)  // Transición suave al cargar
            .crossfade(200)   // 200ms
            .respectCacheHeaders(false)  // Siempre respetar cache
            .build()
    }
}
EOF

echo "✅ FutTVApp.kt creado"

# ═══════════════════════════════════════════════════════════
# 2) AndroidManifest: usar FutTVApp
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Actualizando AndroidManifest para usar FutTVApp..."

MANIFEST="app/src/main/AndroidManifest.xml"
cp "$MANIFEST" "$MANIFEST.bak-fase2"

python3 << 'PYEOF'
file_path = "app/src/main/AndroidManifest.xml"
with open(file_path) as f:
    content = f.read()

# Agregar android:name=".FutTVApp" a <application>
if 'android:name=".FutTVApp"' not in content:
    content = content.replace(
        '<application\n        android:allowBackup="true"',
        '<application\n        android:name=".FutTVApp"\n        android:allowBackup="true"'
    )
    print("✅ android:name agregado al manifest")
else:
    print("ℹ️  Ya estaba")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 3) HomeScreen: adaptación TV vs Celu
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Adaptación TV vs Celu en HomeScreen..."

cp "$UI_DIR/HomeScreen.kt" "$UI_DIR/HomeScreen.kt.bak-fase2"

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Import del detector
if "import com.anonimus757.tvapp.ui.util.rememberEsTV" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.ui.theme.AppIcons",
        "import com.anonimus757.tvapp.ui.theme.AppIcons\nimport com.anonimus757.tvapp.ui.util.rememberEsTV"
    )
    print("✅ Import del detector agregado")

# Agregar detección al inicio del ContenidoHome
if "val esTV = rememberEsTV()" not in content:
    # Insertar en ContenidoHome (donde están los eventos)
    ancla = "    val fbOrdenados = remember(eventosFirebase) { eventosFirebase.sortedBy { horaAMinutos(it.hora) } }"
    if ancla in content:
        content = content.replace(
            ancla,
            "    val esTV = rememberEsTV()\n" + ancla,
            1
        )
        print("✅ Detección TV/Celu agregada")

# Modificar tamaño de cards según dispositivo
# En EventoCardPremium: width(320.dp) → width si esTV 360.dp, sino 260.dp
old_width = '''    Column(
        Modifier
            .width(320.dp)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)'''
new_width = '''    val esTV = rememberEsTV()
    val anchoCard = if (esTV) 360.dp else 260.dp
    val altoCard = if (esTV) 220.dp else 170.dp

    Column(
        Modifier
            .width(anchoCard)
            .scaleOnFocus(isFocused = focused, focusedScale = 1.05f)'''

if old_width in content:
    content = content.replace(old_width, new_width, 1)
    print("✅ Tamaño de card adaptativo")

# Modificar alto de la imagen dentro de la card
old_img = '''        Box(
            Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
        ) {'''
new_img = '''        Box(
            Modifier.fillMaxWidth().height(altoCard).clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
        ) {'''

if old_img in content:
    content = content.replace(old_img, new_img, 1)
    print("✅ Alto de imagen adaptativo")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$UTIL_DIR/DetectorDispositivo.kt" ] && echo "  ✓ DetectorDispositivo.kt"
[ -f "app/src/main/java/com/anonimus757/tvapp/FutTVApp.kt" ] && echo "  ✓ FutTVApp.kt (Coil)"
grep -q 'android:name=".FutTVApp"' "$MANIFEST" && echo "  ✓ Manifest con FutTVApp"
grep -q "rememberEsTV" "$UI_DIR/HomeScreen.kt" && echo "  ✓ HomeScreen adaptativo"

echo ""
echo "✅✅✅ FASE 2b completo — Modo TV/Celu + Coil optimizado"
echo ""
echo "📌 Qué hace:"
echo "   • Detecta si es TV o Celu"
echo "   • Cards más grandes en TV (360dp) y más chicas en celu (260dp)"
echo "   • Coil con cache de 20% RAM + 50MB disco"
echo "   • Crossfade de 200ms al cargar imágenes"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"