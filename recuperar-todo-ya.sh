#!/bin/bash
set -e

echo "═══════════════════════════════════════════════"
echo "🔍 DIAGNÓSTICO INICIAL"
echo "═══════════════════════════════════════════════"
echo ""
echo "📂 Archivos .kt en UI (sin .bak):"
ls app/src/main/java/com/anonimus757/tvapp/ui/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||' || echo "  ❌ NINGUNO"
echo ""
echo "📂 Archivos .kt en data (sin .bak):"
ls app/src/main/java/com/anonimus757/tvapp/data/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||' || echo "  ❌ NINGUNO"
echo ""
echo "📂 Archivos .kt en notifications:"
ls app/src/main/java/com/anonimus757/tvapp/notifications/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||' || echo "  ❌ NINGUNO"
echo ""
echo "📂 Archivos en la raíz:"
ls app/src/main/java/com/anonimus757/tvapp/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||' || echo "  ❌ NINGUNO"

echo ""
echo "═══════════════════════════════════════════════"
echo "📥 RESTAURANDO DEL COMMIT fa9e0aa"
echo "═══════════════════════════════════════════════"
echo ""

# Verificar que el commit existe
if ! git log --oneline --all | grep -q "fa9e0aa"; then
    echo "❌ El commit fa9e0aa no existe"
    exit 1
fi

# Restaurar todo desde el commit
git checkout fa9e0aa -- . 2>/dev/null || true

echo "✅ Restauración desde commit completada"
echo ""

echo "═══════════════════════════════════════════════"
echo "🔍 VERIFICACIÓN POST-RESTAURACIÓN"
echo "═══════════════════════════════════════════════"
echo ""
echo "📂 Archivos en UI:"
ls app/src/main/java/com/anonimus757/tvapp/ui/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||'
echo ""
echo "📂 Archivos en data:"
ls app/src/main/java/com/anonimus757/tvapp/data/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||'
echo ""
echo "📂 Archivos en notifications:"
ls app/src/main/java/com/anonimus757/tvapp/notifications/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||' || echo "  (no existe carpeta)"
echo ""
echo "📂 Archivos en raíz:"
ls app/src/main/java/com/anonimus757/tvapp/*.kt 2>/dev/null | grep -v "\.bak" | sed 's|.*/||'

echo ""
echo "═══════════════════════════════════════════════"
echo "🔧 RESTAURANDO ARCHIVOS ESPECÍFICOS SI FALTAN"
echo "═══════════════════════════════════════════════"
echo ""

# Lista de archivos críticos que deben existir
CRITICOS_UI="HomeScreen.kt PlayerScreen.kt EventDetailScreen.kt AjustesScreen.kt BusquedaScreen.kt SplashScreen.kt Screen.kt UpdateDialog.kt"
CRITICOS_DATA="Models.kt Fuentes.kt EventRepository.kt M3u8Extractor.kt FirebaseManager.kt RemoteConfigRepository.kt SignalHealthMonitor.kt AjustesStore.kt DebugLog.kt ApkDownloader.kt"
CRITICOS_NOTIF="NotificationHelper.kt EventNotifWorker.kt EventNotifScheduler.kt FcmService.kt"

BASE="app/src/main/java/com/anonimus757/tvapp"

# Verificar UI
for f in $CRITICOS_UI; do
    if [ ! -f "$BASE/ui/$f" ]; then
        echo "  ⚠️  Falta: ui/$f → intentando restaurar de .bak"
        # Buscar el .bak más reciente
        BAK=$(ls -t $BASE/ui/${f}.bak* 2>/dev/null | head -1)
        if [ -n "$BAK" ]; then
            cp "$BAK" "$BASE/ui/$f"
            echo "     ✅ Restaurado de: $(basename $BAK)"
        else
            echo "     ❌ No hay .bak disponible"
        fi
    fi
done

# Verificar data
for f in $CRITICOS_DATA; do
    if [ ! -f "$BASE/data/$f" ]; then
        echo "  ⚠️  Falta: data/$f → intentando restaurar de .bak"
        BAK=$(ls -t $BASE/data/${f}.bak* 2>/dev/null | head -1)
        if [ -n "$BAK" ]; then
            cp "$BAK" "$BASE/data/$f"
            echo "     ✅ Restaurado de: $(basename $BAK)"
        else
            echo "     ❌ No hay .bak disponible"
        fi
    fi
done

# Verificar notifications
mkdir -p "$BASE/notifications"
for f in $CRITICOS_NOTIF; do
    if [ ! -f "$BASE/notifications/$f" ]; then
        echo "  ⚠️  Falta: notifications/$f → intentando restaurar de .bak"
        BAK=$(ls -t $BASE/notifications/${f}.bak* 2>/dev/null | head -1)
        if [ -n "$BAK" ]; then
            cp "$BAK" "$BASE/notifications/$f"
            echo "     ✅ Restaurado de: $(basename $BAK)"
        else
            echo "     ❌ No hay .bak disponible"
        fi
    fi
done

# Verificar MainActivity
if [ ! -f "$BASE/MainActivity.kt" ]; then
    echo "  ⚠️  Falta: MainActivity.kt → intentando restaurar de .bak"
    BAK=$(ls -t $BASE/MainActivity.kt.bak* 2>/dev/null | head -1)
    if [ -n "$BAK" ]; then
        cp "$BAK" "$BASE/MainActivity.kt"
        echo "     ✅ Restaurado de: $(basename $BAK)"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ RECUPERACIÓN COMPLETADA"
echo "═══════════════════════════════════════════════"
echo ""
echo "📊 Estado final:"
echo ""
echo "  UI:"
ls $BASE/ui/*.kt 2>/dev/null | grep -v "\.bak" | wc -l | xargs -I {} echo "    {} archivos"
echo "  Data:"
ls $BASE/data/*.kt 2>/dev/null | grep -v "\.bak" | wc -l | xargs -I {} echo "    {} archivos"
echo "  Notifications:"
ls $BASE/notifications/*.kt 2>/dev/null | wc -l | xargs -I {} echo "    {} archivos"
echo "  Raíz:"
ls $BASE/*.kt 2>/dev/null | grep -v "\.bak" | wc -l | xargs -I {} echo "    {} archivos"

echo ""
echo "═══════════════════════════════════════════════"
echo "🚀 COMPILANDO..."
echo "═══════════════════════════════════════════════"
echo ""

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

./gradlew clean --no-daemon --max-workers=1 2>&1 | tail -3
./gradlew assembleDebug --no-daemon --max-workers=1 2>&1 | tail -20

echo ""
echo "═══════════════════════════════════════════════"
echo "✅ SCRIPT COMPLETADO"
echo "═══════════════════════════════════════════════"
echo ""
echo "Si compiló OK → APK en:"
echo "  app/build/outputs/apk/debug/app-debug.apk"
echo ""
echo "Si falló → pegar el error al asistente"