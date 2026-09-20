#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
DATA_DIR="$PKG_DIR/data"
UI_DIR="$PKG_DIR/ui"
MANIFEST="app/src/main/AndroidManifest.xml"

echo "💾 Backups..."
cp "$UI_DIR/HomeScreen.kt" "$UI_DIR/HomeScreen.kt.bak-v31"
cp "$UI_DIR/UpdateDialog.kt" "$UI_DIR/UpdateDialog.kt.bak-v31"
cp "$MANIFEST" "$MANIFEST.bak-v31"
echo "✅ Backups creados"

# ═══════════════════════════════════════════════════════════
# 1) ApkDownloader.kt (descarga interna)
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Creando ApkDownloader.kt..."

cat > "$DATA_DIR/ApkDownloader.kt" << 'EOF'
package com.anonimus757.tvapp.data

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/**
 * Descarga el APK de la nueva versión usando DownloadManager de Android.
 * Al terminar → abre el instalador automáticamente.
 */
object ApkDownloader {

    private const val TAG = "ApkDownloader"

    data class Estado(
        val descargando: Boolean = false,
        val progreso: Int = 0,
        val error: String? = null,
        val listoParaInstalar: Boolean = false
    )

    private val _estado = MutableStateFlow(Estado())
    val estado: StateFlow<Estado> = _estado.asStateFlow()

    private var downloadId: Long = -1L

    /** Inicia la descarga del APK. */
    fun descargar(context: Context, urlApk: String, version: String) {
        try {
            _estado.value = Estado(descargando = true, progreso = 0)

            val nombreArchivo = "FutTV-v$version.apk"

            // Limpiar archivo anterior si existe
            val archivoDestino = File(
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                nombreArchivo
            )
            if (archivoDestino.exists()) archivoDestino.delete()

            val request = DownloadManager.Request(Uri.parse(urlApk))
                .setTitle("FutTV v$version")
                .setDescription("Descargando actualización...")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setDestinationInExternalFilesDir(
                    context,
                    Environment.DIRECTORY_DOWNLOADS,
                    nombreArchivo
                )
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)

            val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            downloadId = dm.enqueue(request)

            // Registrar receiver para cuando termine
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: -1L
                    if (id == downloadId) {
                        try {
                            _estado.value = Estado(descargando = false, progreso = 100, listoParaInstalar = true)
                            ctx?.unregisterReceiver(this)
                        } catch (_: Exception) {}
                    }
                }
            }

            context.registerReceiver(
                receiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
                Context.RECEIVER_EXPORTED
            )

            // Monitor de progreso en background
            Thread {
                val dm2 = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                var terminado = false
                while (!terminado) {
                    try {
                        Thread.sleep(500)
                        val query = DownloadManager.Query().setFilterById(downloadId)
                        val cursor = dm2.query(query)
                        if (cursor != null && cursor.moveToFirst()) {
                            val bytesDescargados = cursor.getLong(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                            )
                            val bytesTotal = cursor.getLong(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                            )
                            val status = cursor.getInt(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                            )
                            val progreso = if (bytesTotal > 0) {
                                ((bytesDescargados * 100) / bytesTotal).toInt()
                            } else 0

                            _estado.value = _estado.value.copy(progreso = progreso)

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                _estado.value = _estado.value.copy(
                                    descargando = false,
                                    progreso = 100,
                                    listoParaInstalar = true
                                )
                                terminado = true
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                _estado.value = _estado.value.copy(
                                    descargando = false,
                                    error = "Descarga fallida"
                                )
                                terminado = true
                            }
                        }
                        cursor?.close()
                    } catch (_: Exception) {
                        terminado = true
                    }
                }
            }.start()

        } catch (e: Exception) {
            Log.e(TAG, "Error iniciando descarga: ${e.message}")
            _estado.value = Estado(descargando = false, error = e.message)
        }
    }

    /** Abre el instalador de Android con el APK descargado. */
    fun instalar(context: Context, version: String) {
        try {
            val nombreArchivo = "FutTV-v$version.apk"
            val archivo = File(
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                nombreArchivo
            )
            if (!archivo.exists()) {
                _estado.value = Estado(error = "El APK no se descargó bien")
                return
            }

            // Android 8+: pedir permiso "Instalar apps desconocidas"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!context.packageManager.canRequestPackageInstalls()) {
                    val intentPermiso = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .setData(Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intentPermiso)
                    return
                }
            }

            // Abrir instalador
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                archivo
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            context.startActivity(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Error instalando: ${e.message}")
            _estado.value = Estado(error = e.message)
        }
    }

    fun reset() {
        _estado.value = Estado()
    }
}
EOF

