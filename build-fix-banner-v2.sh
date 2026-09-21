#!/bin/bash
set -e

HOME="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
[ ! -f "$HOME" ] && { echo "❌ No existe $HOME"; exit 1; }
cp "$HOME" "${HOME}.bak.bannerv2.$(date +%s)"
echo "✅ Backup: ${HOME}.bak.bannerv2.$(date +%s)"

python3 << 'PYEOF'
import re

fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── PASO 1: Eliminar cualquier BannerPremium mal ubicada ───
patron_banner = re.compile(
    r'\n@Composable\s+private\s+fun\s+BannerPremium\s*\([^)]*\)\s*\{.*?\n\}',
    re.DOTALL
)
c_limpio = patron_banner.sub('', c)
if c_limpio != c:
    print("✅ BannerPremium mal ubicada eliminada")
    c = c_limpio
else:
    print("ℹ️ No había BannerPremium para eliminar (o no matcheó)")

# ─── PASO 2: Encontrar el final REAL del archivo (última línea con solo "}" en columna 0) ───
lineas = c.split('\n')
idx_ultimo_cierre = -1
for i in range(len(lineas) - 1, -1, -1):
    if lineas[i].strip() == '}':
        idx_ultimo_cierre = i
        break

if idx_ultimo_cierre < 0:
    print("❌ No encontré un cierre top-level válido")
    raise SystemExit(1)

print(f"✅ Último cierre top-level en línea {idx_ultimo_cierre + 1}")

# ─── PASO 3: Insertar BannerPremium DESPUÉS del último cierre ───
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

# Insertar la línea del cierre + banner + resto
nuevas_lineas = lineas[:idx_ultimo_cierre + 1] + banner.split('\n') + lineas[idx_ultimo_cierre + 1:]
c = '\n'.join(nuevas_lineas)

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)
print("✅ BannerPremium insertada DESPUÉS del último cierre top-level")

# ─── PASO 4: Verificación ───
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

if 'private fun BannerPremium' in final and final.count('private fun BannerPremium') == 1:
    print("✅ Verificación: BannerPremium definida 1 vez")
else:
    print(f"⚠️ Aviso: BannerPremium aparece {final.count('private fun BannerPremium')} veces")

# Mostrar últimas 40 líneas
print("")
print("=== Últimas 40 líneas ===")
for i, line in enumerate(final.split('\n')[-40:], 1):
    print(f"  {line}")
PYEOF

echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
