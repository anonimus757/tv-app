#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto (no encuentro ./gradlew)"
  echo "   cd /workspaces/tv-app y volvé a intentar"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
PLAYER_FILE="$PKG_DIR/ui/PlayerScreen.kt"

if [ ! -f "$PLAYER_FILE" ]; then
  echo "❌ No encuentro $PLAYER_FILE"
  exit 1
fi

# Guarda: si ya está aplicado, no lo duplicamos
if grep -q "FLAG_KEEP_SCREEN_ON" "$PLAYER_FILE"; then
  echo "ℹ️  El fix ya está aplicado, no hago nada."
  exit 0
fi

echo "📝 Aplicando fix: mantener pantalla encendida en el reproductor..."

# Insertamos el bloque justo después de 'val playerFocus = remember { FocusRequester() }'
# Usamos FQN (rutas completas) para no tener que tocar los imports.
perl -0777 -i -pe 's/(val playerFocus = remember \{ FocusRequester\(\) \})/$1\n\n    \/\/ Fix: mantener pantalla encendida mientras se reproduce\n    \/\/ Solo se activa dentro del reproductor (onDispose lo apaga al salir).\n    \/\/ Usa FLAG_KEEP_SCREEN_ON, el flag nativo de Android para esto.\n    val view = androidx.compose.ui.platform.LocalView.current\n    DisposableEffect(Unit) {\n        val window = (view.context as? android.app.Activity)?.window\n        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)\n        onDispose {\n            window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)\n        }\n    }/' "$PLAYER_FILE"

echo ""
echo "🔎 Verificando que se aplicó..."
grep -n "FLAG_KEEP_SCREEN_ON" "$PLAYER_FILE" || {
  echo "❌ No se pudo aplicar. Revisá el archivo manualmente."
  exit 1
}

echo ""
echo "✅✅✅ Fix 21b completo — pantalla ya no se apaga en el reproductor"
echo ""
echo "🚀 Ahora compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"