#!/bin/bash
set -e

echo "🔧 Configurando automatización de partidos..."

mkdir -p .github/workflows
mkdir -p scripts

cat > .github/workflows/fetch-fixtures.yml << 'YAML_EOF'
name: Fetch Fixtures

on:
  schedule:
    - cron: '0 */6 * * *'
    - cron: '*/10 14-23,0-3 * * *'
  workflow_dispatch:

jobs:
  fetch:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm install firebase-admin node-fetch@3

      - name: Run fetch script
        env:
          API_SPORTS_KEY: ${{ secrets.API_SPORTS_KEY }}
          FIREBASE_SERVICE_ACCOUNT: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
        run: node scripts/fetch-fixtures.js
YAML_EOF

echo "✅ Workflow creado: .github/workflows/fetch-fixtures.yml"

cat > scripts/fetch-fixtures.js << 'JS_EOF'
const admin = require('firebase-admin');
const fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));

const API_KEY = process.env.API_SPORTS_KEY;
const SA_JSON = process.env.FIREBASE_SERVICE_ACCOUNT;
const API_BASE = 'https://v3.football.api-sports.io';

const LIGAS_PERMITIDAS = new Set([
  39, 140, 135, 78, 61, 94, 88, 2, 3, 848,
  242, 262, 128, 71, 239, 265, 281, 268,
  34, 32, 9, 4, 1, 10,
]);

if (!SA_JSON) {
  console.error('❌ Falta FIREBASE_SERVICE_ACCOUNT');
  process.exit(1);
}

const serviceAccount = JSON.parse(SA_JSON);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

function fechaHoy() {
  return new Date().toISOString().slice(0, 10);
}
function fechaSuma(dias) {
  const d = new Date();
  d.setDate(d.getDate() + dias);
  return d.toISOString().slice(0, 10);
}

function horaLocal(isoString) {
  try {
    const d = new Date(isoString);
    const h = String(d.getUTCHours()).padStart(2, '0');
    const m = String(d.getUTCMinutes()).padStart(2, '0');
    return `${h}:${m}`;
  } catch (e) {
    return '--:--';
  }
}

async function apiGet(path) {
  const url = `${API_BASE}${path}`;
  console.log(`📡 GET ${path}`);
  const resp = await fetch(url, {
    headers: { 'x-apisports-key': API_KEY },
  });
  if (!resp.ok) {
    throw new Error(`API error ${resp.status}: ${await resp.text()}`);
  }
  const json = await resp.json();
  const remaining = resp.headers.get('x-ratelimit-requests-remaining');
  console.log(`   → OK · remaining: ${remaining}`);
  if (json.errors && Object.keys(json.errors).length > 0) {
    console.warn(`   ⚠️ API errors:`, json.errors);
  }
  return json;
}

async function fetchFixturesPorFecha(fecha) {
  const json = await apiGet(`/fixtures?date=${fecha}`);
  const todos = json.response || [];
  console.log(`   ${todos.length} partidos totales, filtrando ligas...`);

  const filtrados = todos.filter(p => {
    const ligaId = p.league?.id;
    return LIGAS_PERMITIDAS.has(ligaId);
  });
  console.log(`   ${filtrados.length} partidos en ligas permitidas`);

  return filtrados.map(p => {
    const fixture = p.fixture || {};
    const teams = p.teams || {};
    const goals = p.goals || {};
    const league = p.league || {};
    const status = fixture.status || {};

    return {
      fixtureId: fixture.id,
      fecha: fixture.date ? fixture.date.slice(0, 10) : fecha,
      hora: horaLocal(fixture.date || ''),
      timestamp: fixture.timestamp || 0,
      equipoLocal: teams.home?.name || '',
      equipoVisitante: teams.away?.name || '',
      logoLocal: teams.home?.logo || '',
      logoVisitante: teams.away?.logo || '',
      liga: league.name || '',
      ligaId: league.id || 0,
      ligaPais: league.country || '',
      ligaRonda: league.round || '',
      ligaLogo: league.logo || '',
      ligaBandera: league.flag || '',
      estado: status.short || 'NS',
      estadoLargo: status.long || 'Not Started',
      minuto: status.elapsed || 0,
      golesLocal: goals.home ?? null,
      golesVisitante: goals.away ?? null,
    };
  });
}

