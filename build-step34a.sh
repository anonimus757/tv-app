#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
GRADLE_FILE="app/build.gradle.kts"

# ─────────────────────────────────────────────────────────────
# 1) Agregar dependencia material-icons-extended
# ─────────────────────────────────────────────────────────────
echo "📝 Agregando material-icons-extended al build.gradle.kts..."

if grep -q "material-icons-extended" "$GRADLE_FILE"; then
  echo "ℹ️  Ya estaba la dependencia"
else
  # Insertar después de material3
  python3 << 'PYEOF'
file_path = "app/build.gradle.kts"
with open(file_path) as f: content = f.read()

old = 'implementation("androidx.compose.material3:material3")'
new = '''implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")'''

if old in content and "material-icons-extended" not in content:
    content = content.replace(old, new)
    with open(file_path, "w") as f: f.write(content)
    print("✅ Dependencia agregada")
else:
    print("⚠️  No se agregó (ya estaba o no encontró el patrón)")
PYEOF
fi

# ─────────────────────────────────────────────────────────────
# 2) Crear AppIcons.kt (helper centralizado)
# ─────────────────────────────────────────────────────────────
echo "📝 Creando AppIcons.kt..."

mkdir -p "$PKG_DIR/ui/theme"

cat > "$PKG_DIR/ui/theme/AppIcons.kt" << 'EOF'
package com.anonimus757.tvapp.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Iconos centralizados de FutTV.
 * Todos son Material Icons (vectoriales, escalables, look profesional).
 * Reemplazan a los emojis que se veían amateur.
 *
 * Convención:
 *   - "Default." → icono relleno (para acciones activas)
 *   - "Outlined." → icono de contorno (para estados secundarios)
 *   - "Rounded."  → icono redondeado (para botones suaves)
 */
object AppIcons {

    // ── Acciones del header ────────────────────────────────
    val buscar = Icons.Default.Search
    val ajustes = Icons.Default.Settings
    val refrescar = Icons.Default.Refresh
    val cargando = Icons.Default.HourglassEmpty
    val notificaciones = Icons.Default.Notifications
    val notificacionesOff = Icons.Default.NotificationsOff

    // ── Navegación ─────────────────────────────────────────
    val volver = Icons.Default.ArrowBack
    val adelante = Icons.Default.ArrowForward
    val arriba = Icons.Default.KeyboardArrowUp
    val abajo = Icons.Default.KeyboardArrowDown
    val izquierda = Icons.Default.KeyboardArrowLeft
    val derecha = Icons.Default.KeyboardArrowRight

    // ── Reproductor ────────────────────────────────────────
    val play = Icons.Default.PlayArrow
    val pausa = Icons.Default.Pause
    val detener = Icons.Default.Stop
    val volumen = Icons.Default.VolumeUp
    val volumenBajo = Icons.Default.VolumeDown
    val volumenMudo = Icons.Default.VolumeOff
    val pantallaCompleta = Icons.Default.Fullscreen
    val pantallaNormal = Icons.Default.FullscreenExit
    val cast = Icons.Default.Cast

    // ── Info del evento ────────────────────────────────────
    val reloj = Icons.Default.Schedule
    val calendario = Icons.Default.CalendarToday
    val tv = Icons.Default.Tv
    val canales = Icons.Default.LiveTv
    val senal = Icons.Default.Sensors
    val wifi = Icons.Default.Wifi
    val estrella = Icons.Default.Star
    val estrellaBorde = Icons.Default.StarBorder
    val enVivo = Icons.Default.Circle
    val destacado = Icons.Default.Whatshot
    val megafono = Icons.Default.Campaign
    val categoria = Icons.Default.Category

    // ── Estados ────────────────────────────────────────────
    val ok = Icons.Default.Check
    val okCirculo = Icons.Default.CheckCircle
    val error = Icons.Default.ErrorOutline
    val advertencia = Icons.Default.Warning
    val info = Icons.Default.Info
    val bloqueado = Icons.Default.Lock
    val sinConexion = Icons.Default.CloudOff

    // ── Listas / Vacíos ────────────────────────────────────
    val bandeja = Icons.Default.Inbox
    val sinResultados = Icons.Default.SearchOff
    val carpeta = Icons.Default.FolderOpen
    val lista = Icons.Default.ListAlt

    // ── Ajustes ────────────────────────────────────────────
    val calidad = Icons.Default.HighQuality
    val hd = Icons.Default.Hd
    val sd = Icons.Default.Sd
    val cache = Icons.Default.CleaningServices
    val borrar = Icons.Default.Delete
    val datos = Icons.Default.Storage
    val idioma = Icons.Default.Language
    val version = Icons.Default.Info

