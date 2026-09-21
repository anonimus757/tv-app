package com.anonimus757.tvapp.data

import android.content.Context
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ktx.firestore
import com.google.firebase.ktx.Firebase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/**
 * Configuración remota leída desde Firestore (doc: config/app).
 * Fallback: si no hay internet, usa la última config guardada en SharedPreferences.
 *
 * Se actualiza automáticamente en tiempo real (snapshotListener).
 */
data class AppConfig(
    val minutosAutoRefresh: Int = 20,
    val calidadPreferida: String = "auto",     // auto | sd | hd
    val textoBienvenida: String = "⚽ FutTV · En vivo",
    val mensajeSistema: String = "",            // si tiene texto, se muestra banner
    val mostrarHero: Boolean = true,
    val maxReintentosCanal: Int = 3,
    val modoFirebasePrimario: Boolean = true,
    val mostrarScraping: Boolean = true,
    val agendasExternas: List<AgendaExterna> = emptyList(),
    // 🆕 Auto-update
    val versionActual: String = "2.0",           // Última versión publicada
    val versionMinima: String = "1.0",           // Versión mínima soportada
    val urlDescarga: String = "",                // Link de descarga del APK
    val notasVersion: String = "",               // Notas de la versión
    // 🆕 Soporte
    val telegramUrl: String = "https://t.me/futtvsoporte",
    // 🆕 API-Sports (Firestore: config/app → apiSportsKey)
    val apiSportsKey: String = ""
)

data class AgendaExterna(
    val id: String = "",
    val nombre: String = "",
    val activa: Boolean = true
)

object RemoteConfigRepository {

    private const val TAG = "RemoteConfig"
    private const val PREFS = "futtv_config"
    private const val KEY_JSON = "config_json"

    private val _config = MutableStateFlow(AppConfig())
    val config: StateFlow<AppConfig> = _config.asStateFlow()

    private var listenerRegistrado = false

    /** Arranca el listener en tiempo real + carga caché local como fallback inmediato. */
    fun iniciar(context: Context) {
        // 1) Cargar caché local primero (rápido, sin internet)
        cargarCacheLocal(context)

        // 2) Registrar listener en tiempo real de Firestore
        if (listenerRegistrado) return
        listenerRegistrado = true

        try {
            val db: FirebaseFirestore = Firebase.firestore
            db.collection("config").document("app")
                .addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        Log.w(TAG, "⚠️ snapshot error: ${error.message}")
                        return@addSnapshotListener
                    }
                    if (snapshot != null && snapshot.exists()) {
                        val cfg = parsearConfig(snapshot.data ?: emptyMap())
                        _config.value = cfg
                        guardarCacheLocal(context, cfg)
                        // 🆕 Propagar API key al repositorio de API-Sports
                        try {
                            ApiSportsRepository.setApiKey(cfg.apiSportsKey)
                            Log.d(TAG, "🔑 apiSportsKey propagada (${if (cfg.apiSportsKey.isBlank()) "VACÍA" else "OK"})")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ setApiKey fail: ${e.message}")
                        }
                        Log.d(TAG, "✅ Config actualizada desde Firestore")
                    } else {
                        Log.d(TAG, "ℹ️ No existe config/app todavía (usando default)")
                    }
                }
        } catch (e: Exception) {
            Log.e(TAG, "❌ iniciar listener fail: ${e.message}")
        }
    }

    private fun parsearConfig(data: Map<String, Any?>): AppConfig {
        @Suppress("UNCHECKED_CAST")
        val agendasRaw = data["agendasExternas"] as? List<Map<String, Any?>> ?: emptyList()
        val agendas = agendasRaw.map { m ->
            AgendaExterna(
                id = m["id"] as? String ?: "",
                nombre = m["nombre"] as? String ?: "",
                activa = m["activa"] as? Boolean ?: true
            )
        }
        return AppConfig(
            minutosAutoRefresh = (data["minutosAutoRefresh"] as? Number)?.toInt() ?: 20,
            calidadPreferida = data["calidadPreferida"] as? String ?: "auto",
            textoBienvenida = data["textoBienvenida"] as? String ?: "⚽ FutTV · En vivo",
            mensajeSistema = data["mensajeSistema"] as? String ?: "",
            mostrarHero = data["mostrarHero"] as? Boolean ?: true,
            maxReintentosCanal = (data["maxReintentosCanal"] as? Number)?.toInt() ?: 3,
            modoFirebasePrimario = data["modoFirebasePrimario"] as? Boolean ?: true,
            mostrarScraping = data["mostrarScraping"] as? Boolean ?: true,
            agendasExternas = agendas,
            versionActual = data["versionActual"] as? String ?: "2.0",
            versionMinima = data["versionMinima"] as? String ?: "1.0",
            urlDescarga = data["urlDescarga"] as? String ?: "",
            notasVersion = data["notasVersion"] as? String ?: "",
            telegramUrl = data["telegramUrl"] as? String ?: "https://t.me/futtvsoporte",
            apiSportsKey = data["apiSportsKey"] as? String ?: ""
        )
    }

    // ── Caché local ────────────────────────────────────────
    private fun guardarCacheLocal(context: Context, cfg: AppConfig) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            // Guardamos solo los campos simples como JSON manual
            val json = buildString {
                append("{")
                append("\"minutosAutoRefresh\":${cfg.minutosAutoRefresh},")
                append("\"calidadPreferida\":\"${cfg.calidadPreferida}\",")
                append("\"textoBienvenida\":\"${cfg.textoBienvenida.replace("\"", "\\\"")}\",")
                append("\"mensajeSistema\":\"${cfg.mensajeSistema.replace("\"", "\\\"")}\",")
                append("\"mostrarHero\":${cfg.mostrarHero},")
                append("\"maxReintentosCanal\":${cfg.maxReintentosCanal},")
                append("\"modoFirebasePrimario\":${cfg.modoFirebasePrimario},")
                append("\"mostrarScraping\":${cfg.mostrarScraping}")
                append("}")
            }
            prefs.edit().putString(KEY_JSON, json).apply()
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ guardar caché fail: ${e.message}")
        }
    }

    private fun cargarCacheLocal(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val json = prefs.getString(KEY_JSON, null) ?: return
            val obj = org.json.JSONObject(json)
            _config.value = AppConfig(
                minutosAutoRefresh = obj.optInt("minutosAutoRefresh", 20),
                calidadPreferida = obj.optString("calidadPreferida", "auto"),
                textoBienvenida = obj.optString("textoBienvenida", "⚽ FutTV · En vivo"),
                mensajeSistema = obj.optString("mensajeSistema", ""),
                mostrarHero = obj.optBoolean("mostrarHero", true),
                maxReintentosCanal = obj.optInt("maxReintentosCanal", 3),
                modoFirebasePrimario = obj.optBoolean("modoFirebasePrimario", true),
                mostrarScraping = obj.optBoolean("mostrarScraping", true)
            )
            Log.d(TAG, "✅ Config cargada desde caché local")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ cargar caché fail: ${e.message}")
        }
    }
}
