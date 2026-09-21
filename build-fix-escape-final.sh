#!/bin/bash
set -e

API="app/src/main/java/com/anonimus757/tvapp/data/ApiSportsRepository.kt"
cp "$API" "${API}.bak.escapefinal.$(date +%s)"
echo "✅ Backup"

# Usamos perl que maneja mejor los escapes
perl -i -pe 's/(?<!\\)\\s/\\\\s/g if /Regex\(/' "$API"

echo ""
echo "=== Verificación (líneas 210-220) ==="
sed -n '210,220p' "$API"
