#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

PKG_DIR="app/src/main/java/com/anonimus757/tvapp"

echo "📝 Haciendo Firestore query de diagnóstico..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/EventRepository.kt"
with open(file_path) as f:
    content = f.read()

old_block = '''            val db = FirebaseFirestore.getInstance()
            val snap = db.collection("eventos")
                .whereEqualTo("activo", true)
                .get()
                .await()
            val lista = snap.documents.mapNotNull { parsearEventoFirestore(it) }
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos")
            DebugLog.log("✅ Firestore: ${lista.size} eventos")
            lista'''

new_block = '''            val db = FirebaseFirestore.getInstance()

            // DIAGNÓSTICO: traer TODOS los docs, sin filtro, para ver qué hay
            val snap = db.collection("eventos").get().await()
            val totalDocs = snap.size()
            DebugLog.log("📊 Docs totales en 'eventos': $totalDocs")

            // Loguear la primera doc para ver sus campos reales
            snap.documents.firstOrNull()?.let { doc ->
                val keys = doc.data?.keys?.joinToString(", ") ?: "(sin data)"
                DebugLog.log("📄 Campos: $keys")
                val activoVal = doc.get("activo")
                DebugLog.log("🔎 activo = $activoVal (${activoVal?.javaClass?.simpleName})")
            }

            // Filtrar por activo==true o activo==null (tolerante) y parsear
            val lista = snap.documents
                .filter { doc ->
                    val activo = doc.get("activo")
                    activo == null || activo == true
                }
                .mapNotNull { parsearEventoFirestore(it) }

            DebugLog.log("✅ Parseados: ${lista.size} (de $totalDocs)")
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos ($totalDocs docs totales)")
            lista'''

if old_block not in content:
    print("⚠️  No encontré el bloque exacto. Ya puede estar modificado.")
    print("    Buscando alternativas...")
    # Intento alternativo: solo reemplazar la query
    content = content.replace(
        '''            val snap = db.collection("eventos")
                .whereEqualTo("activo", true)
                .get()
                .await()
            val lista = snap.documents.mapNotNull { parsearEventoFirestore(it) }
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos")
            DebugLog.log("✅ Firestore: ${lista.size} eventos")
            lista''',
        '''            val snap = db.collection("eventos").get().await()
            val totalDocs = snap.size()
            DebugLog.log("📊 Docs totales en 'eventos': $totalDocs")
            snap.documents.firstOrNull()?.let { doc ->
                val keys = doc.data?.keys?.joinToString(", ") ?: "(sin data)"
                DebugLog.log("📄 Campos: $keys")
                val activoVal = doc.get("activo")
                DebugLog.log("🔎 activo = $activoVal (${activoVal?.javaClass?.simpleName})")
            }
            val lista = snap.documents
                .filter { doc ->
                    val activo = doc.get("activo")
                    activo == null || activo == true
                }
                .mapNotNull { parsearEventoFirestore(it) }
            DebugLog.log("✅ Parseados: ${lista.size} (de $totalDocs)")
            Log.d(TAG, "✅ Firestore: ${lista.size} eventos ($totalDocs docs totales)")
            lista'''
    )

with open(file_path, "w") as f:
    f.write(content)

print("✅ EventRepository actualizado (query de diagnóstico)")
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "Docs totales en 'eventos'" "$PKG_DIR/data/EventRepository.kt" && echo "  ✓ Query diagnóstico aplicada"

echo ""
echo "✅✅✅ Fix 28e completo — diagnóstico de Firestore"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew clean"
echo "   ./gradlew assembleDebug --no-daemon"