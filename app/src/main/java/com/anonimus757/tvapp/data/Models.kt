package com.anonimus757.tvapp.data

data class Evento(
    val fuente: String,
    val groupTitle: String,
    val descripcion: String,
    val hora: String,
    val imagen: String,
    val embeds: List<Embed>,
    val fecha: String = "" // YYYY-MM-DD. Si vacío → se descarta en Firebase, pero el scraping lo completa con HOY
)

data class Embed(
    val nombre: String,
    val url: String,
    val referer: String
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
