#!/bin/bash
set -e

if [ ! -f "./gradlew" ]; then
    echo "❌ No estás en la raíz del proyecto"
    exit 1
fi

NOTIF_DIR="app/src/main/java/com/anonimus757/tvapp/notifications"

cp "$NOTIF_DIR/EventNotifScheduler.kt" "$NOTIF_DIR/EventNotifScheduler.kt.bak-fecha"

echo "📝 Reescribiendo EventNotifScheduler con lógica de fecha correcta..."

cat > "$NOTIF_DIR/EventNotifScheduler.kt" << 'EOF'
package com.anonimus757.tvapp.notifications

import android.content.Context
import android.util.Log
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.anonimus757.tvapp.data.Evento
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Agenda notificaciones de eventos RESPETANDO la fecha real del evento.
 *
 * Por cada evento se agendan (si su fecha+hora es futura):
 *   1) Notif "⏰ En 10 min: <evento>"  → 10 min antes
 *   2) Notif "🔴 EN VIVO: <evento>"    → a la hora exacta
 *
 * IMPORTANTE: usa el campo `fecha` (YYYY-MM-DD) del evento, NO asume "hoy".
 * Si la fecha+hora ya pasó, no se agenda nada.
 */
object EventNotifScheduler {

    private const val TAG = "EventNotifScheduler"
    private const val TAG_EVENTOS = "futtv_evento"

    /**
     * Convierte "20:30", "Hoy 20:30", "20:30 hs" → (hora, minuto)
     * Devuelve null si no puede parsear.
     */
    private fun parsearHora(hora: String): Pair<Int, Int>? {
        val m = Regex("""(\d{1,2}):(\d{2})""").find(hora) ?: return null
        val h = m.groupValues[1].toIntOrNull() ?: return null
        val min = m.groupValues[2].toIntOrNull() ?: return null
        if (h !in 0..23 || min !in 0..59) return null
        return h to min
    }

    /**
     * Convierte "2026-09-17" → (año, mes, día). Mes 1-12.
     * Devuelve null si no puede parsear.
     */
    private fun parsearFecha(fecha: String): Triple<Int, Int, Int>? {
        if (fecha.isBlank()) return null
        val m = Regex("""^(\d{4})-(\d{1,2})-(\d{1,2})$""").find(fecha.trim()) ?: return null
        val y = m.groupValues[1].toIntOrNull() ?: return null
        val mes = m.groupValues[2].toIntOrNull() ?: return null
        val d = m.groupValues[3].toIntOrNull() ?: return null
        if (mes !in 1..12 || d !in 1..31) return null
        return Triple(y, mes, d)
    }

    /**
     * Combina fecha (YYYY-MM-DD) + hora (HH:MM) → timestamp en millis.
     * Si la fecha está vacía, asume HOY (compatibilidad con eventos viejos).
     * Devuelve null si la hora no se puede parsear.
     */
    private fun timestampEvento(fecha: String, hora: String): Long? {
        val (h, min) = parsearHora(hora) ?: return null

        val cal = Calendar.getInstance()

        // Si tiene fecha válida → usarla. Si no → hoy (fallback).
        val fechaParsed = parsearFecha(fecha)
        if (fechaParsed != null) {
            cal.set(Calendar.YEAR, fechaParsed.first)
            cal.set(Calendar.MONTH, fechaParsed.second - 1) // Calendar usa 0-11
            cal.set(Calendar.DAY_OF_MONTH, fechaParsed.third)
        }
        // Si fechaParsed == null → dejamos la fecha de hoy (Calendar.getInstance ya la tiene)

        cal.set(Calendar.HOUR_OF_DAY, h)
        cal.set(Calendar.MINUTE, min)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        return cal.timeInMillis
    }

