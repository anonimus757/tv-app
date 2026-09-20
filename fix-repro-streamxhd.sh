#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
cp "$FILE" "$FILE.bak-repro-fix"

echo "📝 Aplicando fix para .ts y streamxhd.com..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 1) Asegurar que streamxhd.com esté en esPaginaDinamica
old_esPag = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com") ||
           low.contains("streamxhd.st") ||
           low.contains("stream-xhd") ||
           low.contains("streamx-hd")
}'''
new_esPag = '''private fun esPaginaDinamica(url: String): Boolean {
    val low = url.lowercase()
    // Sitios con reproductores dinámicos (JS, Blob URLs, MSE)
    return low.contains("streamxhd.com") ||
           low.contains("streamhdx.com") ||
           low.contains("streamxhd.st") ||
           low.contains("stream-xhd") ||
           low.contains("streamx-hd") ||
           low.contains("liontv.es") // LionTV también puede ser dinámico
}'''
if old_esPag in content:
    content = content.replace(old_esPag, new_esPag)
    print("✅ esPaginaDinamica actualizada con liontv.es")

# 2) Detectar .ts y forzar MIME type
old_media = '''            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

            val src = if (esTS) {
                androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(ds)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            } else {
                HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(url)))
            }'''
new_media = '''            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

            val mediaItem = MediaItem.Builder()
                .setUri(Uri.parse(url))
                .apply {
                    if (esTS) {
                        // Forzar el tipo MIME para MPEG-TS directo
                        setMimeType(androidx.media3.common.MimeTypes.APPLICATION_MPEGTS)
                    }
                }
                .build()

            val src = if (esTS) {
                // Usar ProgressiveMediaSource con TsExtractor explícito
                val extractorFactory = androidx.media3.extractor.DefaultExtractorsFactory()
                androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(ds, extractorFactory)
                    .createMediaSource(mediaItem)
            } else {
                HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(mediaItem)
            }'''
if old_media in content:
    content = content.replace(old_media, new_media)
    print("✅ .ts ahora usa MIME type explícito + TsExtractor")

# 3) Timeout del WebView: si en 10 seg no captura, hacerlo VISIBLE
old_wv_timeout = '''    LaunchedEffect(usarWebView) {
        if (usarWebView) {
            webViewStartTime = System.currentTimeMillis()
            delay(8000)

            val sinCapturar = m3u8Url == null
            val siguenPasandoLosSegundos = System.currentTimeMillis() - webViewStartTime >= 8000

            if (sinCapturar && siguenPasandoLosSegundos && !refrescando) {
                addLog("⏰ WebView no capturó en 8s → siguiente canal")

                // Buscar siguiente canal del evento
                val siguiente = evento.embeds.firstOrNull {
                    it.url != embedActual.url && it.url !in canalesIntentados
                }
                if (siguiente != null) {
                    addLog("📡 Sin señal, buscando otra...")
                    mostrandoSinSenal = true
                    delay(2000)
                    mostrandoSinSenal = false
                    canalesIntentados = canalesIntentados + embedActual.url
                    usarWebView = false
                    reintentos = 0
                    urlsCandidatas = emptyList()
                    indiceCandidato = 0
                    embedActual = siguiente
                } else {
                    addLog("❌ Evento sin señal")
                    eventoMuerto = true
                    todosFallaron = true
                    usarWebView = false
                }
            }
        }
    }'''
new_wv_timeout = '''    LaunchedEffect(usarWebView) {
        if (usarWebView) {
            webViewStartTime = System.currentTimeMillis()
            delay(10000) // 10 segundos

            if (m3u8Url == null && !refrescando) {
                addLog("⏰ WebView no capturó en 10s → haciendo VISIBLE")

                // 🆕 Hacer visible el WebView para que el usuario vea el reproductor web
                webViewVisible = true

                // Esperar un tiempo más para ver si captura (a veces tarda)
                delay(15000) // 15 seg más

                if (m3u8Url == null && !refrescando) {
                    addLog("❌ WebView sigue sin capturar → siguiente canal")
                    // Si sigue sin capturar, buscar siguiente canal
                    val siguiente = evento.embeds.firstOrNull {
                        it.url != embedActual.url && it.url !in canalesIntentados
                    }
                    if (siguiente != null) {
                        addLog("📡 Sin señal, buscando otra...")
                        mostrandoSinSenal = true
                        delay(2000)
                        mostrandoSinSenal = false
                        canalesIntentados = canalesIntentados + embedActual.url
                        usarWebView = false
                        webViewVisible = false
                        reintentos = 0
                        urlsCandidatas = emptyList()
                        indiceCandidato = 0
                        embedActual = siguiente
                    } else {
                        addLog("❌ Evento sin señal")
                        eventoMuerto = true
                        todosFallaron = true
                        usarWebView = false
                        webViewVisible = false
                    }
                }
            }
        }
    }'''
if old_wv_timeout in content:
    content = content.replace(old_wv_timeout, new_wv_timeout)
    print("✅ Timeout del WebView: 10s para hacer visible")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "liontv.es" "$FILE" && echo "  ✓ liontv.es en páginas dinámicas"
grep -q "APPLICATION_MPEGTS" "$FILE" && echo "  ✓ MIME type para .ts"
grep -q "webViewVisible = true" "$FILE" && echo "  ✓ WebView se hace visible si no captura"

echo ""
echo "✅✅✅ Fix de reproducción aplicado"
echo ""
echo "📌 Qué hace:"
echo "   1. .ts → fuerza MIME type MPEG-TS y usa TsExtractor"
echo "   2. streamxhd → si el WebView no captura en 10s, se hace VISIBLE"
echo "   3. liontv.es → también va al WebView"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"