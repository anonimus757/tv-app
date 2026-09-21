#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

echo "📂 Backups disponibles:"
ls -t ${PLAYER}.bak.* 2>/dev/null | head -10

# Usar el backup de ANTES del script de quitar-diag
BACKUP=$(ls -t ${PLAYER}.bak.quitardiag.* 2>/dev/null | head -1)

if [ -z "$BACKUP" ]; then
    echo "⚠️ No hay backup de quitardiag. Buscando el anterior..."
    BACKUP=$(ls -t ${PLAYER}.bak.pulsesimple.* 2>/dev/null | head -1)
fi

if [ -z "$BACKUP" ]; then
    echo "❌ No hay backup útil. Necesito que me pases el PlayerScreen.kt actual."
    exit 1
fi

cp "$BACKUP" "$PLAYER"
echo "✅ Restaurado desde: $BACKUP"
echo ""
echo "Verificá que compile AHORA (sin tocar nada):"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
