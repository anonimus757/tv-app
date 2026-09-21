#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.streamcut.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Aumentar buffer (8/45/2/5 → 15/90/3/10)
viejo1 = '.setBufferDurationsMs(8000, 45000, 2000, 5000)'
nuevo1 = '.setBufferDurationsMs(15000, 90000, 3000, 10000)'
if viejo1 in c:
    c = c.replace(viejo1, nuevo1, 1)
    print("✅ Buffer aumentado (min=15s, max=90s, play=3s, rebuf=10s)")
else:
    print("⚠️ No matcheó buffer")

# 2. Aumentar timeouts (20000 → 30000)
viejo2 = '.setConnectTimeoutMs(20000)\n                    .setReadTimeoutMs(20000)'
nuevo2 = '.setConnectTimeoutMs(30000)\n                    .setReadTimeoutMs(30000)'
if viejo2 in c:
    c = c.replace(viejo2, nuevo2, 1)
    print("✅ Timeouts aumentados a 30s")
else:
    print("⚠️ No matcheó timeout principal")

# 3. Aumentar timeouts de respaldo (15000 → 25000)
viejo3 = '.setConnectTimeoutMs(15000)\n                    .setReadTimeoutMs(15000)'
nuevo3 = '.setConnectTimeoutMs(25000)\n                    .setReadTimeoutMs(25000)'
if viejo3 in c:
    c = c.replace(viejo3, nuevo3, 1)
    print("✅ Timeouts respaldo aumentados a 25s")

# 4. Auto-refresh: de 6 min a 5 min (renovar token antes)
viejo4 = 'delay(6 * 60 * 1000L) // 8 minutos'
nuevo4 = 'delay(5 * 60 * 1000L) // 5 minutos (antes de que expire el token)'
if viejo4 in c:
    c = c.replace(viejo4, nuevo4, 1)
    print("✅ Auto-refresh reducido a 5 min")

# 5. Auto-refresh: sin mostrar UI (silencioso)
viejo5 = '''if (fresh != null && fresh != m3u8Url) {
                        cookies = M3u8Extractor.cookieString()
                        // Actualizar el m3u8 SIN mostrar spinner ni cortar el video
                        m3u8Url = fresh
                        addLog("✅ Token renovado silenciosamente")
                    }'''
nuevo5 = '''if (fresh != null && fresh != m3u8Url) {
                        cookies = M3u8Extractor.cookieString()
                        // Actualizar el m3u8 SIN mostrar spinner ni cortar el video
                        m3u8Url = fresh
                        addLog("✅ Token renovado silenciosamente")
                    } else if (fresh == null) {
                        addLog("⚠️ Token no renovado, se reintentará en 5 min")
                    }'''
if viejo5 in c:
    c = c.replace(viejo5, nuevo5, 1)
    print("✅ Log de auto-refresh mejorado")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("✅ PlayerScreen.kt actualizado")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
