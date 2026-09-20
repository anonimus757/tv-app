package com.anonimus757.tvapp

import android.Manifest
import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.lifecycleScope
import com.anonimus757.tvapp.data.DebugLog
import com.anonimus757.tvapp.data.AjustesStore
import com.anonimus757.tvapp.data.FirebaseManager
import com.anonimus757.tvapp.data.RemoteConfigRepository
import com.anonimus757.tvapp.data.VersionChecker
import com.anonimus757.tvapp.notifications.NotificationHelper
import com.anonimus757.tvapp.ui.*
import com.anonimus757.tvapp.ui.util.DetectorDispositivo
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ═══════════════════════════════════════════════════════
        // APLICAR ORIENTACIÓN
        // TV → siempre horizontal
        // Celu/Tablet → según preferencia del usuario
        // ═══════════════════════════════════════════════════════
        try {
            if (DetectorDispositivo.esTV(this)) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                val pref = AjustesStore.obtenerOrientacion(this)
                requestedOrientation = when (pref) {
                    "vertical" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    "horizontal" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
        } catch (_: Exception) {}

        lifecycleScope.launch {
            FirebaseManager.init()
        }

        setContent {
            InicializarFirebaseCompose()

            var mostrarSplash by remember { mutableStateOf(true) }
            var screen by remember { mutableStateOf<Screen>(Screen.Home) }

            // ═══════════════════════════════════════════════════════════
            // AUTO-UPDATE: chequea versión en Firestore
            // ═══════════════════════════════════════════════════════════
            val config by RemoteConfigRepository.config.collectAsState()
            var mostrarUpdate by remember { mutableStateOf(false) }
            var notasVersion by remember { mutableStateOf("") }
            var versionNueva by remember { mutableStateOf("") }
            var updateObligatorio by remember { mutableStateOf(false) }
            var urlDescarga by remember { mutableStateOf("") }

            LaunchedEffect(config, mostrarSplash) {
                DebugLog.log("🔍 Update check: splash=$mostrarSplash")
                if (!mostrarSplash) {
                    val local = VersionChecker.versionLocal()
                    val remoto = config.versionActual
                    val hay = VersionChecker.hayUpdate(config)
                    DebugLog.log("📱 Local: $local · Remoto: $remoto · Hay update: $hay")

                    if (hay) {
                        versionNueva = config.versionActual
                        notasVersion = config.notasVersion
                        urlDescarga = config.urlDescarga.ifBlank {
                            "https://github.com/anonimus757/tv-app/releases/latest"
                        }
                        updateObligatorio = VersionChecker.updateObligatorio(config)
                        mostrarUpdate = true
                        DebugLog.log("✅ Mostrando diálogo de update")
                    }
                }
            }

            // Splash primero
            if (mostrarSplash) {
                SplashScreen(onTerminado = { mostrarSplash = false })
            } else {
                when (val s = screen) {
                    is Screen.Home -> HomeScreen(
                        onEventoClick = { evento, todos ->
                            screen = Screen.Detail(evento, todos, VolverA.Home)
                        },
                        onIrAAjustes = { screen = Screen.Ajustes },
                        onIrABusqueda = { screen = Screen.Busqueda }
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

                    is Screen.Ajustes -> AjustesScreen(
                        onBack = { screen = Screen.Home }
                    )

                    is Screen.Busqueda -> BusquedaScreen(
                        onEventoClick = { evento, todos ->
                            screen = Screen.Detail(evento, todos, VolverA.Home)
                        },
                        onBack = { screen = Screen.Home }
                    )
                }
            }

            // Update Dialog — SIEMPRE al final para flotar encima de todo
            if (mostrarUpdate) {
                UpdateDialog(
                    versionNueva = versionNueva,
                    notasVersion = notasVersion,
                    urlDescarga = urlDescarga,
                    obligatorio = updateObligatorio,
                    onCerrar = { mostrarUpdate = false }
                )
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

    val batteryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { }

    LaunchedEffect(Unit) {
        NotificationHelper.crearCanales(context)
        pedirBatteryWhitelist(context, batteryLauncher)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!NotificationHelper.tienePermiso(context)) {
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        RemoteConfigRepository.iniciar(context)
    }
}

private fun pedirBatteryWhitelist(
    context: android.content.Context,
    launcher: ActivityResultLauncher<android.content.Intent>
) {
    try {
        val packageName = context.packageName
        val isIgnoring = (context as? android.app.Activity)
            ?.let { act ->
                val powerManager = act.getSystemService(android.content.Context.POWER_SERVICE)
                        as android.os.PowerManager
                powerManager.isIgnoringBatteryOptimizations(packageName)
            } ?: false

        if (isIgnoring) return

        val intent = android.content.Intent().apply {
            action = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
            data = android.net.Uri.parse("package:$packageName")
        }
        launcher.launch(intent)
    } catch (e: Exception) {
        // No aplica en TV
    }
}
