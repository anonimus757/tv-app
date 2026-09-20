#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
NOTIF_DIR="$PKG_DIR/notifications"
mkdir -p "$NOTIF_DIR"

# ─────────────────────────────────────────────────────────────
# 1) Reescribir NotificationHelper.kt (agrego PendingIntent para
#    que al tocar la notif abra la app)
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo NotificationHelper.kt con PendingIntent..."

cat > "$NOTIF_DIR/NotificationHelper.kt" << 'EOF'
package com.anonimus757.tvapp.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Helper central para TODO lo de notificaciones en FutTV.
 */
object NotificationHelper {

    const val CANAL_EVENTOS = "futtv_eventos"
    const val CANAL_CUSTOM = "futtv_custom"

    /** Crea los canales de notificación. Idempotente. */
    fun crearCanales(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val canalEventos = NotificationChannel(
            CANAL_EVENTOS,
            "Eventos en vivo",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Avisos 10 min antes y al inicio de cada evento"
            enableVibration(true)
            enableLights(true)
        }
        nm.createNotificationChannel(canalEventos)

        val canalCustom = NotificationChannel(
            CANAL_CUSTOM,
            "Recordatorios personalizados",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Avisos que vos mismo programás"
        }
        nm.createNotificationChannel(canalCustom)
    }

    /** Chequea permiso runtime (Android 13+). En versiones anteriores, true. */
    fun tienePermiso(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Envía una notificación simple. Al tocarla abre MainActivity.
     * @param id ID único (hash del evento + tipo).
     */
    fun notificar(
        context: Context,
        id: Int,
        titulo: String,
        mensaje: String,
        canal: String = CANAL_EVENTOS
    ) {
        if (!tienePermiso(context)) return

        // PendingIntent: al tocar la notif abre la app
        val intent = Intent().apply {
            setClassName(context.packageName, "com.anonimus757.tvapp.MainActivity")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, canal)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(titulo)
            .setContentText(mensaje)
            .setStyle(NotificationCompat.BigTextStyle().bigText(mensaje))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pending)
            .setAutoCancel(true)

        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) {
            // Permiso denegado entre el chequeo y el notify — no crasheamos
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 2) Crear EventNotifWorker.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando EventNotifWorker.kt..."

cat > "$NOTIF_DIR/EventNotifWorker.kt" << 'EOF'
package com.anonimus757.tvapp.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Worker que envía una notificación cuando WorkManager lo despierta.
 * Recibe los datos por inputData (id, titulo, mensaje, canal).
 * Es genérico: sirve tanto para "10 min antes" como para "en vivo".
 */
class EventNotifWorker(
    ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val id = inputData.getInt("id", 0)
        val titulo = inputData.getString("titulo") ?: return Result.failure()
        val mensaje = inputData.getString("mensaje") ?: ""
        val canal = inputData.getString("canal") ?: NotificationHelper.CANAL_EVENTOS

        NotificationHelper.notificar(applicationContext, id, titulo, mensaje, canal)
        return Result.success()
    }

    companion object {
        const val KEY_ID = "id"
        const val KEY_TITULO = "titulo"
        const val KEY_MENSAJE = "mensaje"
        const val KEY_CANAL = "canal"
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 3) Crear EventNotifScheduler.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando EventNotifScheduler.kt..."

cat > "$NOTIF_DIR/EventNotifScheduler.kt" << 'EOF'
package com.anonimus757.tvapp.notifications

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.anonimus757.tvapp.data.Evento
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Agenda notificaciones de eventos.
 *
 * Por cada evento se agendan (si el horario todavía no pasó):
 *   1) Notif "⏰ En 10 min: <evento>"
 *   2) Notif "🔴 EN VIVO: <evento>"
 *
 * Estrategia: en cada carga de eventos, cancelamos TODO lo agendado
 * (tag "futtv_evento") y re-agendamos limpio. Así no se acumulan
 * duplicados de días anteriores.
 */
object EventNotifScheduler {

    private const val TAG_EVENTOS = "futtv_evento"

    /** Convierte "20:30", "Hoy 20:30", "20:30 hs" → minutos desde 00:00. */
    private fun horaAMinutos(hora: String): Int? {
        val m = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return null
        val h = m.groupValues[1].toIntOrNull() ?: return null
        val min = m.groupValues[2].toIntOrNull() ?: return null
        if (h !in 0..23 || min !in 0..59) return null
        return h * 60 + min
    }

