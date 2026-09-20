#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

echo "📝 Fix: declarar variable 'logs' y conectarla a addLog..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ── 1) Declarar 'logs' junto a los otros estados ──
if "var logs by remember" not in content:
    # Buscar el ancla cerca del resto de estados
    ancla = "    var mostrarLogPanel by remember { mutableStateOf(false) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + "\n    var logs by remember { mutableStateOf(listOf<String>()) }",
            1
        )
        print("✅ Variable 'logs' declarada")
    else:
        # Fallback: buscar otro ancla
        ancla2 = "    var webViewTimeout by remember { mutableStateOf(false) }"
        if ancla2 in content:
            content = content.replace(
                ancla2,
                ancla2 + "\n    var logs by remember { mutableStateOf(listOf<String>()) }\n    var mostrarLogPanel by remember { mutableStateOf(false) }",
                1
            )
            print("✅ Variables declaradas (variante)")
        else:
            print("❌ No encontré dónde declarar 'logs'")

# ── 2) Conectar addLog para que guarde en la lista ──
old_addlog = '''    val addLog: (String) -> Unit = { msg -> Log.d(TAG, msg) }'''
new_addlog = '''    val addLog: (String) -> Unit = { msg ->
        Log.d(TAG, msg)
        logs = (logs + msg).takeLast(50)
    }'''

if old_addlog in content:
    content = content.replace(old_addlog, new_addlog)
    print("✅ addLog conectado a la lista")
elif "logs = (logs + msg).takeLast(50)" in content:
    print("ℹ️  addLog ya estaba conectado")
else:
    print("⚠️  No encontré addLog, buscando variante...")
    import re
    pattern = r'val addLog: \(String\) -> Unit = \{ msg -> Log\.d\(TAG, msg\) \}'
    if re.search(pattern, content):
        content = re.sub(pattern, new_addlog, content)
        print("✅ addLog reemplazado (regex)")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "var logs by remember" "$FILE" && echo "  ✓ Variable logs declarada"
grep -q "logs = (logs + msg).takeLast" "$FILE" && echo "  ✓ addLog conectado"

echo ""
echo "✅✅✅ Fix aplicado"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"