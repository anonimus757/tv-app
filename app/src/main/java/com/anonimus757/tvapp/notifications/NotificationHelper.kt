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
