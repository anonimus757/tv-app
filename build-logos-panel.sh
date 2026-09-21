#!/bin/bash
set -e

PLAYER="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$PLAYER" "${PLAYER}.bak.logospanel.$(date +%s)"
echo "✅ Backup"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

cambios = 0

# ─── 1. Cambiar la llamada al PanelItem en PanelLateral ───
# Preferir logo del canal, sino imagen del evento
viejo_llamada = '''PanelItem(
                        modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                        titulo = emb.nombre,
                        subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                        seleccionado = emb.url == embedActual.url,
                        miniaturaUrl = evento.imagen,
                        onClick = { onCanalClick(emb) }
                    )'''

nuevo_llamada = '''PanelItem(
                        modifier = if (isFirst) Modifier.focusRequester(primerItemFocus) else Modifier,
                        titulo = emb.nombre,
                        subtitulo = if (emb.url == embedActual.url) "Reproduciendo ahora" else null,
                        seleccionado = emb.url == embedActual.url,
                        miniaturaUrl = evento.imagen,
                        logoCanal = emb.logo,
                        onClick = { onCanalClick(emb) }
                    )'''

if viejo_llamada in c:
    c = c.replace(viejo_llamada, nuevo_llamada, 1)
    print("✅ Llamada actualizada (agrega logoCanal = emb.logo)")
    cambios += 1
else:
    print("⚠️ No matcheó la llamada exacta. Buscando variantes...")
    # Variante con espacios distintos
    patron = re.compile(
        r'(PanelItem\(\s*\n\s*modifier\s*=\s*if\s*\(isFirst\)[^,]+,\s*\n\s*titulo\s*=\s*emb\.nombre,\s*\n\s*subtitulo[^,]+,\s*\n\s*seleccionado[^,]+,\s*\n\s*miniaturaUrl\s*=\s*evento\.imagen,\s*\n)(\s*onClick)',
        re.DOTALL
    )
    def repl(m):
        return m.group(1) + '                        logoCanal = emb.logo,\n' + m.group(2)
    c_nuevo, n = patron.subn(repl, c, count=1)
    if n > 0:
        c = c_nuevo
        print("✅ Variante aplicada")
        cambios += 1
    else:
        print("❌ No pude matchear la llamada")

# ─── 2. Modificar la firma de PanelItem para aceptar logoCanal ───
viejo_firma = '''@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit,
    miniaturaUrl: String? = null
) {'''

nuevo_firma = '''@Composable
private fun PanelItem(
    modifier: Modifier = Modifier,
    titulo: String,
    subtitulo: String?,
    seleccionado: Boolean,
    onClick: () -> Unit,
    miniaturaUrl: String? = null,
    logoCanal: String = ""
) {'''

if viejo_firma in c:
    c = c.replace(viejo_firma, nuevo_firma, 1)
    print("✅ Firma de PanelItem actualizada")
    cambios += 1
else:
    print("⚠️ No matcheó la firma de PanelItem")

# ─── 3. Modificar el bloque visual de la miniatura dentro de PanelItem ───
# Buscar el bloque "if (miniaturaUrl != null && miniaturaUrl.isNotBlank())"
viejo_bloque = '''        if (miniaturaUrl != null && miniaturaUrl.isNotBlank()) {
            Box(
                Modifier
                    .size(width = 76.dp, height = 46.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFF1A1A22)),
                contentAlignment = Alignment.Center
            ) {
                coil.compose.AsyncImage(
                    model = miniaturaUrl,
                    contentDescription = null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                if (seleccionado) {
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))
                            )
                        )
                    )
                    Box(
                        Modifier
                            .align(Alignment.BottomStart)
                            .padding(4.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF4ADE80))
                            .padding(horizontal = 5.dp, vertical = 1.dp)
                    ) {
                        Text("●", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
        } else {'''

nuevo_bloque = '''        // Preferir logo del canal si existe, sino imagen del evento
        val tieneLogo = logoCanal.isNotBlank()
        val tieneMiniatura = miniaturaUrl != null && miniaturaUrl.isNotBlank()
        
        if (tieneLogo || tieneMiniatura) {
            Box(
                Modifier
                    .size(width = 76.dp, height = 46.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (tieneLogo) Color(0xFF0F0F15) else Color(0xFF1A1A22))
                    .border(
                        if (tieneLogo) 1.dp else 0.dp,
                        if (tieneLogo) Color.White.copy(alpha = 0.08f) else Color.Transparent,
                        RoundedCornerShape(8.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                coil.compose.AsyncImage(
                    model = if (tieneLogo) logoCanal else miniaturaUrl,
                    contentDescription = null,
                    contentScale = if (tieneLogo) 
                        androidx.compose.ui.layout.ContentScale.Fit 
                    else 
                        androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = if (tieneLogo) 
                        Modifier.size(width = 60.dp, height = 34.dp) 
                    else 
                        Modifier.fillMaxSize()
                )
                
                // Badge de "reproduciendo" si está seleccionado
                if (seleccionado) {
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))
                            )
                        )
                    )
                    Box(
                        Modifier
                            .align(Alignment.BottomStart)
                            .padding(4.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF4ADE80))
                            .padding(horizontal = 5.dp, vertical = 1.dp)
                    ) {
                        Text("●", color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
        } else {'''

if viejo_bloque in c:
    c = c.replace(viejo_bloque, nuevo_bloque, 1)
    print("✅ Bloque visual de miniatura actualizado para mostrar logos")
    cambios += 1
else:
    print("⚠️ No matcheó el bloque visual exacto. Probando variante...")
    # Variante: buscar cualquier bloque con "size(width = 76.dp, height = 46.dp)"
    idx = c.find('size(width = 76.dp, height = 46.dp)')
    if idx > 0:
        # Buscar el inicio del "if" antes
        inicio = c.rfind('if (miniaturaUrl', 0, idx)
        if inicio > 0:
            # Buscar el cierre del if + else
            fin = c.find('} else {', idx)
            if fin > 0:
                bloque_viejo = c[inicio:fin + len('} else {')]
                c = c.replace(bloque_viejo, nuevo_bloque.strip(), 1)
                print("✅ Variante aplicada por búsqueda de patrón")
                cambios += 1

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

print("")
print(f"✅ Total cambios aplicados: {cambios}")

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

checks = {
    "logoCanal = emb.logo": "logoCanal = emb.logo" in final,
    "logoCanal: String": "logoCanal: String" in final,
    "tieneLogo": "tieneLogo" in final,
}
print("")
print("=== Verificación ===")
for k, v in checks.items():
    print(f"  {'✅' if v else '❌'} {k}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
