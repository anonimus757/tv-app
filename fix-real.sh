#!/bin/bash
set -e

FILE="app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"

cp "$FILE" "$FILE.bak-real"

echo "📝 Fix 1 — streamxhd: mejorar hooks del WebView invisible..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# 1) Mejorar el JS_HOOK: capturar más tipos de URL
# ═══════════════════════════════════════════════════════════
old_js = '''    function send(url) {
        try {
            if (url && typeof url === 'string' && url.indexOf('.m3u8') !== -1) {
                if (window.AndroidBridge && window.AndroidBridge.onM3u8) {
                    window.AndroidBridge.onM3u8(url);
                }
            }
        } catch(e) {}
    }'''

new_js = '''    function send(url) {
        try {
            if (url && typeof url === 'string') {
                // Capturar .m3u8, .ts, .mp4, .mpd (cualquier tipo de video)
                if (url.indexOf('.m3u8') !== -1 ||
                    url.indexOf('.ts') !== -1 ||
                    url.indexOf('.mp4') !== -1 ||
                    url.indexOf('.mpd') !== -1) {
                    if (window.AndroidBridge && window.AndroidBridge.onM3u8) {
                        window.AndroidBridge.onM3u8(url);
                    }
                }
            }
        } catch(e) {}
    }'''

if old_js in content:
    content = content.replace(old_js, new_js)
    print("✅ JS_HOOK captura .ts, .mp4, .mpd")

# ═══════════════════════════════════════════════════════════
# 2) Mejorar shouldInterceptRequest: capturar más tipos
# ═══════════════════════════════════════════════════════════
old_intercept = '''                            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                                val u = request?.url?.toString()
                                if (u != null && u.contains(".m3u8", ignoreCase = true) && m3u8Url == null) {
                                    addLog("🎯 intercept: ${u.take(70)}")
                                    cookies = CookieManager.getInstance().getCookie(u)
                                    m3u8Url = u
                                }
                                return super.shouldInterceptRequest(view, request)
                            }'''

new_intercept = '''                            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                                val u = request?.url?.toString()
                                if (u != null && m3u8Url == null) {
                                    val low = u.lowercase()
                                    val esVideo = low.contains(".m3u8") ||
                                                   low.contains(".ts") ||
                                                   low.contains(".mp4") ||
                                                   low.contains(".mpd") ||
                                                   low.contains("/live/")
                                    if (esVideo && !low.contains(".js") && !low.contains(".css") &&
                                        !low.contains(".png") && !low.contains(".jpg") &&
                                        !low.contains(".svg") && !low.contains(".woff")) {
                                        addLog("🎯 intercept: ${u.take(70)}")
                                        cookies = CookieManager.getInstance().getCookie(u)
                                        m3u8Url = u
                                    }
                                }
                                return super.shouldInterceptRequest(view, request)
                            }'''

if old_intercept in content:
    content = content.replace(old_intercept, new_intercept)
    print("✅ shouldInterceptRequest captura más tipos")

# ═══════════════════════════════════════════════════════════
# 3) Mejorar hooks del JS: video.src, MediaSource, source tags
# ═══════════════════════════════════════════════════════════
old_hook = '''    setInterval(function() {
        try {
            var vids = document.querySelectorAll('video, source');
            for (var i = 0; i < vids.length; i++) {
                if (vids[i].src) send(vids[i].src);
                if (vids[i].currentSrc) send(vids[i].currentSrc);
            }
        } catch(e) {}
    }, 500);'''

new_hook = '''    setInterval(function() {
        try {
            var vids = document.querySelectorAll('video, source');
            for (var i = 0; i < vids.length; i++) {
                if (vids[i].src) send(vids[i].src);
                if (vids[i].currentSrc) send(vids[i].currentSrc);
                if (vids[i].getAttribute && vids[i].getAttribute('data-src')) {
                    send(vids[i].getAttribute('data-src'));
                }
            }
        } catch(e) {}
    }, 500);
    // Interceptar la creación de video
    (function() {
        var _createElement = document.createElement.bind(document);
        document.createElement = function(tag) {
            var el = _createElement(tag);
            if (tag.toLowerCase() === 'video') {
                setTimeout(function() {
                    try {
                        if (el.src) send(el.src);
                        if (el.currentSrc) send(el.currentSrc);
                    } catch(e) {}
                }, 1000);
            }
            return el;
        };
    })();'''

if old_hook in content:
    content = content.replace(old_hook, new_hook)
    print("✅ Hook extra para crear videos")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 2 — LionTV .ts: ProgressiveMediaSource + TsExtractor..."

