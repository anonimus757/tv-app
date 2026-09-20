#!/bin/bash
set -e

if [ ! -f "icon-base.png" ]; then
  echo "❌ Falta icon-base.png en la raíz del proyecto"
  echo "   Guardá la imagen que te dio Gemini con ese nombre y volvé a intentar."
  exit 1
fi

echo "📦 Instalando ImageMagick (si no está)..."
if ! command -v convert &> /dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y imagemagick -qq
fi

RES="app/src/main/res"
mkdir -p "$RES/mipmap-mdpi" "$RES/mipmap-hdpi" "$RES/mipmap-xhdpi" "$RES/mipmap-xxhdpi" "$RES/mipmap-xxxhdpi"
mkdir -p "$RES/drawable"

echo "🎨 Generando iconos en todos los tamaños..."

# Iconos legacy (para Android < 8)
declare -A TAMANIOS=(
  ["mdpi"]=48
  ["hdpi"]=72
  ["xhdpi"]=96
  ["xxhdpi"]=144
  ["xxxhdpi"]=192
)

for dens in "${!TAMANIOS[@]}"; do
  size=${TAMANIOS[$dens]}
  convert icon-base.png -resize ${size}x${size} "$RES/mipmap-$dens/ic_launcher.png"
  convert icon-base.png -resize ${size}x${size} "$RES/mipmap-$dens/ic_launcher_round.png"
  echo "  ✓ $dens ($size x $size)"
done

# Icono Play Store 512x512 (por si lo subís)
convert icon-base.png -resize 512x512 "icon-playstore-512.png"
echo "  ✓ Play Store icon 512x512"

# Banner TV 320x180 (para el launcher de Android TV)
convert icon-base.png -resize 320x180^ -gravity center -extent 320x180 -background "#050505" -flatten "$RES/drawable/app_banner.png"
echo "  ✓ Banner TV (320 x 180)"

# Icono adaptive foreground (108dp x 5 dens)
echo "🎨 Generando adaptive icons (Android 8+)..."
mkdir -p "$RES/mipmap-anydpi-v26"

# Generamos el foreground con margen (66% del canvas según spec de Google)
convert icon-base.png -resize 288x288 -gravity center -background none -extent 432x432 "$RES/drawable/ic_launcher_foreground.png"

# Color de fondo del adaptive icon (negro)
cat > "$RES/values/colors.xml" 2>/dev/null << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#050505</color>
</resources>
EOF

# Adaptive icon (Android 8+)
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOF

cp "$RES/mipmap-anydpi-v26/ic_launcher.xml" "$RES/mipmap-anydpi-v26/ic_launcher_round.xml"

echo ""
echo "🔎 Verificando archivos generados:"
find "$RES/mipmap-mdpi" "$RES/mipmap-xxxhdpi" "$RES/drawable" "$RES/mipmap-anydpi-v26" -type f | sort

echo ""
echo "✅✅✅ Iconos instalados en todos los tamaños"
echo ""
echo "📱 Cobertura:"
echo "   • Android 8+ → adaptive icons (mipmap-anydpi-v26)"
echo "   • Android < 8 → iconos legacy (mipmap-*dpi)"
echo "   • Android TV → banner 320x180"
echo "   • Play Store → icon-playstore-512.png"
echo ""
echo "🚀 Compilá e instalá para ver el icono:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"