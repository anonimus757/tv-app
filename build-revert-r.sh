#!/bin/bash
set -e

EXTRACTOR="app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
BACKUP="${EXTRACTOR}.bak.$(date +%s)"
cp "$EXTRACTOR" "$BACKUP"
echo "✅ Backup antes de revertir: $BACKUP"

python3 << 'PYEOF'
import re
fp = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Borrar el helper decodificarWrapperR (con su comentario)
c = re.sub(
    r'\n\s*/\*\*\s*\n\s*\* Si la URL es un wrapper.*?\n\s*private fun decodificarWrapperR.*?\n\s*\}\n',
    '\n', c, flags=re.DOTALL
)

# Borrar el atajo dentro de extraerYTestear
c = re.sub(
    r'\n\s*// ⬇️ ATAJO: si la URL es un wrapper.*?\n\s*\}\n',
    '\n', c, flags=re.DOTALL
)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ Revert aplicado")
PYEOF

echo "✅✅✅ Revert completo"
