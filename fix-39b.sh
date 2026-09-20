#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
  echo "❌ No estás en la raíz del proyecto"
  exit 1
fi

FILE="app/src/main/java/com/anonimus757/tvapp/data/FirebaseManager.kt"

echo "📝 Verificando FirebaseManager.kt..."

# Guarda: si ya tiene la función, no hacemos nada
if grep -q "private suspend fun suscribirseAlTopic" "$FILE"; then
  echo "ℹ️  La función suscribirseAlTopic ya existe"
  exit 0
fi

echo "📝 Agregando función suscribirseAlTopic..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/FirebaseManager.kt"
with open(file_path) as f:
    content = f.read()

# Buscar el bloque de obtenerTokenFcm y agregar la función DESPUÉS
# Uso un patrón flexible para encontrar el cierre de la función
old_block = '''    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }'''

new_block = '''    private suspend fun obtenerTokenFcm() {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            fcmToken = token
            Log.d(TAG, "🔔 FCM token: ${token.take(20)}...")
        } catch (e: Exception) {
            Log.e(TAG, "❌ FCM token fail: ${e.message}")
        }
    }

    /**
     * Suscribe al topic "futtv_todos".
     * Todos los dispositivos con FutTV reciben los push que se mandan a ese topic.
     * Es lo que permite que el botón "Enviar notificación" del Sheets llegue a todos.
     */
    private suspend fun suscribirseAlTopic() {
        try {
            FirebaseMessaging.getInstance().subscribeToTopic("futtv_todos").await()
            Log.d(TAG, "✅ Suscripto al topic futtv_todos")
            DebugLog.log("✅ Suscripto a notificaciones")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Subscribe topic fail: ${e.message}")
            DebugLog.log("❌ Subscribe topic fail: ${e.message}")
        }
    }'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(file_path, "w") as f:
        f.write(content)
    print("✅ Función suscribirseAlTopic agregada")
else:
    print("⚠️  No encontré el bloque obtenerTokenFcm exacto. Buscando variante...")
    # Intento alternativo: buscar solo el cierre de obtenerTokenFcm
    import re
    pattern = r'(private suspend fun obtenerTokenFcm\(\) \{.*?\n    \})'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        insert_after = match.group(1)
        content = content.replace(insert_after, insert_after + '''

    private suspend fun suscribirseAlTopic() {
        try {
            FirebaseMessaging.getInstance().subscribeToTopic("futtv_todos").await()
            Log.d(TAG, "✅ Suscripto al topic futtv_todos")
            DebugLog.log("✅ Suscripto a notificaciones")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Subscribe topic fail: ${e.message}")
            DebugLog.log("❌ Subscribe topic fail: ${e.message}")
        }
    }''')
        with open(file_path, "w") as f:
            f.write(content)
        print("✅ Función suscribirseAlTopic agregada (regex)")
    else:
        print("❌ No se pudo agregar la función. Revisá el archivo manualmente.")
        exit(1)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "private suspend fun suscribirseAlTopic" "$FILE" && echo "  ✓ Función suscribirseAlTopic existe"
grep -q "suscribirseAlTopic()" "$FILE" && echo "  ✓ Llamada a suscribirseAlTopic existe"

echo ""
echo "📄 Contenido de la función en el archivo:"
grep -A 12 "private suspend fun suscribirseAlTopic" "$FILE" | head -15

echo ""
echo "✅✅✅ Fix 39b completo"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"