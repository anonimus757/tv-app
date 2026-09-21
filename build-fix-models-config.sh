#!/bin/bash
set -e

echo "🔧 Fix Models.kt + RemoteConfigRepository.kt + init de API key"

# ═══════════════════════════════════════════════════════════
# 1. MODELS.KT: agregar campos al data class Evento
# ═══════════════════════════════════════════════════════════
MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
[ ! -f "$MODELS" ] && { echo "❌ No existe $MODELS"; exit 1; }
cp "$MODELS" "${MODELS}.bak.fix.$(date +%s)"
echo "✅ Backup: ${MODELS}.bak.fix.$(date +%s)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Buscar el data class Evento (tolerante a comentarios al final del fecha)
import re
patron = re.compile(
    r'(data\s+class\s+Evento\s*\([^)]*?)(\)\s*(?:/\*.*?\*/)?\s*$)',
    re.MULTILINE | re.DOTALL
)
m = patron.search(c)
if not m:
    print("❌ No encontré data class Evento.")
    raise SystemExit(1)

cuerpo = m.group(1)
if "equipoLocal" in cuerpo:
    print("ℹ️ Evento ya tiene equipoLocal. Nada que hacer.")
else:
    # Insertar los campos antes del cierre
    cuerpo_strip = cuerpo.rstrip()
    if not cuerpo_strip.endswith(","):
        cuerpo_strip += ","
    nuevo_cuerpo = cuerpo_strip + '''

    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null
'''
    c = c[:m.start(1)] + nuevo_cuerpo + c[m.end(1):]
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ Models.kt: Evento extendido con equipoLocal, equipoVisitante, liga, fixtureId")
PYEOF

# ═══════════════════════════════════════════════════════════
# 2. REMOTECONFIG: agregar apiSportsKey + init
# ═══════════════════════════════════════════════════════════
RC="app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
[ ! -f "$RC" ] && { echo "❌ No existe $RC"; exit 1; }
cp "$RC" "${RC}.bak.fix.$(date +%s)"
echo "✅ Backup: ${RC}.bak.fix.$(date +%s)"

python3 << 'PYEOF'
import re
fp = "app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# 2a. Agregar apiSportsKey al data class RemoteConfig
patron = re.compile(
    r'(data\s+class\s+RemoteConfig\s*\([^)]*?)(\)\s*(?:/\*.*?\*/)?\s*$)',
    re.MULTILINE | re.DOTALL
)
m = patron.search(c)
if not m:
    print("⚠️ No encontré data class RemoteConfig. Buscando otra firma...")
    # Buscar por nombre de clase alternativo
    m2 = re.search(r'(data\s+class\s+\w*Config\w*\s*\([^)]*?)(\)\s*$)', c, re.MULTILINE | re.DOTALL)
    if m2:
        m = m2
    else:
        print("❌ No pude encontrar el data class de config. Abortando RemoteConfig.")
        raise SystemExit(0)

cuerpo = m.group(1)
if "apiSportsKey" in cuerpo:
    print("ℹ️ RemoteConfig ya tiene apiSportsKey")
else:
    cuerpo_strip = cuerpo.rstrip()
    if not cuerpo_strip.endswith(","):
        cuerpo_strip += ","
    nuevo_cuerpo = cuerpo_strip + '\n    val apiSportsKey: String = "" // API-Sports (Firestore: config/app)'
    c = c[:m.start(1)] + nuevo_cuerpo + c[m.end(1):]
    print("✅ RemoteConfigRepository.kt: campo apiSportsKey agregado")

# 2b. Llamar a ApiSportsRepository.setApiKey() cuando llega la config
# Buscar donde se asigna el objeto config al StateFlow interno
# Patrón típico: "_config.value = ..." o "configState.value = ..."
# Insertamos después de asignar la config un setApiKey
patron_set = re.search(
    r'((?:_config|_state|configState|_configState)\.value\s*=\s*[^\n]+)\n',
    c
)
if patron_set:
    linea = patron_set.group(1)
    insercion = linea + "\n                try { com.anonimus757.tvapp.data.ApiSportsRepository.setApiKey(" + (re.search(r'\.value\s*=\s*(\w+)', linea).group(1) if re.search(r'\.value\s*=\s*(\w+)', linea) else 'cfg') + ".apiSportsKey) } catch (_: Exception) {}\n"
    c = c.replace(linea, insercion, 1)
    print("✅ RemoteConfigRepository.kt: setApiKey() inyectado tras asignar config")
else:
    print("⚠️ No encontré el patrón _config.value = ... para inyectar setApiKey.")
    print("   Agregá manualmente esta línea después de asignar la config:")
    print('   ApiSportsRepository.setApiKey(config.apiSportsKey)')

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ RemoteConfigRepository.kt actualizado")
PYEOF

echo ""
echo "✅✅✅ Fix Models + RemoteConfig completo"
echo ""
echo "Verificá:"
echo "  grep -n 'equipoLocal\\|fixtureId' app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
echo "  grep -n 'apiSportsKey' app/src/main/java/com/anonimus757/tvapp/data/RemoteConfigRepository.kt"
echo ""
echo "Compilá (OJO con el ./):"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
