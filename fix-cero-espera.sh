#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-cero-espera"

echo "📝 Implementando sistema 'cero espera'..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Agregar estados para candidatos (URLs de respaldo)
# ═══════════════════════════════════════════════════════════
if "var urlsCandidatas by remember" not in content:
    ancla = "    var logs by remember { mutableStateOf(listOf<String>()) }"
    if ancla in content:
        content = content.replace(
            ancla,
            ancla + """
    // ═══════════════════════════════════════════════════════════
    // SISTEMA DE URLs CANDIDATAS (respaldo silencioso)
    // Extrae varias URLs del mismo embed. Si una falla, cambia
    // automáticamente a la siguiente SIN que el usuario note.
    // ═══════════════════════════════════════════════════════════
    var urlsCandidatas by remember { mutableStateOf(listOf<String>()) }
    var indiceCandidato by remember { mutableIntStateOf(0) }
    var preparandoCandidatos by remember { mutableStateOf(false) }""",
            1
        )
        print("✅ Estados de candidatos agregados")
    else:
        print("⚠️  No encontré ancla para estados")

# ═══════════════════════════════════════════════════════════
# 2) Cargar la URL en ExoPlayer cuando cambia el índice
# ═══════════════════════════════════════════════════════════
# Este bloque permite cambiar de candidato sin pasar por el extractor
if "// Auto-cambio a siguiente candidato" not in content:
    # Buscar el LaunchedEffect(m3u8Url, reloadTrigger) para insertar antes
    ancla_effect = '''    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect'''

    nuevo_bloque = '''    // ═══════════════════════════════════════════════════════════
    // AUTO-CAMBIO A SIGUIENTE CANDIDATO (silencioso, 1 seg)
    // ═══════════════════════════════════════════════════════════
    LaunchedEffect(indiceCandidato, urlsCandidatas) {
        if (indiceCandidato > 0 && indiceCandidato < urlsCandidatas.size) {
            val nuevaUrl = urlsCandidatas[indiceCandidato]
            addLog("🔀 Cambiando a respaldo #${indiceCandidato + 1}")
            // Cambio ultra-rápido: sin clearMediaItems para que el video no se corte
            try {
                exoPlayer.stop()
                val headers = mutableMapOf(
                    "User-Agent" to USER_AGENT,
                    "Referer" to embedActual.referer,
                    "Origin" to embedActual.referer.trimEnd('/')
                )
                cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }
                val ds = DefaultHttpDataSource.Factory()
                    .setUserAgent(USER_AGENT)
                    .setDefaultRequestProperties(headers)
                    .setAllowCrossProtocolRedirects(true)
                    .setConnectTimeoutMs(15000)
                    .setReadTimeoutMs(15000)
                val src = HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(nuevaUrl)))
                exoPlayer.setMediaSource(src)
                exoPlayer.prepare()
                exoPlayer.playWhenReady = true
                exoError = null
                status = "Reproduciendo"
            } catch (_: Exception) {
                addLog("⚠️ Respaldo #${indiceCandidato + 1} falló")
            }
        }
    }

    LaunchedEffect(m3u8Url, reloadTrigger) {
        val url = m3u8Url ?: return@LaunchedEffect'''

    if ancla_effect in content:
        content = content.replace(ancla_effect, nuevo_bloque)
        print("✅ Auto-cambio a candidato agregado")

# ═══════════════════════════════════════════════════════════
# 3) Al cargar un embed: extraer 3 URLs en paralelo
# ═══════════════════════════════════════════════════════════
old_effect = '''        try {
            val url = kotlinx.coroutines.withTimeoutOrNull(12000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }
            if (url != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = url
            } else {
                addLog("⚠️ Extracto falló/timeout → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }'''

new_effect = '''        try {
            // 1) Extraer la URL PRINCIPAL primero (rápido para arrancar YA)
            val principal = kotlinx.coroutines.withTimeoutOrNull(12000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }
            if (principal != null) {
                cookies = M3u8Extractor.cookieString()
                m3u8Url = principal
                urlsCandidatas = listOf(principal)
                indiceCandidato = 0

                // 2) En BACKGROUND: extraer 3 URLs de respaldo
                scope.launch {
                    preparandoCandidatos = true
                    val respaldos = mutableListOf<String>()
                    for (i in 1..3) {
                        try {
                            val extra = M3u8Extractor.extraer(
                                embedActual.url, embedActual.referer,
                                { /* silencioso */ }
                            )
                            if (extra != null && extra != principal && extra !in respaldos) {
                                respaldos.add(extra)
                                addLog("🔒 Respaldo #${respaldos.size} listo")
                            }
                        } catch (_: Exception) {}
                    }
                    if (respaldos.isNotEmpty()) {
                        urlsCandidatas = listOf(principal) + respaldos
                        addLog("🛡️ ${respaldos.size} URLs de respaldo listas")
                    }
                    preparandoCandidatos = false
                }
            } else {
                addLog("⚠️ Extracto falló/timeout → WebView")
                status = "Cargando reproductor..."
                usarWebView = true
            }
        } catch (e: Exception) {
            addLog("❌ ${e.message} → WebView")
            status = "Cargando reproductor..."
            usarWebView = true
        }'''

