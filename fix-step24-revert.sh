#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
DATA_DIR="$PKG_DIR/data"
NOTIF_DIR="$PKG_DIR/notifications"
UI_DIR="$PKG_DIR/ui"

echo "🧹 Revirtiendo Paso 24 (recordatorios custom)..."

# ─────────────────────────────────────────────────────────────
# 1) Borrar archivos exclusivos del Paso 24
# ─────────────────────────────────────────────────────────────
echo "🗑  Borrando archivos del Paso 24..."
rm -f "$DATA_DIR/Recordatorio.kt"
rm -f "$DATA_DIR/RecordatoriosStore.kt"
rm -f "$NOTIF_DIR/RecordatorioScheduler.kt"
rm -f "$UI_DIR/RecordatorioDialog.kt"
rm -f "$UI_DIR/MisRecordatoriosScreen.kt"

# ─────────────────────────────────────────────────────────────
# 2) Restaurar HomeScreen y EventDetailScreen desde .bak
# ─────────────────────────────────────────────────────────────
if [ -f "$UI_DIR/HomeScreen.kt.bak" ]; then
  mv "$UI_DIR/HomeScreen.kt.bak" "$UI_DIR/HomeScreen.kt"
  echo "✅ HomeScreen.kt restaurado desde .bak (estado Paso 23)"
else
  echo "ℹ️  No hay HomeScreen.kt.bak — asumo que el 24 no se corrió"
fi

if [ -f "$UI_DIR/EventDetailScreen.kt.bak" ]; then
  mv "$UI_DIR/EventDetailScreen.kt.bak" "$UI_DIR/EventDetailScreen.kt"
  echo "✅ EventDetailScreen.kt restaurado desde .bak (estado Paso 23)"
else
  echo "ℹ️  No hay EventDetailScreen.kt.bak — asumo que el 24 no se corrió"
fi

# ─────────────────────────────────────────────────────────────
# 3) Reescribir Screen.kt (sin MisRecordatorios)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo Screen.kt..."

cat > "$UI_DIR/Screen.kt" << 'EOF'
package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen
    data class Detail(val evento: Evento, val todos: List<Evento>, val volverA: VolverA) : Screen
    data class Player(val evento: Evento, val embed: Embed, val todos: List<Evento>) : Screen
}

enum class VolverA { Home, Player }
EOF

# ─────────────────────────────────────────────────────────────
# 4) Reescribir MainActivity.kt (estado Paso 23)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo MainActivity.kt..."

cat > "$PKG_DIR/MainActivity.kt" << 'EOF'
package com.anonimus757.tvapp

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.anonimus757.tvapp.notifications.NotificationHelper
import com.anonimus757.tvapp.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PedirPermisoNotificaciones()

            var screen by remember { mutableStateOf<Screen>(Screen.Home) }

            when (val s = screen) {
                is Screen.Home -> HomeScreen(
                    onEventoClick = { evento, todos ->
                        screen = Screen.Detail(evento, todos, VolverA.Home)
                    }
                )

                is Screen.Detail -> EventDetailScreen(
                    evento = s.evento,
                    onCanalClick = { embed ->
                        screen = Screen.Player(s.evento, embed, s.todos)
                    },
                    onBack = {
                        screen = when (s.volverA) {
                            VolverA.Home -> Screen.Home
                            VolverA.Player -> Screen.Player(s.evento, s.evento.embeds.first(), s.todos)
                        }
                    }
                )

                is Screen.Player -> {
                    key(s.evento.descripcion + "|" + s.embed.url) {
                        PlayerScreen(
                            evento = s.evento,
                            embedInicial = s.embed,
                            todosEventos = s.todos,
                            onBack = { screen = Screen.Home },
                            onEventoChange = { nuevo ->
                                screen = Screen.Detail(nuevo, s.todos, VolverA.Player)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PedirPermisoNotificaciones() {
    val context = LocalContext.current

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    LaunchedEffect(Unit) {
        NotificationHelper.crearCanales(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!NotificationHelper.tienePermiso(context)) {
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 5) Verificar que quedó todo consistente
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando estado final:"

# Deben existir (notis automáticas del 23)
[ -f "$NOTIF_DIR/NotificationHelper.kt" ] && echo "  ✓ NotificationHelper.kt (notis automáticas)"
[ -f "$NOTIF_DIR/EventNotifWorker.kt" ] && echo "  ✓ EventNotifWorker.kt (notis automáticas)"
[ -f "$NOTIF_DIR/EventNotifScheduler.kt" ] && echo "  ✓ EventNotifScheduler.kt (notis automáticas)"

# NO deben existir (revertidos del 24)
[ ! -f "$DATA_DIR/Recordatorio.kt" ] && echo "  ✓ Recordatorio.kt borrado"
[ ! -f "$DATA_DIR/RecordatoriosStore.kt" ] && echo "  ✓ RecordatoriosStore.kt borrado"
[ ! -f "$NOTIF_DIR/RecordatorioScheduler.kt" ] && echo "  ✓ RecordatorioScheduler.kt borrado"
[ ! -f "$UI_DIR/RecordatorioDialog.kt" ] && echo "  ✓ RecordatorioDialog.kt borrado"
[ ! -f "$UI_DIR/MisRecordatoriosScreen.kt" ] && echo "  ✓ MisRecordatoriosScreen.kt borrado"

# No deben quedar referencias a nada del 24
if grep -rq "MisRecordatorios\|RecordatorioScheduler\|RecordatoriosStore" "$PKG_DIR" 2>/dev/null; then
  echo ""
  echo "⚠️  Todavía hay referencias al Paso 24:"
  grep -rln "MisRecordatorios\|RecordatorioScheduler\|RecordatoriosStore" "$PKG_DIR" 2>/dev/null
  echo "   Avisame y lo limpiamos."
else
  echo "  ✓ Cero referencias al Paso 24 en el código"
fi

echo ""
echo "✅✅✅ Revert del Paso 24 completo"
echo ""
echo "📌 Estado actual:"
echo "   - Notis automáticas: ✅ 10 min antes + al inicio (Paso 23)"
echo "   - Recordatorios custom: ❌ removidos (como pediste)"
echo "   - Todo lo demás: intacto"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"