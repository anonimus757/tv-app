// Script opcional: agrega el campo 'fecha' = HOY a todos los eventos
// que no lo tengan. Útil para no perder los eventos existentes.
//
// Uso: node add-fechas.js

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./service-account.json');

const app = initializeApp({
  credential: cert(serviceAccount),
  projectId: 'futtv-ce7f9'
});

const db = getFirestore(app);

function hoy() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

async function main() {
  const snap = await db.collection('eventos').get();
  console.log(`📊 Total eventos: ${snap.size}`);

  let actualizados = 0;
  const batch = db.batch();

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!data.fecha || data.fecha.trim() === '') {
      batch.update(doc.ref, { fecha: hoy() });
      console.log(`📝 ${data.descripcion || doc.id} → fecha: ${hoy()}`);
      actualizados++;
    } else {
      console.log(`✓ ${data.descripcion || doc.id} → ya tiene fecha: ${data.fecha}`);
    }
  }

  if (actualizados > 0) {
    await batch.commit();
    console.log(`\n✅ ${actualizados} eventos actualizados con fecha ${hoy()}`);
  } else {
    console.log('\nℹ️  Todos los eventos ya tenían fecha');
  }
  process.exit(0);
}

main().catch(e => { console.error('❌ Error:', e.message); process.exit(1); });
