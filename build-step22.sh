#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

MANIFEST="app/src/main/AndroidManifest.xml"
BUILD_GRADLE="app/build.gradle.kts"
PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

# ─────────────────────────────────────────────────────────────
# 0) Verificaciones previas
# ─────────────────────────────────────────────────────────────
if [ ! -f "$MANIFEST" ]; then
  echo "❌ No encuentro $MANIFEST"
  exit 1
fi
if [ ! -f "$BUILD_GRADLE" ]; then
  echo "❌ No encuentro $BUILD_GRADLE"
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# 1) Backup de archivos que vamos a modificar
# ─────────────────────────────────────────────────────────────
cp "$MANIFEST" "$MANIFEST.bak"
cp "$BUILD_GRADLE" "$BUILD_GRADLE.bak"
echo "💾 Backups creados: $MANIFEST.bak y $BUILD_GRADLE.bak"

# ─────────────────────────────────────────────────────────────
# 2) Insertar permisos en el AndroidManifest (si no existen)
# ─────────────────────────────────────────────────────────────
if grep -q "POST_NOTIFICATIONS" "$MANIFEST"; then
  echo "ℹ️  Permisos ya estaban en el manifest"
else
  TMP=$(mktemp)
  awk '
    BEGIN { done = 0 }
    /<application/ && !done {
      print "    <!-- Notificaciones (Paso 22) -->"
      print "    <uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\" />"
      print "    <uses-permission android:name=\"android.permission.RECEIVE_BOOT_COMPLETED\" />"
      print "    <uses-permission android:name=\"android.permission.WAKE_LOCK\" />"
      print ""
      done = 1
    }
    { print }
  ' "$MANIFEST" > "$TMP"
  mv "$TMP" "$MANIFEST"
  echo "✅ Permisos agregados al manifest"
fi

# ─────────────────────────────────────────────────────────────
# 3) Agregar WorkManager al build.gradle.kts (si no está)
# ─────────────────────────────────────────────────────────────
if grep -q "work-runtime-ktx" "$BUILD_GRADLE"; then
  echo "ℹ️  WorkManager ya estaba en build.gradle.kts"
else
  TMP=$(mktemp)
  awk '
    BEGIN { done = 0 }
    /^dependencies[[:space:]]*\{/ && !done {
      print
      print "    implementation(\"androidx.work:work-runtime-ktx:2.9.1\")"
      done = 1
      next
    }
    { print }
  ' "$BUILD_GRADLE" > "$TMP"
  mv "$TMP" "$BUILD_GRADLE"

  if grep -q "work-runtime-ktx" "$BUILD_GRADLE"; then
    echo "✅ WorkManager agregado al build.gradle.kts"
  else
    echo "⚠️  No encontré el bloque 'dependencies {' en build.gradle.kts."
    echo "   Agregá manualmente dentro del bloque dependencies:"
    echo "     implementation(\"androidx.work:work-runtime-ktx:2.9.1\")"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 4) Crear NotificationHelper.kt
# ─────────────────────────────────────────────────────────────
mkdir -p "$PKG_DIR/notifications"

cat > "$PKG_DIR/notifications/NotificationHelper.kt" << 'EOF'
package com.anonimus757.tvapp.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Helper central para TODO lo de notificaciones en FutTV.
 *
 * Paso 22: infra únicamente. La lógica de cuándo enviar viene en el 23.
 * Los canales se crean una sola vez y Android los ignora si ya existen.
 */
object NotificationHelper {

    const val CANAL_EVENTOS = "futtv_eventos"
    const val CANAL_CUSTOM = "futtv_custom"

    /**
     * Crea los canales de notificación. Llamar una vez al iniciar la app.
     * Idempotente: si ya existen, Android los ignora.
     */
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

    /**
     * Verifica si tenemos el permiso runtime de notificaciones (Android 13+).
     * En versiones anteriores siempre devuelve true.
     */
    fun tienePermiso(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Envía una notificación simple.
     * @param id ID único — usar hash del evento o timestamp para no pisar otras.
     */
    fun notificar(
        context: Context,
        id: Int,
        titulo: String,
        mensaje: String,
        canal: String = CANAL_EVENTOS
    ) {
        if (!tienePermiso(context)) return

        val builder = NotificationCompat.Builder(context, canal)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(titulo)
            .setContentText(mensaje)
            .setStyle(NotificationCompat.BigTextStyle().bigText(mensaje))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
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
# 5) Verificación final
# ─────────────────────────────────────────────────────────────
echo ""
echo "🔎 Verificando cambios:"
grep -q "POST_NOTIFICATIONS" "$MANIFEST" && echo "  ✓ manifest tiene POST_NOTIFICATIONS"
grep -q "RECEIVE_BOOT_COMPLETED" "$MANIFEST" && echo "  ✓ manifest tiene RECEIVE_BOOT_COMPLETED"
grep -q "WAKE_LOCK" "$MANIFEST" && echo "  ✓ manifest tiene WAKE_LOCK"
grep -q "work-runtime-ktx" "$BUILD_GRADLE" && echo "  ✓ gradle tiene WorkManager"
[ -f "$PKG_DIR/notifications/NotificationHelper.kt" ] && echo "  ✓ NotificationHelper.kt creado"

echo ""
echo "✅✅✅ Paso 22 completo — infra de notificaciones lista"
echo ""
echo "📌 Qué hicimos:"
echo "   - AndroidManifest: 3 permisos nuevos"
echo "   - build.gradle.kts: androidx.work:work-runtime-ktx:2.9.1"
echo "   - NotificationHelper.kt: 2 canales (eventos + custom) + método notificar()"
echo "   - Backups en *.bak por si hay que revertir"
echo ""
echo "⚠️  NADA VISUAL CAMBIA todavía. Solo es infra."
echo ""
echo "🚀 Ahora compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"