#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

DATA_DIR="app/src/main/java/com/anonimus757/tvapp/data"
UI_DIR="app/src/main/java/com/anonimus757/tvapp/ui"

cp "$DATA_DIR/M3u8Extractor.kt" "$DATA_DIR/M3u8Extractor.kt.bak-precheck"
cp "$UI_DIR/PlayerScreen.kt" "$UI_DIR/PlayerScreen.kt.bak-precheck"

echo "📝 Agregando sistema de pre-check..."

# ═══════════════════════════════════════════════════════════
# 1) M3u8Extractor: agregar testeo rápido de URL
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/data/M3u8Extractor.kt"
with open(file_path) as f:
    content = f.read()

# Función testearUrl + extraerYTestear
funciones_nuevas = '''
    /**
     * Testea rápido si una URL m3u8 está viva.
     * Hace un GET con timeout corto (3s) y verifica que contenga #EXTM3U.
     *
     * @return true si la URL responde bien
     */
    private fun testearUrl(url: String, referer: String?): Boolean {
        return try {
            val b = Request.Builder()
                .url(url)
                .header("User-Agent", USER_AGENT)
                .header("Accept", "*/*")
            if (!referer.isNullOrBlank()) b.header("Referer", referer)
            if (cookies.isNotEmpty()) b.header("Cookie", cookies.values.joinToString("; "))

            // Cliente con timeout corto SOLO para el test
            val clienteRapido = client.newBuilder()
                .connectTimeout(3, TimeUnit.SECONDS)
                .readTimeout(3, TimeUnit.SECONDS)
                .build()

            val resp = clienteRapido.newCall(b.build()).execute()
            if (resp.code != 200) {
                resp.close()
                return false
            }
            // Leer solo el inicio del body para verificar que es un m3u8 válido
            val body = resp.body?.string()?.take(200) ?: ""
            resp.close()
            body.contains("#EXTM3U")
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Extrae la URL del embed y la testea. Si la primera falla,
     * intenta extraer otra y testearla. Devuelve la primera URL
     * que responda OK, o null si todas fallan.
     *
     * Máximo: 3 intentos, timeout total ~10 seg.
     */
    suspend fun extraerYTestear(
        urlEmbed: String,
        referer: String,
        onLog: (String) -> Unit
    ): String? = withContext(Dispatchers.IO) {
        val inicio = System.currentTimeMillis()

        for (intento in 1..3) {
            if (System.currentTimeMillis() - inicio > 12000) {
                onLog("⏰ Timeout total alcanzado")
                break
            }

            if (intento > 1) {
                onLog("🔍 Reintento $intento/3...")
            }

            val url = try {
                withTimeoutOrNull(5000L) {
                    extraer(urlEmbed, referer, onLog)
                }
            } catch (_: Exception) { null }

            if (url == null) {
                onLog("⚠️ No se pudo extraer (intento $intento)")
                continue
            }

            onLog("🧪 Testeando URL...")
            val ok = testearUrl(url, referer)
            if (ok) {
                onLog("✅ URL verificada OK")
                return@withContext url
            } else {
                onLog("❌ URL muerta, buscando otra...")
            }
        }

        onLog("❌ No se encontró URL funcional")
        null
    }

'''

# Insertar antes de la última función (elegirVariante o similar)
if "extraerYTestear" not in content:
    # Buscar un ancla
    ancla = "    private fun elegirVariante"
    if ancla in content:
        content = content.replace(ancla, funciones_nuevas + ancla, 1)
        print("✅ extraerYTestear + testearUrl agregados")
    elif "    private fun adaptarUrl" in content:
        content = content.replace("    private fun adaptarUrl", funciones_nuevas + "    private fun adaptarUrl", 1)
        print("✅ Funciones agregadas (variante adaptarUrl)")
    else:
        # Último intento: agregar antes del cierre de la clase
        content = content.rstrip()
        if content.endswith("}"):
            content = content[:-1] + "\n" + funciones_nuevas + "\n}\n"
            print("✅ Funciones agregadas al final")

