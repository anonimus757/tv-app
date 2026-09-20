#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
FILE="$UI_DIR/AjustesScreen.kt"

cp "$FILE" "$FILE.bak-version"

echo "📝 Agregando sección de versión + update..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/AjustesScreen.kt"
with open(file_path) as f:
    content = f.read()

# Imports necesarios
if "import androidx.compose.material3.CircularProgressIndicator" not in content:
    content = content.replace(
        "import androidx.compose.material3.Text",
        "import androidx.compose.material3.CircularProgressIndicator\nimport androidx.compose.material3.Text"
    )

if "import com.anonimus757.tvapp.data.ApkDownloader" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.AjustesStore",
        "import com.anonimus757.tvapp.data.AjustesStore\nimport com.anonimus757.tvapp.data.ApkDownloader"
    )
if "import com.anonimus757.tvapp.data.RemoteConfigRepository" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.ApkDownloader",
        "import com.anonimus757.tvapp.data.ApkDownloader\nimport com.anonimus757.tvapp.data.RemoteConfigRepository"
    )
if "import com.anonimus757.tvapp.data.VersionChecker" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.RemoteConfigRepository",
        "import com.anonimus757.tvapp.data.RemoteConfigRepository\nimport com.anonimus757.tvapp.data.VersionChecker"
    )

# Agregar estados al inicio del composable
if "val config by RemoteConfigRepository.config.collectAsState()" not in content:
    content = content.replace(
        "    val esTV = rememberEsTV()",
        """    val esTV = rememberEsTV()
    // 🆕 Estado de versión + update
    val config by RemoteConfigRepository.config.collectAsState()
    val estadoDescarga by ApkDownloader.estado.collectAsState()
    val hayUpdate = VersionChecker.hayUpdate(config)"""
    )
    print("✅ Estados agregados")

# Insertar la sección ANTES de "Sección: INFO"
old_info = '''            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")
            Spacer(Modifier.height(12.dp))
            FilaInfo("Versión", "v${BuildConfig.VERSION_NAME}")
            Spacer(Modifier.height(8.dp))
            FilaInfo("Desarrollador", "FutTV")'''

new_info = '''            // Sección: ACTUALIZACIÓN
            SeccionTitulo(icono = AppIcons.refrescar, texto = "ACTUALIZACIÓN")
            Spacer(Modifier.height(12.dp))

            // Card de estado de versión
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(
                        if (hayUpdate) AppColors.Gold.copy(alpha = 0.12f)
                        else AppColors.AccentGreen.copy(alpha = 0.10f)
                    )
                    .border(
                        1.dp,
                        if (hayUpdate) AppColors.Gold.copy(alpha = 0.5f)
                        else AppColors.AccentGreen.copy(alpha = 0.5f),
                        RoundedCornerShape(14.dp)
                    )
                    .padding(16.dp)
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = if (hayUpdate) AppIcons.refrescar else AppIcons.okCirculo,
                            contentDescription = null,
                            tint = if (hayUpdate) AppColors.GoldBright else AppColors.AccentGreen,
                            modifier = Modifier.size(22.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            if (hayUpdate) "Nueva versión disponible" else "Estás al día",
                            color = if (hayUpdate) AppColors.GoldBright else AppColors.AccentGreen,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Versión instalada: ${BuildConfig.VERSION_NAME}",
                        color = AppColors.TextPrimary,
                        fontSize = 13.sp
                    )
                    if (hayUpdate) {
                        Spacer(Modifier.height(2.dp))
                        Text(
                            "Última versión: ${config.versionActual}",
                            color = AppColors.Gold,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )

                        if (config.notasVersion.isNotBlank()) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                config.notasVersion,
                                color = AppColors.TextSecondary,
                                fontSize = 12.sp,
                                lineHeight = 16.sp
                            )
                        }

                        Spacer(Modifier.height(14.dp))

                        // Estado de la descarga
                        when {
                            estadoDescarga.descargando -> {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    CircularProgressIndicator(
                                        color = AppColors.GoldBright,
                                        strokeWidth = 2.dp,
                                        modifier = Modifier.size(20.dp),
                                        progress = { estadoDescarga.progreso / 100f }
                                    )
                                    Spacer(Modifier.width(10.dp))
                                    Text(
                                        "Descargando ${estadoDescarga.progreso}%",
                                        color = AppColors.GoldBright,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }
                            estadoDescarga.error != null -> {
                                Column {
                                    Text(
                                        "❌ ${estadoDescarga.error}",
                                        color = Color(0xFFEF4444),
                                        fontSize = 12.sp
                                    )
                                    Spacer(Modifier.height(8.dp))
                                    BotonDescargarVersion(
                                        texto = "Reintentar",
                                        onClick = {
                                            ApkDownloader.reset()
                                            ApkDownloader.descargar(context, config.urlDescarga, config.versionActual)
                                        }
                                    )
                                }
                            }
                            estadoDescarga.listoParaInstalar -> {
                                BotonDescargarVersion(
                                    texto = "Instalar ahora",
                                    onClick = {
                                        ApkDownloader.instalar(context, config.versionActual)
                                    }
                                )
                            }
                            else -> {
                                BotonDescargarVersion(
                                    texto = "Actualizar ahora",
                                    onClick = {
                                        ApkDownloader.descargar(context, config.urlDescarga, config.versionActual)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(32.dp))

            // Sección: INFO
            SeccionTitulo(icono = AppIcons.info, texto = "INFORMACIÓN")
            Spacer(Modifier.height(12.dp))
            FilaInfo("Versión", "v${BuildConfig.VERSION_NAME}")
            Spacer(Modifier.height(8.dp))
            FilaInfo("Desarrollador", "FutTV")'''

if old_info in content:
    content = content.replace(old_info, new_info, 1)
    print("✅ Sección de actualización agregada")
else:
    print("⚠️  No encontré la sección INFO exacta")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# Agregar composable BotonDescargarVersion al final
cat >> "$FILE" << 'EOF'


// ═══════════════════════════════════════════════════════════
// 🆕 Botón de descarga desde Ajustes (sin abrir navegador)
// ═══════════════════════════════════════════════════════════
@Composable
private fun BotonDescargarVersion(texto: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }

    Row(
        Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) AppColors.GoldBright else AppColors.Gold)
            .border(
                2.dp,
                if (focused) AppColors.GoldBright else Color.Transparent,
                RoundedCornerShape(10.dp)
            )
            .clickable { onClick() }
            .padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = AppIcons.play,
            contentDescription = null,
            tint = Color.Black,
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            texto,
            color = Color.Black,
            fontSize = 14.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp
        )
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -q "ACTUALIZACIÓN" "$FILE" && echo "  ✓ Sección agregada"
grep -q "BotonDescargarVersion" "$FILE" && echo "  ✓ Botón de descarga"
grep -q "VersionChecker.hayUpdate" "$FILE" && echo "  ✓ Detecta update"

echo ""
echo "✅✅✅ Sección de versión en Ajustes lista"
echo ""
echo "📌 Qué va a mostrar:"
echo "   • Si estás al día → verde ✅"
echo "   • Si hay update → dorado con versión nueva"
echo "   • Botón de descarga interna (sin salir a la web)"
echo "   • Progress bar mientras descarga"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"