#!/bin/bash
set -e

echo "🔒 Protegiendo archivos sensibles..."

# Agregar a .gitignore todo lo que NO debe subirse
for entry in "service-account.json" "set-admin.js" "node_modules/" "package.json" "package-lock.json" ".env" "local.properties" "*.bak" "*.bak*" "*.keystore" "*.jks"; do
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
    fi
done
echo "  ✅ .gitignore blindado"

echo ""
echo "🌿 Creando branch temporal..."

# Crear branch temporal (no toca main)
BRANCH_NAME="context-temp-$(date +%Y%m%d-%H%M)"
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"

echo "  ✅ Branch: $BRANCH_NAME"

echo ""
echo "🚀 Agregando TODOS los archivos del proyecto..."

# Agregar todo
git add -A

# Forzar google-services.json (necesario)
if [ -f "app/google-services.json" ]; then
    git add -f app/google-services.json
fi

# Forzar el .gitignore
git add -f .gitignore

echo ""
echo "📊 Verificando que NO haya archivos sensibles..."
echo ""

# Verificar que service-account.json NO esté en el stage
if git diff --cached --name-only | grep -q "service-account.json"; then
    echo "❌ ALERTA: service-account.json está siendo subido"
    echo "   Cancelando..."
    exit 1
fi
echo "  ✅ service-account.json NO está en el commit"

if git diff --cached --name-only | grep -q "set-admin.js"; then
    echo "❌ ALERTA: set-admin.js está siendo subido"
    exit 1
fi
echo "  ✅ set-admin.js NO está en el commit"

echo ""
echo "📋 Total de archivos a subir:"
git diff --cached --name-only | wc -l

echo ""
echo "💾 Haciendo commit..."
git commit -m "v3.1 completa - contexto temporal"

echo ""
echo "☁️  Subiendo a GitHub..."
git push -u origin "$BRANCH_NAME"

echo ""
echo "✅✅✅ Contexto subido a GitHub"
echo ""
echo "═══════════════════════════════════════════"
echo "🔗 LINKS PARA EL ASISTENTE NUEVO:"
echo "═══════════════════════════════════════════"
echo ""
echo "📦 REPO (branch $BRANCH_NAME):"
echo "   https://github.com/anonimus757/tv-app/tree/$BRANCH_NAME"
echo ""
echo "📂 CÓDIGO FUENTE COMPLETO:"
echo "   https://github.com/anonimus757/tv-app/tree/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp"
echo ""
echo "🎬 REPRODUCTOR (el más importante):"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
echo ""
echo "🏠 HOME:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
echo ""
echo "🔧 EXTRACTOR M3U8:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
echo ""
echo "📊 MODELOS:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
echo ""
echo "🔥 FIREBASE MANAGER:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/java/com/anonimus757/tvapp/data/FirebaseManager.kt"
echo ""
echo "📱 MANIFEST:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/src/main/AndroidManifest.xml"
echo ""
echo "⚙️  BUILD GRADLE:"
echo "   https://github.com/anonimus757/tv-app/blob/$BRANCH_NAME/app/build.gradle.kts"
echo ""
echo "═══════════════════════════════════════════"
echo "⚠️  PARA BORRARLO DESPUÉS (cuando ya no lo necesites):"
echo "═══════════════════════════════════════════"
echo ""
echo "   bash borrar-contexto.sh"
echo ""
echo "   (o manual: git push origin --delete $BRANCH_NAME)"
echo ""