echo "✅ ApkDownloader.kt creado"

# ═══════════════════════════════════════════════════════════
# 2) AndroidManifest: permiso + FileProvider
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Actualizando AndroidManifest (permiso + FileProvider)..."

python3 << 'PYEOF'
file_path = "app/src/main/AndroidManifest.xml"
with open(file_path) as f:
    content = f.read()

# Permiso REQUEST_INSTALL_PACKAGES
if "REQUEST_INSTALL_PACKAGES" not in content:
    content = content.replace(
        '<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />',
        '<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
    )
    print("✅ Permiso REQUEST_INSTALL_PACKAGES")

# FileProvider
if "androidx.core.content.FileProvider" not in content:
    # Insertar antes del cierre de </application>
    file_provider = '''
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>

    </application>'''

    content = content.replace("    </application>", file_provider)
    print("✅ FileProvider agregado")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# Crear archivo de paths
echo ""
echo "📝 Creando res/xml/file_paths.xml..."
mkdir -p "app/src/main/res/xml"
cat > "app/src/main/res/xml/file_paths.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-files-path name="downloads" path="Download/" />
    <files-path name="files" path="." />
    <cache-path name="cache" path="." />
</paths>
EOF
echo "✅ file_paths.xml creado"

# ═══════════════════════════════════════════════════════════
# 3) UpdateDialog: usar ApkDownloader + ancho adaptativo
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Reescribiendo UpdateDialog con descarga interna..."

cat > "$UI_DIR/UpdateDialog.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.anonimus757.tvapp.data.ApkDownloader
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

