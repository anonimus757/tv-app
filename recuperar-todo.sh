#!/bin/bash
set -e

echo "🔍 Verificando el commit con los archivos perdidos..."
git show --name-only fa9e0aa 2>/dev/null | grep -E "\.kt$" | head -30
echo ""
echo "Total de archivos .kt en el commit:"
git show --name-only fa9e0aa 2>/dev/null | grep -c "\.kt$" || echo "0"

echo ""
echo "📥 Restaurando TODOS los archivos desde el commit..."
git checkout fa9e0aa -- .

echo ""
echo "🔎 Verificando restauración..."
echo ""
echo "═══ ARCHIVOS EN UI ═══"
ls -la app/src/main/java/com/anonimus757/tvapp/ui/*.kt 2>/dev/null | grep -v "\.bak" | wc -l
echo "archivos .kt base en ui/"

echo ""
echo "═══ ARCHIVOS EN DATA ═══"
ls -la app/src/main/java/com/anonimus757/tvapp/data/*.kt 2>/dev/null | grep -v "\.bak" | wc -l
echo "archivos .kt base en data/"

echo ""
echo "═══ ARCHIVOS EN NOTIFICATIONS ═══"
ls -la app/src/main/java/com/anonimus757/tvapp/notifications/*.kt 2>/dev/null | grep -v "\.bak" | wc -l
echo "archivos .kt base en notifications/"

echo ""
echo "═══ LISTADO COMPLETO UI ═══"
ls app/src/main/java/com/anonimus757/tvapp/ui/*.kt 2>/dev/null | grep -v "\.bak"

echo ""
echo "═══ LISTADO COMPLETO DATA ═══"
ls app/src/main/java/com/anonimus757/tvapp/data/*.kt 2>/dev/null | grep -v "\.bak"

echo ""
echo "═══ LISTADO COMPLETO NOTIFICATIONS ═══"
ls app/src/main/java/com/anonimus757/tvapp/notifications/*.kt 2>/dev/null | grep -v "\.bak"

echo ""
echo "═══ MAIN ACTIVITY Y OTROS ═══"
ls app/src/main/java/com/anonimus757/tvapp/*.kt 2>/dev/null | grep -v "\.bak"

echo ""
echo "🚀 Ahora commiteando a main para respaldarlos..."
git commit -m "Recuperar v3.1 completa desde branch temporal" 2>&1 | head -5 || echo "(nada que commitear)"

echo ""
echo "☁️  Subiendo a GitHub main..."
git push origin main 2>&1 | head -5

echo ""
echo "✅✅✅ RECUPERACIÓN COMPLETA"
echo ""
echo "🔗 Verificar en GitHub:"
echo "   https://github.com/anonimus757/tv-app"
echo ""
echo "📌 Los archivos .kt ahora están en main y respaldados en GitHub."
