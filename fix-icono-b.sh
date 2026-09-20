#!/bin/bash
set -e

RES="app/src/main/res"

echo "📝 Verificando app_banner en drawable/..."
ls -la "$RES/drawable/" | grep -i banner || echo "  (no hay nada con 'banner')"

echo ""
echo "🗑  Eliminando app_banner.xml (el viejo)..."
rm -f "$RES/drawable/app_banner.xml"

echo "✅ app_banner.xml eliminado"

echo ""
echo "🔎 Verificando:"
ls -la "$RES/drawable/app_banner"* 2>/dev/null || echo "⚠️  No queda ningún app_banner"

echo ""
echo "✅✅✅ Fix aplicado — el PNG ahora es el único banner"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"