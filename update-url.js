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