    /** Devuelve el timestamp (millis) de hoy a esa hora. */
    private fun timestampHoy(minutosDelDia: Int): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, minutosDelDia / 60)
        cal.set(Calendar.MINUTE, minutosDelDia % 60)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /**
     * Cancela todo lo agendado y re-agenda según la lista de eventos.
     * Llamar cada vez que se cargan eventos en el Home.
     */
    fun reagendar(context: Context, eventos: List<Evento>) {
        val wm = WorkManager.getInstance(context)
        wm.cancelAllWorkByTag(TAG_EVENTOS)

        val ahora = System.currentTimeMillis()

        eventos.forEach { ev ->
            val min = horaAMinutos(ev.hora) ?: return@forEach
            val tsEvento = timestampHoy(min)
            val ts10Antes = tsEvento - 10L * 60L * 1000L

            // id base del evento. Se usa para el id de notificación y unique name.
            // Uso AND 0x7FFFFFFF para asegurar positivo (Android acepta negativo,
            // pero por claridad lo dejo positivo).
            val idBase = ((ev.descripcion + "|" + ev.fuente).hashCode()) and 0x7FFFFFFF

            if (ts10Antes > ahora) {
                agendar(
                    context = context,
                    cuando = ts10Antes,
                    titulo = "⏰ En 10 min: ${ev.descripcion}",
                    mensaje = "${ev.hora} · ${ev.fuente} · ${ev.groupTitle}",
                    id = idBase,
                    uniqueName = "futtv_antes_$idBase"
                )
            }
            if (tsEvento > ahora) {
                agendar(
                    context = context,
                    cuando = tsEvento,
                    titulo = "🔴 EN VIVO: ${ev.descripcion}",
                    mensaje = "${ev.hora} · ${ev.fuente} · ${ev.groupTitle}",
                    id = idBase xor 0x1000, // evita colisión con "antes"
                    uniqueName = "futtv_inicio_$idBase"
                )
            }
        }
    }

    private fun agendar(
        context: Context,
        cuando: Long,
        titulo: String,
        mensaje: String,
        id: Int,
        uniqueName: String
    ) {
        val delayMs = cuando - System.currentTimeMillis()
        if (delayMs <= 0) return

        val data = Data.Builder()
            .putInt(EventNotifWorker.KEY_ID, id)
            .putString(EventNotifWorker.KEY_TITULO, titulo)
            .putString(EventNotifWorker.KEY_MENSAJE, mensaje)
            .putString(EventNotifWorker.KEY_CANAL, NotificationHelper.CANAL_EVENTOS)
            .build()

        val req = OneTimeWorkRequestBuilder<EventNotifWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(TAG_EVENTOS)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueName,
            ExistingWorkPolicy.REPLACE,
            req
        )
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 4) Reescribir MainActivity.kt con pedido de permiso
# ─────────────────────────────────────────────────────────────
echo "📝 Reescribiendo MainActivity.kt con pedido de permiso..."

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
            // Paso 23: crear canales + pedir permiso de notificaciones (1 vez)
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

/**
 * Crea los canales de notificación y pide el permiso runtime (Android 13+).
 * En Android < 13 no hace nada porque el permiso no existe.
 */
@Composable
private fun PedirPermisoNotificaciones() {
    val context = LocalContext.current

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* sin acción: si acepta, se activa; si no, no pasa nada */ }

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
# 5) HomeScreen.kt: insertar agendado tras cargar eventos
# ─────────────────────────────────────────────────────────────
echo "📝 Insertando agendado en HomeScreen.kt..."

HOME_FILE="$PKG_DIR/ui/HomeScreen.kt"

if [ ! -f "$HOME_FILE" ]; then
  echo "❌ No encuentro $HOME_FILE"
  exit 1
fi

# Backup por si hay que revertir
cp "$HOME_FILE" "$HOME_FILE.bak"

# 5a) Agregar import de EventNotifScheduler si no está
if ! grep -q "EventNotifScheduler" "$HOME_FILE"; then
  # Inserto el import después del último import existente
  perl -0777 -i -pe 's/(import com\.anonimus757\.tvapp\.data\.Evento\n)/$1import com.anonimus757.tvapp.notifications.EventNotifScheduler\n/' "$HOME_FILE"
fi

# 5b) Capturar context dentro de HomeScreen (antes del LaunchedEffect)
if ! grep -q "val context = androidx.compose.ui.platform.LocalContext.current" "$HOME_FILE"; then
  perl -0777 -i -pe 's/(fun HomeScreen\(onEventoClick: \(Evento, List<Evento>\) -> Unit\) \{\n)/$1    val context = androidx.compose.ui.platform.LocalContext.current\n/' "$HOME_FILE"
fi

# 5c) Llamar al scheduler después de "cargando = false"
if ! grep -q "EventNotifScheduler.reagendar" "$HOME_FILE"; then
  perl -0777 -i -pe 's/(\n(\s*)cargando = false\n)/\n$2cargando = false\n$2\/\/ Paso 23: agendar notificaciones de este lote de eventos\n$2try { EventNotifScheduler.reagendar(context, eventos) } catch (_: Exception) {}\n/' "$HOME_FILE"
fi

# ─────────────────────────────────────────────────────────────
# 6) Verificación
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando:"
[ -f "$NOTIF_DIR/NotificationHelper.kt" ] && echo "  ✓ NotificationHelper.kt"
[ -f "$NOTIF_DIR/EventNotifWorker.kt" ] && echo "  ✓ EventNotifWorker.kt"
[ -f "$NOTIF_DIR/EventNotifScheduler.kt" ] && echo "  ✓ EventNotifScheduler.kt"
grep -q "PedirPermisoNotificaciones" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity pide permiso"
grep -q "EventNotifScheduler.reagendar" "$HOME_FILE" && echo "  ✓ HomeScreen agenda eventos"
grep -q "import com.anonimus757.tvapp.notifications.EventNotifScheduler" "$HOME_FILE" && echo "  ✓ Import insertado en HomeScreen"

echo ""
echo "✅✅✅ Paso 23 completo — auto-notificaciones 10 min antes + en vivo"
echo ""
echo "📌 Qué hace ahora la app:"
echo "   1. Al abrir, pide permiso de notifs (Android 13+)"
echo "   2. Cada vez que carga eventos, agenda 2 notifs por evento"
echo "   3. Notifs se cancelan y re-agendan limpias en cada carga"
echo "   4. Al tocar la notif, abre la app"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"