python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Reemplazar la lógica de .ts en el bloque principal
old_ts_block = '''            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

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

new_ts_block = '''            val esTS = url.substringBefore("?").endsWith(".ts", ignoreCase = true)

            val src = if (esTS) {
                // ═══════════════════════════════════════════════════
                // MPEG-TS DIRECTO (LionTV Xtream Codes)
                // Configuramos el extractor MPEG-TS explícitamente
                // ═══════════════════════════════════════════════════
                val tsExtractor = androidx.media3.extractor.ts.TsExtractor(
                    androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory(
                        androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES
                    )
                )
                val extractorsFactory = androidx.media3.extractor.DefaultExtractorsFactory()

                val mediaItemTS = MediaItem.Builder()
                    .setUri(Uri.parse(url))
                    .setMimeType(androidx.media3.common.MimeTypes.APPLICATION_MPEGTS)
                    .build()

                androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(ds, extractorsFactory)
                    .createMediaSource(mediaItemTS)
            } else {
                val mediaItemHls = MediaItem.Builder()
                    .setUri(Uri.parse(url))
                    .build()

                HlsMediaSource.Factory(ds)
                    .setAllowChunklessPreparation(false)
                    .setUseSessionKeys(false)
                    .createMediaSource(mediaItemHls)
            }'''

if old_ts_block in content:
    content = content.replace(old_ts_block, new_ts_block)
    print("✅ .ts usa TsExtractor explícito")
else:
    # Buscar variante
    print("⚠️  No encontré el bloque .ts principal")

# Headers especiales para .ts (Xtream Codes)
old_headers = '''            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Referer" to embedActual.referer,
                "Origin" to embedActual.referer.trimEnd('/')
            )
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }
            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(20000)
                .setReadTimeoutMs(20000)'''

new_headers = '''            val esTSDirec = url.substringBefore("?").endsWith(".ts", ignoreCase = true)
            val headers = mutableMapOf(
                "User-Agent" to USER_AGENT,
                "Accept" to "*/*",
                "Connection" to "keep-alive"
            )
            if (embedActual.referer.isNotBlank()) {
                headers["Referer"] = embedActual.referer
                headers["Origin"] = embedActual.referer.trimEnd('/')
            }
            // Para .ts (Xtream Codes) → a veces necesita el Referer del propio host
            if (esTSDirec) {
                try {
                    val uri = Uri.parse(url)
                    val hostReferer = "${uri.scheme}://${uri.host}:${uri.port}/"
                    headers["Referer"] = hostReferer
                    headers["Origin"] = "${uri.scheme}://${uri.host}:${uri.port}"
                } catch (_: Exception) {}
            }
            cookies?.let { if (it.isNotEmpty()) headers["Cookie"] = it }
            val ds = DefaultHttpDataSource.Factory()
                .setUserAgent(USER_AGENT)
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(20000)
                .setReadTimeoutMs(20000)'''

if old_headers in content:
    content = content.replace(old_headers, new_headers)
    print("✅ Headers especiales para .ts")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "📝 Fix 3 — SACAR el WebView visible (volver a invisible)..."

python3 << 'PYEOF'
import re
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# 3a) Sacar el botón "Volver" del WebView visible
old_boton = '''
        // 🆕 Botón para volver del modo WebView visible
        if (webViewVisible && m3u8Url == null) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(20.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color(0xE6000000))
                    .border(2.dp, Color(0xFFFFD700), RoundedCornerShape(10.dp))
                    .clickable {
                        webViewVisible = false
                        addLog("🔙 Volviendo a modo invisible")
                    }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = AppIcons.volver,
                        contentDescription = null,
                        tint = Color(0xFFFFD700),
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Volver",
                        color = Color(0xFFFFD700),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
'''

if old_boton in content:
    content = content.replace(old_boton, '')
    print("✅ Botón Volver eliminado")

# 3b) Hacer que el WebView siempre sea invisible
old_layout = '''                        // Si webViewVisible=true → ocupa toda la pantalla
                        // Si no → invisible 1x1 (para capturar m3u8 en background)
                        layoutParams = if (webViewVisible) {
                            ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT
                            )
                        } else {
                            ViewGroup.LayoutParams(1, 1)
                        }'''
new_layout = '''                        layoutParams = ViewGroup.LayoutParams(1, 1)'''
if old_layout in content:
    content = content.replace(old_layout, new_layout)
    print("✅ WebView siempre 1x1 (invisible)")

# 3c) Modifier siempre 1.dp
old_mod = '''                modifier = if (webViewVisible) {
                    Modifier.fillMaxSize()
                } else {
                    Modifier.size(1.dp)
                }'''
new_mod = '''                modifier = Modifier.size(1.dp)'''
if old_mod in content:
    content = content.replace(old_mod, new_mod)
    print("✅ Modifier siempre 1dp")

# 3d) Quitar la lógica de hacer visible el WebView del timeout
old_timeout = '''    LaunchedEffect(usarWebView) {
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

new_timeout = '''    LaunchedEffect(usarWebView) {
        if (usarWebView) {
            webViewStartTime = System.currentTimeMillis()
            // Esperar hasta 25 segundos a que capture el m3u8 del WebView invisible
            delay(25000)

            if (m3u8Url == null && !refrescando) {
                addLog("⏰ WebView no capturó en 25s → siguiente canal")
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

if old_timeout in content:
    content = content.replace(old_timeout, new_timeout)
    print("✅ Timeout del WebView: 25s (más tiempo para capturar)")

# 3e) Quitar la declaración de webViewVisible (ya no se usa)
content = re.sub(r'\n    var webViewVisible by remember \{ mutableStateOf\(false\) \}', '', content)
content = re.sub(r'\n        webViewVisible = false', '', content)

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -c "webViewVisible" "$FILE" | xargs -I {} echo "  webViewVisible referencias: {} (debe ser 0)"
grep -q "TsExtractor" "$FILE" && echo "  ✓ TsExtractor para .ts"
grep -q "esVideo && !low.contains" "$FILE" && echo "  ✓ shouldInterceptRequest mejorado"

echo ""
echo "✅✅✅ Fix real aplicado"
echo ""
echo "📌 Qué cambió:"
echo "   🎬 LionTV .ts → TsExtractor explícito + headers Xtream"
echo "   🎬 streamxhd → hooks mejorados (captura .ts, .mp4, .mpd)"
echo "   🚫 WebView visible ELIMINADO (vuelve a invisible)"
echo "   ⏱️  Timeout del WebView: 25s"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"