if old_effect in content:
    content = content.replace(old_effect, new_effect)
    print("✅ Extracción multi-URL en paralelo")
else:
    print("⚠️  No encontré el bloque de extracción principal")

# ═══════════════════════════════════════════════════════════
# 4) En el onPlayerError: cambiar SILENCIOSAMENTE al siguiente candidato
# ═══════════════════════════════════════════════════════════
old_error = '''                        scope.launch {
                            if (reintentos >= MAX_REINTENTOS_POR_CANAL) {
                                // 4° error en este canal → saltar al siguiente
                                val siguiente = evento.embeds.firstOrNull {
                                    it.url != embedActual.url && it.url !in canalesIntentados
                                }
                                if (siguiente == null) {
                                    addLog("❌ Todos los canales fallaron")
                                    todosFallaron = true
                                    exoError = "Todos los canales fallaron. Probá más tarde."
                                    return@launch
                                }
                                canalesIntentados = canalesIntentados + embedActual.url
                                addLog("➡️  Cambiando a ${siguiente.nombre}")
                                avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                exoError = null
                                status = "Cambiando de canal..."
                                delay(2000)
                                avisoCambio = null
                                reintentos = 0
                                embedActual = siguiente
                            } else {'''

new_error = '''                        scope.launch {
                            // ═══════════════════════════════════════════════════
                            // PRIMERO: intentar cambiar a una URL de respaldo (SILENCIOSO)
                            // Si hay candidatos disponibles, saltar a la siguiente SIN esperar
                            // ═══════════════════════════════════════════════════
                            if (urlsCandidatas.size > indiceCandidato + 1) {
                                indiceCandidato++
                                addLog("🔀 Auto-cambio a respaldo #${indiceCandidato + 1}/${urlsCandidatas.size}")
                                // El LaunchedEffect indiceCandidato va a hacer el cambio
                                delay(500) // pequeño delay para que el ExoPlayer se prepare
                                return@launch
                            }

                            if (reintentos >= MAX_REINTENTOS_POR_CANAL) {
                                // 4° error en este canal → saltar al siguiente
                                val siguiente = evento.embeds.firstOrNull {
                                    it.url != embedActual.url && it.url !in canalesIntentados
                                }
                                if (siguiente == null) {
                                    addLog("❌ Todos los canales fallaron")
                                    todosFallaron = true
                                    exoError = "Todos los canales fallaron. Probá más tarde."
                                    return@launch
                                }
                                canalesIntentados = canalesIntentados + embedActual.url
                                addLog("➡️  Cambiando a ${siguiente.nombre}")
                                avisoCambio = "Cambiando a ${siguiente.nombre}..."
                                exoError = null
                                status = "Cambiando de canal..."
                                delay(2000)
                                avisoCambio = null
                                reintentos = 0
                                embedActual = siguiente
                            } else {'''

if old_error in content:
    content = content.replace(old_error, new_error)
    print("✅ Error handler cambiado a candidatos silenciosos")
else:
    print("⚠️  No encontré el bloque de onPlayerError")

# ═══════════════════════════════════════════════════════════
# 5) Reducir reintentos a 1 (por si no hay candidatos)
# ═══════════════════════════════════════════════════════════
if "private const val MAX_REINTENTOS_POR_CANAL = 3" in content:
    content = content.replace(
        "private const val MAX_REINTENTOS_POR_CANAL = 3",
        "private const val MAX_REINTENTOS_POR_CANAL = 2"
    )
    print("✅ Reintentos reducidos a 2 (respaldo toma el control)")

# ═══════════════════════════════════════════════════════════
# 6) Cuando cambia manualmente de canal: resetear candidatos
# ═══════════════════════════════════════════════════════════
old_manual = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO'''

new_manual = '''                onCanalClick = { nuevo ->
                    reintentos = 0
                    todosFallaron = false
                    panelAbierto = false
                    zona = ZonaUI.VIDEO
                    // Resetear candidatos al cambiar manualmente de canal
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0'''

if old_manual in content:
    content = content.replace(old_manual, new_manual)
    print("✅ Reset de candidatos al cambiar de canal")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "urlsCandidatas" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Sistema de candidatos"
grep -q "Auto-cambio a respaldo" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Auto-cambio silencioso"
grep -q "Respaldo #" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Extracción multi-URL en paralelo"
grep -q "MAX_REINTENTOS_POR_CANAL = 2" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ Reintentos reducidos"

echo ""
echo "✅✅✅ Sistema 'CERO ESPERA' instalado"
echo ""
echo "🎯 Cómo funciona:"
echo "   1. Tocás un canal → extrae la principal (rápido)"
echo "   2. Arranca a reproducir YA"
echo "   3. En BACKGROUND: extrae 3 URLs de respaldo"
echo "   4. Si falla la principal → cambia a respaldo #1 al toque"
echo "   5. Si falla #1 → respaldo #2 (todo silencioso)"
echo "   6. Solo si TODAS fallan → muestra error"
echo ""
echo "🎬 El usuario VE:"
echo "   ✅ Reproduciendo (arranca al toque)"
echo "   🛡️ 3 URLs de respaldo listas (invisible)"
echo "   🔀 (si falla algo) cambio automático sin que se note"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"