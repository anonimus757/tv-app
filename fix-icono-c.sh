#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

MANIFEST="app/src/main/AndroidManifest.xml"
RES="app/src/main/res"

# ═══════════════════════════════════════════════════════════
# 1) Verificar que existan los archivos de icono
# ═══════════════════════════════════════════════════════════
echo "🔎 Verificando archivos de icono..."

FALTAN=0
for f in \
  "$RES/mipmap-mdpi/ic_launcher.png" \
  "$RES/mipmap-hdpi/ic_launcher.png" \
  "$RES/mipmap-xhdpi/ic_launcher.png" \
  "$RES/mipmap-xxhdpi/ic_launcher.png" \
  "$RES/mipmap-xxxhdpi/ic_launcher.png" \
  "$RES/mipmap-anydpi-v26/ic_launcher.xml" \
  "$RES/drawable/ic_launcher_foreground.png" \
  "$RES/values/colors.xml"
do
  if [ -f "$f" ]; then
    echo "  ✓ $(basename $f) en $(dirname $f | sed "s|$RES/||")"
  else
    echo "  ❌ FALTA: $f"
    FALTAN=$((FALTAN+1))
  fi
done

if [ $FALTAN -gt 0 ]; then
  echo ""
  echo "⚠️  Faltan $FALTAN archivos. Corré primero el fix-icono.sh original."
  exit 1
fi

# ═══════════════════════════════════════════════════════════
# 2) Verificar/agregar android:icon al manifest
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Verificando android:icon en AndroidManifest.xml..."

cp "$MANIFEST" "$MANIFEST.bak-icono-c"

# Buscar si ya tiene android:icon
if grep -q 'android:icon=' "$MANIFEST"; then
  echo "  ℹ️  Ya tiene android:icon declarado"
  grep 'android:icon=' "$MANIFEST" | head -1
else
  echo "  📝 Agregando android:icon + android:roundIcon al <application>..."

  # Agregar icon y roundIcon justo después de <application
  python3 << 'PYEOF'
file_path = "app/src/main/AndroidManifest.xml"
with open(file_path) as f:
    content = f.read()

# Insertar después de la línea <application (con sus atributos ya existentes)
old = '<application'
if content.count(old) >= 1:
    # Buscar la primera aparición de <application y agregar icon ahí
    # Encuentro el cierre del tag >
    import re
    match = re.search(r'<application\b[^>]*>', content)
    if match:
        original = match.group(0)
        # Chequear si ya tiene icon
        if 'android:icon=' not in original:
            # Insertar icon y roundIcon antes del cierre >
            nuevo = original[:-1] + '    android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"\n        >'
            content = content.replace(original, nuevo, 1)
            with open(file_path, "w") as f:
                f.write(content)
            print("✅ android:icon + android:roundIcon agregados")
        else:
            print("ℹ️  Ya tenía icon")
    else:
        print("⚠️  No encontré el tag <application>")
else:
    print("⚠️  No encontré el tag <application>")
PYEOF
fi

# ═══════════════════════════════════════════════════════════
# 3) Verificar que ic_launcher_round exista
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Verificando ic_launcher_round..."

for dens in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  if [ ! -f "$RES/mipmap-$dens/ic_launcher_round.png" ]; then
    echo "  📝 Creando ic_launcher_round.png para $dens"
    cp "$RES/mipmap-$dens/ic_launcher.png" "$RES/mipmap-$dens/ic_launcher_round.png"
  fi
done
echo "  ✅ ic_launcher_round OK"

# ═══════════════════════════════════════════════════════════
# 4) Verificar colors.xml
# ═══════════════════════════════════════════════════════════
echo ""
echo "📝 Verificando colors.xml..."

if [ -f "$RES/values/colors.xml" ]; then
  if ! grep -q "ic_launcher_background" "$RES/values/colors.xml"; then
    echo "  📝 Agregando ic_launcher_background a colors.xml"
    # Agregar la línea antes del </resources>
    sed -i 's|</resources>|    <color name="ic_launcher_background">#050505</color>\n</resources>|' "$RES/values/colors.xml"
  fi
  echo "  ✅ colors.xml OK"
else
  echo "  📝 Creando colors.xml"
  mkdir -p "$RES/values"
  cat > "$RES/values/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#050505</color>
</resources>
EOF
  echo "  ✅ colors.xml creado"
fi

# ═══════════════════════════════════════════════════════════
# 5) Verificación final
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔎 VERIFICACIÓN FINAL:"
echo ""
echo "Manifest:"
grep -E "android:icon|android:roundIcon" "$MANIFEST" | head -2
echo ""
echo "Archivos de icono en mipmap-xxxhdpi:"
ls "$RES/mipmap-xxxhdpi/" 2>/dev/null
echo ""
echo "Adaptive icon:"
ls "$RES/mipmap-anydpi-v26/" 2>/dev/null

echo ""
echo "✅✅✅ Fix icono C completo"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"