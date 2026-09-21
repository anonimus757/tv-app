#!/bin/bash
set -e

RC="app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
[ ! -f "$RC" ] && { echo "❌ No existe $RC"; exit 1; }
cp "$RC" "${RC}.bak.apikeyprop.$(date +%s)"
echo "✅ Backup: ${RC}.bak.apikeyprop.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# PASO 1: Agregar apiSportsKey al data class AppConfig
# ═══════════════════════════════════════════════════════════
ancla_telegram = '''    // 🆕 Soporte
    val telegramUrl: String = "https://t.me/futtvsoporte"
)'''

nuevo_telegram = '''    // 🆕 Soporte
    val telegramUrl: String = "https://t.me/futtvsoporte",
    // 🆕 API-Sports (Firestore: config/app → apiSportsKey)
    val apiSportsKey: String = ""
)'''

if ancla_telegram in c:
    c = c.replace(ancla_telegram, nuevo_telegram, 1)
    print("✅ Paso 1: apiSportsKey agregado a AppConfig")
else:
    print("❌ Paso 1: no encontré el ancla de telegramUrl en AppConfig")
    raise SystemExit(1)

# ═══════════════════════════════════════════════════════════
# PASO 2: Parsear apiSportsKey en parsearConfig
# ═══════════════════════════════════════════════════════════
ancla_parseo = '''            telegramUrl = data["telegramUrl"] as? String ?: "https://t.me/futtvsoporte"
        )'''

nuevo_parseo = '''            telegramUrl = data["telegramUrl"] as? String ?: "https://t.me/futtvsoporte",
            apiSportsKey = data["apiSportsKey"] as? String ?: ""
        )'''

if ancla_parseo in c:
    c = c.replace(ancla_parseo, nuevo_parseo, 1)
    print("✅ Paso 2: parseo de apiSportsKey agregado")
else:
    print("❌ Paso 2: no encontré el ancla de telegramUrl en parsearConfig")
    raise SystemExit(1)

# ═══════════════════════════════════════════════════════════
# PASO 3: Inyectar setApiKey() después de _config.value = cfg
# ═══════════════════════════════════════════════════════════
ancla_setvalue = '''                        _config.value = cfg
                        guardarCacheLocal(context, cfg)
                        Log.d(TAG, "✅ Config actualizada desde Firestore")'''

nuevo_setvalue = '''                        _config.value = cfg
                        guardarCacheLocal(context, cfg)
                        // 🆕 Propagar API key al repositorio de API-Sports
                        try {
                            ApiSportsRepository.setApiKey(cfg.apiSportsKey)
                            Log.d(TAG, "🔑 apiSportsKey propagada (${if (cfg.apiSportsKey.isBlank()) "VACÍA" else "OK"})")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ setApiKey fail: ${e.message}")
                        }
                        Log.d(TAG, "✅ Config actualizada desde Firestore")'''

if ancla_setvalue in c:
    c = c.replace(ancla_setvalue, nuevo_setvalue, 1)
    print("✅ Paso 3: setApiKey inyectado después de _config.value = cfg")
else:
    print("⚠️ Paso 3: no encontré el ancla exacta. Probando variante...")
    # Fallback: buscar solo la línea "_config.value = cfg"
    ancla_alt = '                        _config.value = cfg'
    if ancla_alt in c:
        insercion = ancla_alt + '''
                        // 🆕 Propagar API key al repositorio de API-Sports
                        try { ApiSportsRepository.setApiKey(cfg.apiSportsKey) } catch (_: Exception) {}'''
        c = c.replace(ancla_alt, insercion, 1)
        print("✅ Paso 3 (variante): setApiKey inyectado")
    else:
        print("❌ Paso 3: no pude inyectar setApiKey. Revisá el archivo.")
        raise SystemExit(1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("✅✅✅ RemoteConfigRepository.kt actualizado")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

checks = {
    "apiSportsKey en AppConfig": 'val apiSportsKey: String = ""' in final,
    "apiSportsKey en parsearConfig": 'data["apiSportsKey"] as? String' in final,
    "setApiKey() llamado": 'ApiSportsRepository.setApiKey' in final,
}
for k, v in checks.items():
    print(f"   {'✅' if v else '❌'} {k}")
PYEOF

echo ""
echo "Verificá:"
echo "  grep -n 'apiSportsKey\\|setApiKey' app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
