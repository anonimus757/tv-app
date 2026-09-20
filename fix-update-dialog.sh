#!/bin/bash
set -e

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
UI_DIR="$PKG_DIR/ui"

# 1) Restaurar MainActivity
if [ -f "$PKG_DIR/MainActivity.kt.bak-layout" ]; then
    cp "$PKG_DIR/MainActivity.kt.bak-layout" "$PKG_DIR/MainActivity.kt"
    echo "✅ MainActivity restaurado"
else
    echo "❌ No hay backup .bak-layout"
    exit 1
fi

# 2) Reescribir UpdateDialog usando Dialog nativo (se superpone siempre)
echo "📝 Reescribiendo UpdateDialog con Dialog nativo..."

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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.anonimus757.tvapp.ui.animations.scaleOnFocus
import com.anonimus757.tvapp.ui.theme.AppColors
import com.anonimus757.tvapp.ui.theme.AppIcons

/**
 * Diálogo de actualización — usa Dialog nativo para superponerse SIEMPRE.
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

    Dialog(
        onDismissRequest = { if (!obligatorio) onCerrar() },
        properties = DialogProperties(
            dismissOnBackPress = !obligatorio,
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
                    .width(520.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.verticalGradient(
                            listOf(AppColors.SurfaceLight, AppColors.Surface)
                        )
                    )
                    .border(2.dp, AppColors.Gold, RoundedCornerShape(24.dp))
                    .padding(32.dp)
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("🚀", fontSize = 64.sp)
                Spacer(Modifier.height(16.dp))

                Text(
                    "Nueva versión disponible",
                    color = AppColors.GoldBright,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Black
                )

                Spacer(Modifier.height(8.dp))

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

echo "✅ UpdateDialog.kt reescrito con Dialog nativo"

echo ""
echo "🔎 Verificando:"
grep -q "import androidx.compose.ui.window.Dialog" "$UI_DIR/UpdateDialog.kt" && echo "  ✓ Dialog nativo importado"
grep -q "fun UpdateDialog" "$UI_DIR/UpdateDialog.kt" && echo "  ✓ Función UpdateDialog"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "📌 El Dialog ahora se superpone SIEMPRE, sin importar el layout"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"