#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

# Verificar que google-services.json exista
if [ ! -f "app/google-services.json" ]; then
  echo "❌ Falta app/google-services.json"
  echo "   Bajalo de Firebase Console → Configuración del proyecto → Tu app Android"
  echo "   Y ponelo en app/google-services.json antes de seguir."
  exit 1
fi
echo "✅ google-services.json encontrado"

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
mkdir -p "$PKG_DIR/data"
mkdir -p "$PKG_DIR/notifications"

# ─────────────────────────────────────────────────────────────
# 1) build.gradle.kts (raíz) → plugin Google Services
# ─────────────────────────────────────────────────────────────
echo "📝 Actualizando build.gradle.kts (raíz)..."
cat > build.gradle.kts << 'EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}
EOF

# ─────────────────────────────────────────────────────────────
# 2) app/build.gradle.kts → Firebase BoM + Auth + Firestore + Messaging
# ─────────────────────────────────────────────────────────────
echo "📝 Actualizando app/build.gradle.kts..."

cat > app/build.gradle.kts << 'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.anonimus757.tvapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.anonimus757.tvapp"
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")

    implementation(platform("androidx.compose:compose-bom:2024.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.tv:tv-material:1.0.0")

    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")

    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")

    // Firebase (Paso 26)
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
EOF

# ─────────────────────────────────────────────────────────────
# 3) AndroidManifest.xml → FcmService
# ─────────────────────────────────────────────────────────────
echo "📝 Actualizando AndroidManifest.xml..."
cat > app/src/main/AndroidManifest.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <uses-feature android:name="android.software.leanback" android:required="false" />
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

    <!-- Notificaciones (Paso 22) -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:banner="@drawable/app_banner"
        android:usesCleartextTraffic="true"
        android:supportsRtl="true"
        android:theme="@style/Theme.TVApp">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:theme="@style/Theme.TVApp">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- FCM (Paso 26) -->
        <service
            android:name=".notifications.FcmService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>

        <!-- Canal por defecto para notifs FCM cuando la app está cerrada -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="futtv_eventos" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@android:drawable/ic_media_play" />
    </application>
</manifest>
EOF

# ─────────────────────────────────────────────────────────────
# 4) FirebaseManager.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando FirebaseManager.kt..."

cat > "$PKG_DIR/data/FirebaseManager.kt" << 'EOF'
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
            inicializado = true
            Log.d(TAG, "✅ Firebase inicializado")
        } catch (e: Exception) {
            Log.e(TAG, "❌ init fail: ${e.message}")
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
        } catch (e: Exception) {
            Log.e(TAG, "❌ Login anónimo fail: ${e.message}")
        }
    }

    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 5) RemoteConfigRepository.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando RemoteConfigRepository.kt..."

cat > "$PKG_DIR/data/RemoteConfigRepository.kt" << 'EOF'
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
    val agendasExternas: List<AgendaExterna> = emptyList()
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
            agendasExternas = agendas
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
EOF

# ─────────────────────────────────────────────────────────────
# 6) FcmService.kt
# ─────────────────────────────────────────────────────────────
echo "📝 Creando FcmService.kt..."

cat > "$PKG_DIR/notifications/FcmService.kt" << 'EOF'
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
EOF

# ─────────────────────────────────────────────────────────────
# 7) MainActivity.kt → init Firebase al arrancar
# ─────────────────────────────────────────────────────────────
echo "📝 Actualizando MainActivity.kt..."

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
import com.anonimus757.tvapp.data.FirebaseManager
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.notifications.NotificationHelper
import com.anonimus757.tvapp.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Paso 26: inicializar Firebase (auth anónimo + FCM token)
        // Se hace en background, no bloquea la UI.
        lifecycleScope.launchWhenStarted {
            FirebaseManager.init()
        }

        setContent {
            InicializarFirebaseCompose()

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
private fun InicializarFirebaseCompose() {
    val context = LocalContext.current

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    LaunchedEffect(Unit) {
        // Canales de notificación
        NotificationHelper.crearCanales(context)

        // Permiso POST_NOTIFICATIONS (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!NotificationHelper.tienePermiso(context)) {
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // Config remota (Firestore listener + caché)
        RemoteConfigRepository.iniciar(context)
    }
}
EOF

# Necesitamos importar lifecycleScope en MainActivity, lo agregamos
perl -0777 -i -pe 's/(import androidx\.activity\.ComponentActivity\n)/$1import androidx.lifecycle.lifecycleScope\nimport kotlinx.coroutines.launch\n/' "$PKG_DIR/MainActivity.kt"

# ─────────────────────────────────────────────────────────────
# 8) Verificación final
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando:"
[ -f "app/google-services.json" ] && echo "  ✓ app/google-services.json"
grep -q "com.google.gms.google-services" build.gradle.kts && echo "  ✓ Plugin Google Services en gradle raíz"
grep -q "firebase-bom" app/build.gradle.kts && echo "  ✓ Firebase BoM en app/build.gradle.kts"
grep -q "firebase-firestore-ktx" app/build.gradle.kts && echo "  ✓ Firestore KTX"
grep -q "firebase-messaging-ktx" app/build.gradle.kts && echo "  ✓ Messaging KTX"
grep -q "FcmService" app/src/main/AndroidManifest.xml && echo "  ✓ FcmService en manifest"
[ -f "$PKG_DIR/data/FirebaseManager.kt" ] && echo "  ✓ FirebaseManager.kt"
[ -f "$PKG_DIR/data/RemoteConfigRepository.kt" ] && echo "  ✓ RemoteConfigRepository.kt"
[ -f "$PKG_DIR/notifications/FcmService.kt" ] && echo "  ✓ FcmService.kt"
grep -q "FirebaseManager.init" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity init Firebase"
grep -q "RemoteConfigRepository.iniciar" "$PKG_DIR/MainActivity.kt" && echo "  ✓ MainActivity inicia config remota"

echo ""
echo "✅✅✅ Paso 26 completo — Firebase integrado (sin cambios visuales)"
echo ""
echo "📌 Qué hace ahora la app:"
echo "   1. Login anónimo en Firebase (aparece 1 user en Console)"
echo "   2. Lee config/app de Firestore (con caché local)"
echo "   3. Obtiene token FCM para recibir push"
echo "   4. FcmService listo para recibir notifs cuando las mandes"
echo ""
echo "🚀 Compilá (va a tardar más, baja deps nuevas):"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"