package com.anonimus757.tvapp.notifications

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe push de Firebase Cloud Messaging.
 * Cuando vos mandás una notif desde Firebase Console (o Cloud Function),
 * esto la recibe y la muestra usando NotificationHelper.
 */
class FcmService : FirebaseMessagingService() {

    private val TAG = "FcmService"

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "📩 Push recibido: ${message.data} / ${message.notification?.title}")

        val titulo = message.notification?.title
            ?: message.data["titulo"]
            ?: "FutTV"
        val cuerpo = message.notification?.body
            ?: message.data["mensaje"]
            ?: ""
        val canal = message.data["canal"] ?: NotificationHelper.CANAL_EVENTOS

        // ID único para no pisar notifs (usa timestamp)
        val id = (System.currentTimeMillis() and 0x7FFFFFFF).toInt()

        NotificationHelper.notificar(
            context = applicationContext,
            id = id,
            titulo = titulo,
            mensaje = cuerpo,
            canal = canal
        )
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔔 Nuevo FCM token: ${token.take(20)}...")
        // El token se obtiene también desde FirebaseManager.init() al arrancar.
        // Aquí podríamos guardarlo en Firestore si quisiéramos enviar a usuarios específicos.
    }
}
