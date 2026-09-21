package com.anonimus757.tvapp.ui

import com.anonimus757.tvapp.data.Embed
import com.anonimus757.tvapp.data.Evento

sealed interface Screen {
    data object Home : Screen
    data class Detail(val evento: Evento, val todos: List<Evento>, val volverA: VolverA) : Screen
    data class Player(val evento: Evento, val embed: Embed, val todos: List<Evento>) : Screen
    data object Ajustes : Screen
    data object Busqueda : Screen
}

enum class VolverA { Home, Player }

