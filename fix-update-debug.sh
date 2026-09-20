#!/bin/bash
set -e

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
cp "$PKG_DIR/MainActivity.kt" "$PKG_DIR/MainActivity.kt.bak-update-debug"

echo "📝 Agregando logs de debug al sistema de update..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/MainActivity.kt"
with open(file_path) as f:
    content = f.read()

# Agregar import de DebugLog si no está
if "import com.anonimus757.tvapp.data.DebugLog" not in content:
    content = content.replace(
        "import com.anonimus757.tvapp.data.AppConfig",
        "import com.anonimus757.tvapp.data.AppConfig\nimport com.anonimus757.tvapp.data.DebugLog"
    )

# Reemplazar el LaunchedEffect para que tenga logs detallados
old_effect = '''            LaunchedEffect(config, mostrarSplash) {
                // Solo chequear cuando terminó el splash
                if (!mostrarSplash && VersionChecker.hayUpdate(config)) {
                    versionNueva = config.versionActual
                    notasVersion = config.notasVersion
                    urlDescarga = config.urlDescarga.ifBlank {
                        "https://github.com/anonimus757/tv-app/releases/latest"
                    }
                    updateObligatorio = VersionChecker.updateObligatorio(config)
                    mostrarUpdate = true
                }
            }'''

new_effect = '''            LaunchedEffect(config, mostrarSplash) {
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
            }'''

if old_effect in content:
    content = content.replace(old_effect, new_effect)
    print("✅ Logs detallados agregados")
else:
    print("⚠️  No encontré el LaunchedEffect exacto")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"