package com.anonimus757.tvapp.data

data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "", // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY

    // ═══ Campos para API-Sports (opcionales) ═══
    val equipoLocal: String = "",
    val equipoVisitante: String = "",
    val liga: String = "",
    val fixtureId: Int? = null,

    // ═══ Duración y videos en bucle ═══
    val duracionMinutos: Int = 150,        // Cuánto dura el evento (default 2.5h)
    val videoFinalizado: String = "",      // URL MP4 en bucle al finalizar
    val videoProximo: String = ""          // URL MP4 en bucle antes de empezar
)

data class Embed(
    val nombre: String,
    val url: String,
    val referer: String,
    val logo: String = ""  // URL del logo del canal (opcional)
)

data class Fuente(
    val id: String,
    val nombre: String,
    val groupTitle: String,
    val base: String,
    val agenda: String,
    val imgBase: String,
    val imgDefault: String,
    val flagsBase: String?,
    val tipo: String
)

data class Canal(
    val id: String,
    val nombre: String,
    val url: String,
    val logo: String,
    val grupo: String,
    val tvgId: String
)

data class GrupoCanales(
    val nombre: String,
    val canales: List<Canal>
)
