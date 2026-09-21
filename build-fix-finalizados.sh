#!/bin/bash
set -e

HOME_FILE="app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
BACKUP="${HOME_FILE}.bak.finalizados.$(date +%s)"
[ ! -f "$HOME_FILE" ] && { echo "❌ No existe $HOME_FILE"; exit 1; }
cp "$HOME_FILE" "$BACKUP"
echo "✅ Backup: $BACKUP"

python3 << 'PYEOF'
fp = "app/src/main/java/com/anonimus757/tvapp/ui/HomeScreen.kt"
with open(fp, 'r', encoding='utf-8') as f:
    c = f.read()

# ─── PASO 1: Cambiar diaRelativo para que reciba el Evento completo ───
viejo_diaRelativo = '''private fun diaRelativo(fechaStr: String): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(fechaStr) ?: return "PRÓXIMOS"
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val eventoMillis = cal.timeInMillis
        val diffDias = ((eventoMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()
        when {
            diffDias < 0 -> "FINALIZADOS"
            diffDias == 0 -> "HOY"
            diffDias == 1 -> "MAÑANA"
            diffDias == 2 -> "PASADO MAÑANA"
            diffDias in 3..7 -> "ESTA SEMANA"
            else -> "PRÓXIMOS"
        }
    } catch (e: Exception) { "PRÓXIMOS" }
}'''

nuevo_diaRelativo = '''private fun diaRelativo(ev: Evento): String {
    return try {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.isLenient = false
        val fechaEvento = sdf.parse(ev.fecha) ?: return "PRÓXIMOS"
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val hoyMillis = cal.timeInMillis
        cal.time = fechaEvento
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val eventoMillis = cal.timeInMillis
        val diffDias = ((eventoMillis - hoyMillis) / (1000L * 60L * 60L * 24L)).toInt()

        when {
            // Días anteriores → ignorar (no mostrar)
            diffDias < 0 -> "IGNORAR"

            // HOY: ¿ya terminó el partido? (hora + 150 min de duración)
            diffDias == 0 -> {
                val minActual = Calendar.getInstance().let {
                    it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE)
                }
                val minEvento = horaAMinutos(ev.hora)
                if (minEvento != Int.MAX_VALUE && minActual > minEvento + 150) "FINALIZADOS"
                else "HOY"
            }

            diffDias == 1 -> "MAÑANA"
            diffDias == 2 -> "PASADO MAÑANA"
            diffDias in 3..7 -> "ESTA SEMANA"
            else -> "PRÓXIMOS"
        }
    } catch (e: Exception) { "PRÓXIMOS" }
}'''

if viejo_diaRelativo not in c:
    print("❌ No encontré la función diaRelativo original. Abortando.")
    raise SystemExit(1)
c = c.replace(viejo_diaRelativo, nuevo_diaRelativo, 1)
print("✅ Paso 1: diaRelativo ahora recibe Evento y devuelve IGNORAR para días pasados")

# ─── PASO 2: Filtrar los IGNORAR en agruparEventos ───
viejo_agrup = '''    eventos.forEach { ev ->
        if (estaEnVivo(ev)) enVivo.add(ev)
        else porDia.getOrPut(diaRelativo(ev.fecha)) { mutableListOf() }.add(ev)
    }'''

nuevo_agrup = '''    eventos.forEach { ev ->
        if (estaEnVivo(ev)) {
            enVivo.add(ev)
        } else {
            val dia = diaRelativo(ev)
            if (dia != "IGNORAR") {
                porDia.getOrPut(dia) { mutableListOf() }.add(ev)
            }
        }
    }'''

if viejo_agrup not in c:
    print("❌ No encontré el forEach de agruparEventos. Abortando.")
    raise SystemExit(1)
c = c.replace(viejo_agrup, nuevo_agrup, 1)
print("✅ Paso 2: eventos IGNORAR filtrados correctamente")

with open(fp, 'w', encoding='utf-8') as f:
    f.write(c)

# Verificación
with open(fp, 'r', encoding='utf-8') as f:
    final = f.read()

if 'IGNORAR' in final and 'diaRelativo(ev)' in final:
    print("✅ Verificación: cambios aplicados correctamente")
else:
    print("⚠️ Advertencia: algo no se aplicó bien")
PYEOF

echo ""
echo "✅✅✅ Fix finalizados completo"
echo ""
echo "Compilá:"
echo "  ./gradlew clean"
echo "  ./gradlew assembleDebug --no-daemon --max-workers=1"
