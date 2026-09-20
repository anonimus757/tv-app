package com.anonimus757.tvapp.data

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.ktx.auth
import com.google.firebase.ktx.Firebase
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.tasks.await

/**
 * Encargado de inicializar Firebase en la app.
 * - Login anónimo (para poder leer Firestore sin pedir cuenta al user)
 * - Obtener token FCM (para recibir push)
 *
 * Se llama una vez al arrancar MainActivity.
 */
object FirebaseManager {

    private const val TAG = "FirebaseManager"

    @Volatile
    var inicializado: Boolean = false
        private set

    @Volatile
    var fcmToken: String? = null
        private set

    /** Inicializa Firebase. Idempotente: si ya se inicializó, no hace nada. */
    suspend fun init() {
        if (inicializado) return
        try {
            loginAnonimo()
            obtenerTokenFcm()
            suscribirseAlTopic()
            inicializado = true
            Log.d(TAG, "✅ Firebase inicializado")
            DebugLog.log("✅ Firebase init OK")
        } catch (e: Exception) {
            Log.e(TAG, "❌ init fail: ${e.message}")
            DebugLog.log("❌ Firebase init fail: ${e.message}")
        }
    }

    private suspend fun loginAnonimo() {
        val auth: FirebaseAuth = Firebase.auth
        if (auth.currentUser != null) {
            Log.d(TAG, "👤 Ya había sesión: ${auth.currentUser?.uid?.take(8)}...")
            return
        }
        try {
            val result = auth.signInAnonymously().await()
            Log.d(TAG, "✅ Login anónimo OK: ${result.user?.uid?.take(8)}...")
            DebugLog.log("✅ Login OK: ${result.user?.uid?.take(8)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Login anónimo fail: ${e.message}")
            DebugLog.log("❌ Login fail: ${e.message}")
        }
    }

    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
            DebugLog.log("🔔 FCM token OK")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }

    private suspend fun suscribirseAlTopic() {
        try {
            FirebaseMessaging.getInstance().subscribeToTopic("futtv_todos").await()
            Log.d(TAG, "✅ Suscripto al topic futtv_todos")
            DebugLog.log("✅ Suscripto a notificaciones")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Subscribe topic fail: ${e.message}")
            DebugLog.log("❌ Subscribe topic fail: ${e.message}")
        }
    }
}
