#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
MANIFEST="app/src/main/AndroidManifest.xml"

# ═══════════════════════════════════════════════════════════
# PARTE 1 — APLICAR CAMBIOS (idempotente)
# ═══════════════════════════════════════════════════════════
echo "🔍 Verificando cambios del fix 39..."

# ── 1a) FirebaseManager: suscribirseAlTopic ──
if grep -q "suscribirseAlTopic" "$PKG_DIR/data/FirebaseManager.kt" 2>/dev/null; then
  echo "  ✓ FirebaseManager ya tiene suscribirseAlTopic"
else
  echo "  📝 Aplicando cambio en FirebaseManager.kt..."

  python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/FirebaseManager.kt"
with open(file_path) as f: content = f.read()

old = '''            loginAnonimo()
            obtenerTokenFcm()
            inicializado = true'''
new = '''            loginAnonimo()
            obtenerTokenFcm()
            suscribirseAlTopic()
            inicializado = true'''
if old in content:
    content = content.replace(old, new)

old_fn = '''    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }'''

new_fn = '''    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }

    /**
     * Suscribe al topic "futtv_todos".
     */
    private suspend fun suscribirseAlTopic() {
        try {
            FirebaseMessaging.getInstance().subscribeToTopic("futtv_todos").await()
            Log.d(TAG, "✅ Suscripto al topic futtv_todos")
            DebugLog.log("✅ Suscripto a notificaciones")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Subscribe topic fail: ${e.message}")
            DebugLog.log("❌ Subscribe topic fail: ${e.message}")
        }
    }'''

if old_fn in content:
    content = content.replace(old_fn, new_fn)

with open(file_path, "w") as f: f.write(content)
PYEOF
  echo "  ✅ FirebaseManager actualizado"
fi

# ── 1b) Manifest: REQUEST_IGNORE_BATTERY_OPTIMIZATIONS ──
if grep -q "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" "$MANIFEST" 2>/dev/null; then
  echo "  ✓ Manifest ya tiene el permiso"
else
  echo "  📝 Agregando permiso al manifest..."
  sed -i 's|android.permission.WAKE_LOCK" />|android.permission.WAKE_LOCK" />\n    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />|' "$MANIFEST"
  echo "  ✅ Permiso agregado"
fi

# ── 1c) MainActivity: pedirBatteryWhitelist ──
if grep -q "pedirBatteryWhitelist" "$PKG_DIR/MainActivity.kt" 2>/dev/null; then
  echo "  ✓ MainActivity ya pide whitelist de batería"
else
  echo "  📝 Aplicando cambio en MainActivity.kt..."

  python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/MainActivity.kt"
with open(file_path) as f: content = f.read()

old = '''    LaunchedEffect(Unit) {
        NotificationHelper.crearCanales(context)'''

new = '''    val batteryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { }

    LaunchedEffect(Unit) {
        NotificationHelper.crearCanales(context)
        pedirBatteryWhitelist(context, batteryLauncher)'''

if old in content:
    content = content.replace(old, new)

if "import android.content.Intent" not in content:
    content = content.replace(
        "import android.os.Build",
        "import android.content.Intent\nimport android.net.Uri\nimport android.os.Build\nimport android.provider.Settings"
    )
if "import androidx.activity.result.ActivityResultLauncher" not in content:
    content = content.replace(
        "import androidx.activity.result.contract.ActivityResultContracts",
        "import androidx.activity.result.ActivityResultLauncher\nimport androidx.activity.result.contract.ActivityResultContracts"
    )

helper = '''

private fun pedirBatteryWhitelist(
    context: android.content.Context,
    launcher: ActivityResultLauncher<Intent>
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

        val intent = Intent().apply {
            action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
            data = Uri.parse("package:$packageName")
        }
        launcher.launch(intent)
    } catch (e: Exception) {
        // En TV no aplica, no es grave
    }
}
'''

if "pedirBatteryWhitelist" in content and "private fun pedirBatteryWhitelist" not in content:
    content += helper

with open(file_path, "w") as f: f.write(content)
PYEOF
  echo "  ✅ MainActivity actualizado"
fi

# ═══════════════════════════════════════════════════════════
# PARTE 2 — CONFIGURAR GRADLE CON MEMORIA SEGURA
# ═══════════════════════════════════════════════════════════
echo ""
echo "⚙️  Configurando Gradle con memoria optimizada para Codespaces..."

cat > gradle.properties << 'EOF'
# Configuración optimizada para Codespaces (RAM limitada)
org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.configureondemand=false
org.gradle.caching=true
kotlin.daemon.jvmargs=-Xmx1024m
android.useAndroidX=true
android.enableJetifier=false
EOF

echo "  ✅ gradle.properties creado con memoria segura"

# ═══════════════════════════════════════════════════════════
# PARTE 3 — LIMPIAR DAEMONS VIEJOS
# ═══════════════════════════════════════════════════════════
echo ""
echo "🧹 Limpiando daemons viejos de Gradle..."
./gradlew --stop 2>/dev/null || true
echo "  ✅ Daemons detenidos"

# ═══════════════════════════════════════════════════════════
# PARTE 4 — COMPILAR
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔎 Verificando cambios:"
grep -q "suscribirseAlTopic" "$PKG_DIR/data/FirebaseManager.kt" && echo "  ✓ suscribirseAlTopic"
grep -q "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" "$MANIFEST" && echo "  ✓ Permiso battery"
grep -q "pedirBatteryWhitelist" "$PKG_DIR/MainActivity.kt" && echo "  ✓ pedirBatteryWhitelist"

echo ""
echo "🚀 Compilando..."
./gradlew clean --no-daemon --max-workers=1
./gradlew assembleDebug --no-daemon --max-workers=1

echo ""
echo "✅✅✅ Todo listo — APK generado"
echo ""
echo "📱 APK en: app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "📌 Qué tiene este build:"
echo "   • Fix crash key duplicada"
echo "   • Notifs solo Firebase"
echo "   • Suscripto al topic futtv_todos"
echo "   • Pide whitelist de batería"
echo "   • Iconos nuevos"