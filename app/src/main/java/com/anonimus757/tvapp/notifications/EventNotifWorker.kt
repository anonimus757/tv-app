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
