#!/bin/bash
set -e

MODELS="app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
echo "📂 Backups disponibles:"
ls -t ${MODELS}.bak.* 2>/dev/null | head -5

# Restaurar el backup más reciente (antes de romperlo)
BACKUP=$(ls -t ${MODELS}.bak.* 2>/dev/null | head -1)
if [ -z "$BACKUP" ]; then
    echo "❌ No hay backup. Necesito que me pases el contenido original."
    exit 1
fi
cp "$BACKUP" "$MODELS"
echo "✅ Restaurado desde: $BACKUP"

# Ahora aplicamos el fix con python usando find/replace literal (sin regex)
python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

print("=== ANTES ===")
print(c[:600])
print("=============")

# Bloque exacto actual (con cualquier comentario al final)
viejo = '''data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "" // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY
)'''

nuevo = '''data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "", // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY

    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null
)'''

if viejo in c:
    c = c.replace(viejo, nuevo, 1)
    print("✅ Reemplazo literal OK")
else:
    # Intento alternativo: sin comentario final
    viejo2 = '''data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = ""
)'''
    if viejo2 in c:
        c = c.replace(viejo2, nuevo, 1)
        print("✅ Reemplazo alternativo OK (sin comentario)")
    else:
        print("❌ No matcheó ninguna variante. Mostrando zona 'data class Evento':")
        idx = c.find("data class Evento")
        if idx >= 0:
            print(c[idx:idx+500])
        raise SystemExit(1)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print("=== DESPUÉS ===")
with open(fp, 'r', encoding='utf-8') as f:
    print(f.read()[:700])
print("===============")
PYEOF

echo ""
echo "✅✅✅ Models.kt limpio y con campos API-Sports"
echo ""
echo "Verificá:"
echo "  grep -n 'equipoLocal\\|fixtureId' app/src/main/java/com/anonimus757/tvapp/data/Models.kt"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
