#!/bin/bash
set -e

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"
cp "$PKG_DIR/MainActivity.kt" "$PKG_DIR/MainActivity.kt.bak-layout"

echo "📝 Arreglando layout del UpdateDialog (superponer, no apilar)..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/MainActivity.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Envolver TODO el contenido en un Box para que el UpdateDialog
# se superponga en vez de apilarse
# ═══════════════════════════════════════════════════════════

# Buscar el bloque donde empieza el "if (mostrarUpdate)"
old_bloque = '''            if (mostrarUpdate) {
                com.anonimus757.tvapp.ui.UpdateDialog(
                    versionNueva = versionNueva,
                    notasVersion = notasVersion,
                    urlDescarga = urlDescarga,
                    obligatorio = updateObligatorio,
                    onCerrar = { mostrarUpdate = false }
                )
            }

            if (mostrarSplash) {
                SplashScreen(onTerminado = { mostrarSplash = false })
            } else {'''

new_bloque = '''            // ═══════════════════════════════════════════════════════════
            // Box para superponer el UpdateDialog sobre el contenido
            // ═══════════════════════════════════════════════════════════
            androidx.compose.foundation.layout.Box(
                Modifier.fillMaxSize()
            ) {
                if (mostrarSplash) {
                    SplashScreen(onTerminado = { mostrarSplash = false })
                } else {'''

if old_bloque in content:
    content = content.replace(old_bloque, new_bloque)
    print("✅ Box contenedor agregado")

# Ahora hay que cerrar el Box y meter el UpdateDialog adentro
# Buscar el cierre del when (el último } del when)
old_cierre = '''                is Screen.Busqueda -> BusquedaScreen(
                    onEventoClick = { evento, todos ->
                        screen = Screen.Detail(evento, todos, VolverA.Home)
                    },
                    onBack = { screen = Screen.Home }
                )
            }
        }
    }
}'''

new_cierre = '''                    is Screen.Busqueda -> BusquedaScreen(
                        onEventoClick = { evento, todos ->
                            screen = Screen.Detail(evento, todos, VolverA.Home)
                        },
                        onBack = { screen = Screen.Home }
                    )
                }

                // ═══════════════════════════════════════════════════════════
                // UpdateDialog SUPERPUESTO arriba de todo
                // ═══════════════════════════════════════════════════════════
                if (mostrarUpdate) {
                    com.anonimus757.tvapp.ui.UpdateDialog(
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
}'''

if old_cierre in content:
    content = content.replace(old_cierre, new_cierre)
    print("✅ UpdateDialog movido adentro del Box (superpuesto)")

# Import de Modifier
if "import androidx.compose.ui.Modifier" not in content:
    content = content.replace(
        "import androidx.compose.runtime.*",
        "import androidx.compose.runtime.*\nimport androidx.compose.ui.Modifier"
    )
    print("✅ Import Modifier")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "Box(" "$PKG_DIR/MainActivity.kt" | xargs -I {} echo "  Boxes en MainActivity: {}"
grep -q "UpdateDialog SUPERPUESTO" "$PKG_DIR/MainActivity.kt" && echo "  ✓ UpdateDialog superpuesto"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"