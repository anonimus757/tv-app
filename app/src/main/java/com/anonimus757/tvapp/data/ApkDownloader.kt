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
