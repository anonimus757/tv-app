#!/bin/bash
set -e

echo "🗑️  Buscando branches temporales..."

# Listar branches que empiezan con context-temp-
BRANCHES=$(git branch -r | grep "origin/context-temp-" | sed 's|origin/||' | tr -d ' ')

if [ -z "$BRANCHES" ]; then
    echo "ℹ️  No hay branches temporales para borrar"
    exit 0
fi

echo "Branches encontrados:"
echo "$BRANCHES"
echo ""

for BRANCH in $BRANCHES; do
    echo "🗑️  Borrando branch: $BRANCH"
    git push origin --delete "$BRANCH" 2>/dev/null || echo "   (ya estaba borrado)"
    
    # Borrar local también
    git branch -D "$BRANCH" 2>/dev/null || true
done

echo ""
echo "✅ Volviendo a main..."
git checkout main 2>/dev/null || git checkout master

echo ""
echo "✅✅✅ Contexto temporal borrado de GitHub"
echo ""
echo "🔗 Verificar en:"
echo "   https://github.com/anonimus757/tv-app/branches"
echo ""
echo "   (no debería aparecer ningún 'context-temp-*')"