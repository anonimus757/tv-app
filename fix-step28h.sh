#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

echo "🔄 Revirtiendo PlayerScreen.kt al estado anterior al fix 28g..."

# Restaurar el backup que se creó en el fix 28g
if [ -f "$PKG_DIR/ui/PlayerScreen.kt.bak3" ]; then
  cp "$PKG_DIR/ui/PlayerScreen.kt.bak3" "$PKG_DIR/ui/PlayerScreen.kt"
  echo "✅ PlayerScreen.kt restaurado desde .bak3"
else
  echo "⚠️  No hay .bak3. Revisá manualmente."
  exit 1
fi

echo "📝 Actualizando URL del evento en Firestore..."

# Script de Node para actualizar Firestore
cat > update-url.js << 'EOF'
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./service-account.json');

const app = initializeApp({
  credential: cert(serviceAccount),
  projectId: 'futtv-ce7f9'
});

const db = getFirestore(app);

// Buscar el evento TEST y actualizar el embed
db.collection('eventos').get()
  .then(snapshot => {
    if (snapshot.empty) {
      console.log('⚠️  No hay documentos en la colección eventos');
      process.exit(0);
    }

    const doc = snapshot.docs[0];
    const data = doc.data();
    console.log(`📄 Documento encontrado: ${data.descripcion || 'sin nombre'}`);

    // Actualizar el embed con la nueva URL
    const embeds = data.embeds || [];
    if (embeds.length > 0) {
      embeds[0].url = 'https://tvf90.com/online.php?stream=espn';
      embeds[0].nombre = 'ESPN';

      return doc.ref.update({ embeds: embeds })
        .then(() => {
          console.log('✅ URL actualizada a: https://tvf90.com/online.php?stream=espn');
          process.exit(0);
        });
    } else {
      console.log('⚠️  No hay embeds en el documento');
      process.exit(0);
    }
  })
  .catch(e => {
    console.error('❌ Error:', e.message);
    process.exit(1);
  });
EOF

# Instalar firebase-admin si no está
if [ ! -d "node_modules/firebase-admin" ]; then
  npm install firebase-admin@12 --silent
fi

echo ""
echo "🔎 Ejecutando actualización..."
node update-url.js

echo ""
echo "🔎 Verificando PlayerScreen.kt:"
grep -c "esPaginaDinamica" "$PKG_DIR/ui/PlayerScreen.kt" || echo "  ✓ Fix 28g revertido (helper eliminado)"
grep -c "withTimeoutOrNull(15000L)" "$PKG_DIR/ui/PlayerScreen.kt" || echo "  ✓ Timeout eliminado"

echo ""
echo "✅✅✅ Fix 28h completo — revertido y URL actualizada"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"