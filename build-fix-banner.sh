#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
[ ! -f "$HOME" ] && { echo "❌ No existe $HOME"; exit 1; }
cp "$HOME" "${HOME}.bak.banner.$(date +%s)"
echo "✅ Backup: ${HOME}.bak.banner.$(date +%s)"

echo ""
echo "🔍 ANTES:"
grep -n "BannerPremium" "$HOME" || echo "  (sin referencias)"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# Verificar si la FUNCIÓN existe (no solo la llamada)
if 'private fun BannerPremium' in c:
    print("ℹ️ BannerPremium ya está definida. No hago nada.")
else:
    # Encontrar el último "}" del archivo y meter la función antes
    idx = c.rfind("}")
    if idx < 0:
        print("❌ No encontré el cierre del archivo")
        raise SystemExit(1)

    banner = '''
@Composable
private fun BannerPremium(mensaje: String, esMovil: Boolean) {
    val padH = if (esMovil) 16.dp else 48.dp
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = padH)
            .fadeInOnLoad(500, delayMs = 150)
            .clip(RoundedCornerShape(14.dp))
            .background(
                Brush.horizontalGradient(
                    listOf(
                        AppColors.Gold.copy(alpha = 0.22f),
                        AppColors.Gold.copy(alpha = 0.05f)
                    )
                )
            )
            .border(1.dp, AppColors.Gold.copy(alpha = 0.55f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📢", fontSize = if (esMovil) 18.sp else 20.sp)
        Spacer(Modifier.width(12.dp))
        Text(
            mensaje,
            color = AppColors.GoldBright,
            fontSize = if (esMovil) 12.sp else 13.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = if (esMovil) 16.sp else 18.sp
        )
    }
}
'''
    c = c[:idx] + banner + "\n" + c[idx:]
    with open(fp, 'w', encoding='utf-8') as f:
        f.write(c)
    print("✅ BannerPremium agregada al final del archivo")
PYEOF

echo ""
echo "🔍 DESPUÉS:"
grep -n "BannerPremium\|private fun BannerPremium" "$HOME" || echo "  (sin referencias)"

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