@Composable
fun UpdateDialog(
    versionNueva: String,
    notasVersion: String,
    urlDescarga: String,
    obligatorio: Boolean,
    onCerrar: () -> Unit
) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val esVertical = configuration.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT

    // Ancho adaptativo: en vertical → casi full, en horizontal → 520dp
    val anchoDialog = if (esVertical) {
        configuration.screenWidthDp.dp - 32.dp
    } else {
        520.dp
    }

    // Estado de la descarga
    val estadoDescarga by ApkDownloader.estado.collectAsState()

    // Al terminar de descargar → abrir instalador automáticamente
    LaunchedEffect(estadoDescarga.listoParaInstalar) {
        if (estadoDescarga.listoParaInstalar) {
            ApkDownloader.instalar(context, versionNueva)
        }
    }

    Dialog(
        onDismissRequest = { if (!obligatorio && !estadoDescarga.descargando) onCerrar() },
        properties = DialogProperties(
            dismissOnBackPress = !obligatorio && !estadoDescarga.descargando,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false
        )
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color(0xDD000000)),
            contentAlignment = Alignment.Center
        ) {
            Column(
                Modifier
                    .width(anchoDialog)
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.verticalGradient(
                            listOf(AppColors.SurfaceLight, AppColors.Surface)
                        )
                    )
                    .border(2.dp, AppColors.Gold, RoundedCornerShape(24.dp))
                    .padding(if (esVertical) 24.dp else 32.dp)
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("🚀", fontSize = if (esVertical) 52.sp else 64.sp)
                Spacer(Modifier.height(if (esVertical) 10.dp else 16.dp))

                Text(
                    "Nueva versión disponible",
                    color = AppColors.GoldBright,
                    fontSize = if (esVertical) 20.sp else 24.sp,
                    fontWeight = FontWeight.Black,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )

                Spacer(Modifier.height(6.dp))

                Text(
                    "v$versionNueva",
                    color = AppColors.TextSecondary,
                    fontSize = if (esVertical) 14.sp else 16.sp,
                    fontWeight = FontWeight.Bold
                )

                if (notasVersion.isNotBlank()) {
                    Spacer(Modifier.height(if (esVertical) 16.dp else 20.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color(0x33D4AF37))
                            .padding(if (esVertical) 12.dp else 16.dp)
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
                                fontSize = if (esVertical) 13.sp else 14.sp,
                                lineHeight = 20.sp
                            )
                        }
                    }
                }

                if (obligatorio) {
                    Spacer(Modifier.height(14.dp))
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
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Esta actualización es obligatoria",
                                color = Color(0xFFEF4444),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }

                Spacer(Modifier.height(if (esVertical) 20.dp else 28.dp))

                // Si está descargando → mostrar progreso
                if (estadoDescarga.descargando) {
                    CircularProgressIndicator(
                        color = AppColors.GoldBright,
                        strokeWidth = 3.dp,
                        modifier = Modifier.size(48.dp),
                        progress = { estadoDescarga.progreso / 100f }
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Descargando... ${estadoDescarga.progreso}%",
                        color = AppColors.GoldBright,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                } else if (estadoDescarga.error != null) {
                    Text(
                        "❌ ${estadoDescarga.error}",
                        color = Color(0xFFEF4444),
                        fontSize = 13.sp
                    )
                    Spacer(Modifier.height(12.dp))
                    BotonUpdate(
                        texto = "Reintentar",
                        esPrimario = true,
                        onClick = {
                            ApkDownloader.reset()
                            ApkDownloader.descargar(context, urlDescarga, versionNueva)
                        }
                    )
                } else if (estadoDescarga.listoParaInstalar) {
                    Text(
                        "✅ Descarga completa",
                        color = Color(0xFF4ADE80),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(12.dp))
                    BotonUpdate(
                        texto = "Instalar ahora",
                        esPrimario = true,
                        onClick = { ApkDownloader.instalar(context, versionNueva) }
                    )
                } else {
                    BotonUpdate(
                        texto = "Actualizar ahora",
                        esPrimario = true,
                        onClick = {
                            ApkDownloader.descargar(context, urlDescarga, versionNueva)
                        }
                    )

                    if (!obligatorio) {
                        Spacer(Modifier.height(12.dp))
                        BotonUpdate(
                            texto = "Después",
                            esPrimario = false,
                            onClick = {
                                ApkDownloader.reset()
                                onCerrar()
                            }
                        )
                    }
                }
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

echo "✅ UpdateDialog reescrito con descarga interna"

# ═══════════════════════════════════════════════════════════
# 4) HomeScreen: cards adaptativas en vertical
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Adaptando HomeScreen al modo vertical..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(file_path) as f:
    content = f.read()

# Import de LocalConfiguration
if "import androidx.compose.ui.platform.LocalConfiguration" not in content:
    content = content.replace(
        "import androidx.compose.ui.platform.LocalContext",
        "import androidx.compose.ui.platform.LocalConfiguration\nimport androidx.compose.ui.platform.LocalContext"
    )

# Modificar EventoCardPremium para detectar orientación
old_firma = '''@Composable
private fun EventoCardPremium(ev: Evento, enVivo: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "cc"
    )

    val esTV = rememberEsTV()
    val anchoCard = if (esTV) 360.dp else 260.dp
    val altoCard = if (esTV) 220.dp else 170.dp'''

new_firma = '''@Composable
private fun EventoCardPremium(ev: Evento, enVivo: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(if (focused) 3.dp else 1.dp, tween(180), label = "cw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "cc"
    )

    val esTV = rememberEsTV()
    val config = LocalConfiguration.current
    val esVertical = config.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT && !esTV

    // Si es vertical (celu en modo parado) → card horizontal compacta
    if (esVertical) {
        EventoCardVerticalCompacta(ev, enVivo, focused, { focused = it }, onClick)
        return
    }

    val anchoCard = if (esTV) 360.dp else 260.dp
    val altoCard = if (esTV) 220.dp else 170.dp'''

if old_firma in content:
    content = content.replace(old_firma, new_firma, 1)
    print("✅ EventoCardPremium detecta vertical")

# Agregar composable EventoCardVerticalCompacta al final
if "EventoCardVerticalCompacta" not in content:
    componente_vertical = '''

// ═══════════════════════════════════════════════════════════
// 🆕 CARD VERTICAL COMPACTA (celu en modo parado)
// Estilo lista: imagen a la izquierda, info a la derecha
// ═══════════════════════════════════════════════════════════
@Composable
private fun EventoCardVerticalCompacta(
    ev: Evento,
    enVivo: Boolean,
    focused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    onClick: () -> Unit
) {
    val color = AppColors.fuenteColor(ev.groupTitle)
    val pulse = rememberPulseAlpha(min = 0.5f, max = 1f, durationMs = 800)

    val borderWidth by animateDpAsState(if (focused) 2.dp else 1.dp, tween(180), label = "vcbw")
    val borderColor by animateColorAsState(
        if (focused) AppColors.GoldBright else color.copy(alpha = 0.3f),
        tween(180), label = "vcbc"
    )

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .onFocusChanged { onFocusChange(it.isFocused) }
            .focusable()
            .clickable { onClick() }
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) AppColors.CardFocus else AppColors.Card)
            .border(borderWidth, borderColor, RoundedCornerShape(12.dp))
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Imagen a la izquierda
        Box(
            Modifier
                .size(width = 80.dp, height = 80.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Brush.verticalGradient(listOf(AppColors.SurfaceLight, AppColors.Surface))),
            contentAlignment = Alignment.Center
        ) {
            if (ev.imagen.isNotBlank()) {
                AsyncImage(
                    model = ev.imagen,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(60.dp)
                )
            } else {
                Text("⚽", fontSize = 36.sp)
            }

            // Badge LIVE
            if (enVivo || (FechaHelper.esHoy(ev.fecha) && estaEnVivo(ev.hora))) {
                Box(
                    Modifier.align(Alignment.TopEnd).padding(4.dp).alpha(pulse)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color(0xFFEF4444))
                        .padding(horizontal = 4.dp, vertical = 1.dp)
                ) {
                    Text("LIVE", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                }
            }
        }

        Spacer(Modifier.width(12.dp))

        // Info a la derecha
        Column(Modifier.weight(1f)) {
            Text(
                ev.descripcion,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 18.sp
            )
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(5.dp))
                Text(
                    FechaHelper.badgeCard(ev.fecha, ev.hora),
                    color = AppColors.GoldBright,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.width(8.dp))
                Text("·", color = AppColors.TextMuted, fontSize = 11.sp)
                Spacer(Modifier.width(8.dp))
                Text("${ev.embeds.size} canales", color = AppColors.TextSecondary, fontSize = 11.sp)
            }
        }

        Icon(
            imageVector = if (focused) AppIcons.play else AppIcons.adelante,
            contentDescription = null,
            tint = if (focused) AppColors.GoldBright else AppColors.TextMuted,
            modifier = Modifier.size(18.dp)
        )
    }
}
'''
    content = content.rstrip() + componente_vertical + "\n"
    print("✅ EventoCardVerticalCompacta agregada")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
[ -f "$DATA_DIR/ApkDownloader.kt" ] && echo "  ✓ ApkDownloader.kt"
grep -q "REQUEST_INSTALL_PACKAGES" "$MANIFEST" && echo "  ✓ Permiso install packages"
grep -q "FileProvider" "$MANIFEST" && echo "  ✓ FileProvider"
[ -f "app/src/main/res/xml/file_paths.xml" ] && echo "  ✓ file_paths.xml"
grep -q "ApkDownloader" "$UI_DIR/UpdateDialog.kt" && echo "  ✓ UpdateDialog usa descarga interna"
grep -q "EventoCardVerticalCompacta" "$UI_DIR/HomeScreen.kt" && echo "  ✓ Home vertical adaptativo"

echo ""
echo "✅✅✅ v3.1 completa"
echo ""
echo "📌 Qué ganamos:"
echo "   📱 Home adaptativo en vertical (cards compactas tipo lista)"
echo "   📥 Descarga interna del APK (sin abrir navegador)"
echo "   🔄 Progress bar en el diálogo de update"
echo "   ✅ Instalación automática al terminar la descarga"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"