async function fetchLiveScores() {
  const json = await apiGet('/fixtures?live=all');
  const todos = json.response || [];
  const filtrados = todos.filter(p => LIGAS_PERMITIDAS.has(p.league?.id));
  console.log(`   ${filtrados.length} partidos en vivo de nuestras ligas`);
  if (filtrados.length === 0) return null;

  const liveMap = {};
  for (const p of filtrados) {
    const fixture = p.fixture || {};
    const goals = p.goals || {};
    const status = fixture.status || {};
    liveMap[fixture.id] = {
      golesLocal: goals.home ?? null,
      golesVisitante: goals.away ?? null,
      minuto: status.elapsed || 0,
      estado: status.short || 'NS',
    };
  }
  return liveMap;
}

async function main() {
  if (!API_KEY) {
    console.error('❌ Falta API_SPORTS_KEY');
    process.exit(1);
  }

  const trigger = process.env.GITHUB_EVENT_NAME || 'manual';
  const hora = new Date().getUTCHours();
  const esLive = (hora >= 14 || hora <= 3);

  console.log(`🚀 Trigger: ${trigger}`);
  console.log(`🔴 Modo: ${esLive ? 'LIVE' : 'FIXTURES'}`);

  const hoy = fechaHoy();
  const manana = fechaSuma(1);
  const pasado = fechaSuma(2);

  console.log(`\n📅 Trayendo fixtures de ${hoy}, ${manana}, ${pasado}...`);

  const [partidosHoy, partidosManana, partidosPasado] = await Promise.all([
    fetchFixturesPorFecha(hoy),
    fetchFixturesPorFecha(manana),
    fetchFixturesPorFecha(pasado),
  ]);

  const batch = db.batch();

  batch.set(db.collection('partidos_auto').doc(hoy), {
    fecha: hoy,
    partidos: partidosHoy,
    actualizado: admin.firestore.FieldValue.serverTimestamp(),
    total: partidosHoy.length,
  });

  batch.set(db.collection('partidos_auto').doc(manana), {
    fecha: manana,
    partidos: partidosManana,
    actualizado: admin.firestore.FieldValue.serverTimestamp(),
    total: partidosManana.length,
  });

  batch.set(db.collection('partidos_auto').doc(pasado), {
    fecha: pasado,
    partidos: partidosPasado,
    actualizado: admin.firestore.FieldValue.serverTimestamp(),
    total: partidosPasado.length,
  });

  await batch.commit();
  console.log(`\n✅ Guardados: ${partidosHoy.length} hoy, ${partidosManana.length} mañana, ${partidosPasado.length} pasado`);

  if (esLive) {
    console.log(`\n🔴 Trayendo live scores...`);
    const live = await fetchLiveScores();
    if (live && Object.keys(live).length > 0) {
      await db.collection('partidos_auto').doc('_live').set({
        live,
        actualizado: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`✅ Live scores actualizados: ${Object.keys(live).length} partidos en vivo`);
    } else {
      console.log(`ℹ️ Sin partidos en vivo ahora`);
    }
  }

  console.log('\n🎉 Done');
}

main().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});
JS_EOF

echo "✅ Script creado: scripts/fetch-fixtures.js"

if [ ! -f "package.json" ]; then
  cat > package.json << 'PKG_EOF'
{
  "name": "futtv-automation",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "fetch": "node scripts/fetch-fixtures.js"
  }
}
PKG_EOF
  echo "✅ package.json creado"
else
  echo "ℹ️ package.json ya existe"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅✅✅ Setup automatización completo"
echo "═══════════════════════════════════════════════════════"