    // ── Extras ─────────────────────────────────────────────
    val cerrar = Icons.Default.Close
    val agregar = Icons.Default.Add
    val editar = Icons.Default.Edit
    val compartir = Icons.Default.Share
    val favorito = Icons.Default.Favorite
    val favoritoBorde = Icons.Default.FavoriteBorder
    val rayo = Icons.Default.Bolt
    val tendencia = Icons.Default.TrendingUp
    val grafico = Icons.Default.BarChart
    val filtro = Icons.Default.FilterList
    val orden = Icons.Default.Sort
    val buscarLupa = Icons.Default.ManageSearch
    val catalogo = Icons.Default.VideoLibrary
    val pelicula = Icons.Default.Movie
    val trofeo = Icons.Default.EmojiEvents
    val pelota = Icons.Default.SportsSoccer
    val grupos = Icons.Default.Groups
    val mas = Icons.Default.MoreVert
    val menu = Icons.Default.Menu
    val expandir = Icons.Default.ExpandMore
    val colapsar = Icons.Default.ExpandLess

    // ── Iconos outlined (secundarios) ──────────────────────
    val settingsOutlined = Icons.Outlined.Settings
    val searchOutlined = Icons.Outlined.Search
    val refreshOutlined = Icons.Outlined.Refresh

    // ── Iconos rounded (suaves) ────────────────────────────
    val playRounded = Icons.Rounded.PlayArrow
    val starRounded = Icons.Rounded.Star
    val favoriteRounded = Icons.Rounded.Favorite
}
EOF

# ─────────────────────────────────────────────────────────────
# 3) Reescribir SplashScreen.kt (con Box real para la rayita)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo SplashScreen.kt..."

cat > "$PKG_DIR/ui/SplashScreen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.anonimus757.tvapp.ui.theme.AppColors
import kotlinx.coroutines.delay

@Composable
fun SplashScreen(onTerminado: () -> Unit) {
    var visible by remember { mutableStateOf(false) }
    var saliendo by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        delay(100)
        visible = true
        delay(1400)
        saliendo = true
        delay(400)
        onTerminado()
    }

    val alpha by animateFloatAsState(
        targetValue = if (saliendo) 0f else if (visible) 1f else 0f,
        animationSpec = tween(if (saliendo) 400 else 600),
        label = "splashAlpha"
    )
    val scale by animateFloatAsState(
        targetValue = if (visible && !saliendo) 1f else 0.85f,
        animationSpec = tween(700),
        label = "splashScale"
    )

    // Glow pulsante en el logo
    val transition = rememberInfiniteTransition(label = "glow")
    val glow by transition.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "glowPulse"
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(AppColors.Background, Color(0xFF0A0A0A), AppColors.Background)
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.alpha(alpha).scale(scale)
        ) {
            // Logo (pelota emoji como marca de FutTV)
            Text(
                "⚽",
                fontSize = 90.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(16.dp))
            Text(
                "FutTV",
                color = AppColors.GoldBright,
                fontSize = 56.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 6.sp,
                modifier = Modifier.alpha(glow)
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "EN VIVO · IPTV PREMIUM",
                color = AppColors.TextSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 3.sp
            )
            Spacer(Modifier.height(40.dp))
            // Línea dorada decorativa (reemplaza el Box con Brush)
            Box(
                Modifier
                    .width(90.dp)
                    .height(2.dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(
                        Brush.horizontalGradient(
                            listOf(Color.Transparent, AppColors.Gold, Color.Transparent)
                        )
                    )
            )
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 4) Verificación
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando:"
grep -q "material-icons-extended" "$GRADLE_FILE" && echo "  ✓ Dependencia en gradle"
[ -f "$PKG_DIR/ui/theme/AppIcons.kt" ] && echo "  ✓ AppIcons.kt creado"
grep -q "val buscar = Icons.Default.Search" "$PKG_DIR/ui/theme/AppIcons.kt" && echo "  ✓ Iconos centralizados"
[ -f "$PKG_DIR/ui/SplashScreen.kt" ] && echo "  ✓ SplashScreen.kt actualizado"

echo ""
echo "✅✅✅ Paso 34a completo — Dependencia + AppIcons + Splash"
echo ""
echo "📌 Qué viene:"
echo "   ✅ material-icons-extended en Gradle"
echo "   ✅ AppIcons.kt con +80 iconos centralizados"
echo "   ✅ SplashScreen mejorado (marca + glow)"
echo "   ⏭️  34b: HomeScreen con iconos Material"
echo ""
echo "🚀 Compilá (va a tardar más por la nueva dep):"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"