    /**
     * Cancela todo lo agendado y re-agenda según la lista de eventos.
     * Llamar cada vez que se cargan eventos en el Home.
     */
    fun reagendar(context: Context, eventos: List<Evento>) {
        val wm = WorkManager.getInstance(context)
        wm.cancelAllWorkByTag(TAG_EVENTOS)

        val ahora = System.currentTimeMillis()
        var agendados = 0
        var omitidos = 0

        eventos.forEach { ev ->
            val tsEvento = timestampEvento(ev.fecha, ev.hora)
            if (tsEvento == null) {
                Log.d(TAG, "⚠️ No se pudo parsear: ${ev.descripcion} (${ev.fecha} ${ev.hora})")
                omitidos++
                return@forEach
            }

            // Si el evento ya pasó (incluso con 10 min de margen) → no agendar
            // Damos 1 minuto de tolerancia por si estamos justo en el momento
            if (tsEvento < ahora - 60_000L) {
                Log.d(TAG, "⏭️ Evento pasado, se omite: ${ev.descripcion} (${ev.fecha} ${ev.hora})")
                omitidos++
                return@forEach
            }

            val ts10Antes = tsEvento - 10L * 60L * 1000L
            val idBase = ((ev.descripcion + "|" + ev.fuente + "|" + ev.fecha).hashCode()) and 0x7FFFFFFF

            // Notif "10 min antes" → solo si faltan más de 10 min
            if (ts10Antes > ahora) {
                agendar(
                    context = context,
                    cuando = ts10Antes,
                    titulo = "⏰ En 10 min: ${ev.descripcion}",
                    mensaje = "${ev.hora} · ${ev.fuente} · ${ev.groupTitle}",
                    id = idBase,
                    uniqueName = "futtv_antes_$idBase"
                )
                agendados++
            }

            // Notif "en vivo" → a la hora exacta
            if (tsEvento > ahora) {
                agendar(
                    context = context,
                    cuando = tsEvento,
                    titulo = "🔴 EN VIVO: ${ev.descripcion}",
                    mensaje = "${ev.hora} · ${ev.fuente} · ${ev.groupTitle}",
                    id = idBase xor 0x1000,
                    uniqueName = "futtv_inicio_$idBase"
                )
                agendados++
            }
        }

        Log.d(TAG, "✅ Re-agendados: $agendados notifs (omitidos: $omitidos)")
    }

    private fun agendar(
        context: Context,
        cuando: Long,
        titulo: String,
        mensaje: String,
        id: Int,
        uniqueName: String
    ) {
        val delayMs = cuando - System.currentTimeMillis()
        if (delayMs <= 0) return

        val data = Data.Builder()
            .putInt(EventNotifWorker.KEY_ID, id)
            .putString(EventNotifWorker.KEY_TITULO, titulo)
            .putString(EventNotifWorker.KEY_MENSAJE, mensaje)
            .putString(EventNotifWorker.KEY_CANAL, NotificationHelper.CANAL_EVENTOS)
            .build()

        val req = OneTimeWorkRequestBuilder<EventNotifWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(TAG_EVENTOS)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueName,
            ExistingWorkPolicy.REPLACE,
            req
        )
    }
}
EOF

echo ""
echo "🔎 Verificando:"
grep -q "parsearFecha" "$NOTIF_DIR/EventNotifScheduler.kt" && echo "  ✓ Parsea fecha"
grep -q "timestampEvento" "$NOTIF_DIR/EventNotifScheduler.kt" && echo "  ✓ Combina fecha + hora"
grep -q "Evento pasado, se omite" "$NOTIF_DIR/EventNotifScheduler.kt" && echo "  ✓ Omite eventos ya pasados"

echo ""
echo "✅✅✅ Fix aplicado — Notifs respetan fecha real"
echo ""
echo "🎯 Qué cambió:"
echo "   • ANTES: agendaba TODO como si fuera hoy"
echo "   • AHORA: usa fecha + hora del evento"
echo "   • Si el evento ya pasó → no agenda nada"
echo "   • Si el evento es para mañana → agenda para mañana"
echo ""
echo "🚀 Compilá:"
echo "   ./gradlew assembleDebug --no-daemon --max-workers=1"