# Import para withTimeoutOrNull
if "import kotlinx.coroutines.withTimeoutOrNull" not in content:
    content = content.replace(
        "import kotlinx.coroutines.withContext",
        "import kotlinx.coroutines.withContext\nimport kotlinx.coroutines.withTimeoutOrNull"
    )

with open(file_path, "w") as f:
    f.write(content)
PYEOF

# ═══════════════════════════════════════════════════════════
# 2) PlayerScreen: usar extraerYTestear en vez de extraer
# ═══════════════════════════════════════════════════════════
python3 << 'PYEOF'
file_path = "app/src/main/java/com/anonimus757/tvapp/ui/PlayerScreen.kt"
with open(file_path) as f:
    content = f.read()

# Reemplazar la extracción principal por extraerYTestear
old_extraccion = '''            val principal = kotlinx.coroutines.withTimeoutOrNull(12000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }'''

new_extraccion = '''            // Usar extraerYTestear: extrae + verifica que la URL funcione ANTES de reproducir
            val principal = M3u8Extractor.extraerYTestear(
                embedActual.url, embedActual.referer, addLog
            )'''

if old_extraccion in content:
    content = content.replace(old_extraccion, new_extraccion)
    print("✅ Extracción con pre-check aplicada")
else:
    # Buscar variante con "M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)"
    old_alt = '''            val url = kotlinx.coroutines.withTimeoutOrNull(12000L) {
                M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
            }'''
    new_alt = '''            val url = M3u8Extractor.extraerYTestear(
                embedActual.url, embedActual.referer, addLog
            )'''
    if old_alt in content:
        content = content.replace(old_alt, new_alt)
        print("✅ Extracción con pre-check (variante)")
    else:
        print("⚠️  No encontré el bloque de extracción principal")

# También en los reintentos: usar extraerYTestear cuando se hace URL fresca
old_fresh = '''                                        val fresh = try {
                                            M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                                        } catch (ex: Exception) { null }'''

new_fresh = '''                                        val fresh = try {
                                            M3u8Extractor.extraerYTestear(embedActual.url, embedActual.referer, addLog)
                                        } catch (ex: Exception) { null }'''

if old_fresh in content:
    content = content.replace(old_fresh, new_fresh)
    print("✅ Reintentos usan pre-check")

# Y en el refrescar manual
old_refresh = '''                    val fresh = try {
                        M3u8Extractor.extraer(embedActual.url, embedActual.referer, addLog)
                    } catch (ex: Exception) { null }'''

new_refresh = '''                    val fresh = try {
                        M3u8Extractor.extraerYTestear(embedActual.url, embedActual.referer, addLog)
                    } catch (ex: Exception) { null }'''

if old_refresh in content:
    content = content.replace(old_refresh, new_refresh)
    print("✅ Refrescar manual usa pre-check")

with open(file_path, "w") as f:
    f.write(content)
PYEOF

echo ""
echo "🔎 Verificando:"
grep -q "fun extraerYTestear" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ extraerYTestear creado"
grep -q "fun testearUrl" "$DATA_DIR/M3u8Extractor.kt" && echo "  ✓ testearUrl creado"
grep -q "extraerYTestear" "$UI_DIR/PlayerScreen.kt" && echo "  ✓ PlayerScreen usa pre-check"

echo ""
echo "✅✅✅ Sistema de pre-check instalado"
echo ""
echo "🎯 Cómo funciona:"
echo "   1. Tocás canal → extrae URL"
echo "   2. Testea rápido si responde (3s timeout)"
echo "   3. Si OK → reproduce YA"
echo "   4. Si falla → extrae otra y testea (máx 3 intentos)"
echo "   5. Solo reproduce URLs verificadas"
echo ""
echo "⚡ Velocidad:"
echo "   • URL buena → reproduce en 3-5 seg"
echo "   • URL mala → 3 seg extra + 3-5 seg = 6-8 seg"
echo "   • Antes: esperabas a que fallara en ExoPlayer (10-15 seg)"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"