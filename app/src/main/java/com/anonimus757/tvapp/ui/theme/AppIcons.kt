package com.anonimus757.tvapp.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Iconos centralizados de FutTV.
 * Todos son Material Icons (vectoriales, escalables, look profesional).
 * Reemplazan a los emojis que se veían amateur.
 *
 * Convención:
 *   - "Default." → icono relleno (para acciones activas)
 *   - "Outlined." → icono de contorno (para estados secundarios)
 *   - "Rounded."  → icono redondeado (para botones suaves)
 */
object AppIcons {

    // ── Acciones del header ────────────────────────────────
    val buscar = Icons.Default.Search
    val ajustes = Icons.Default.Settings
    val refrescar = Icons.Default.Refresh
    val cargando = Icons.Default.HourglassEmpty
    val notificaciones = Icons.Default.Notifications
    val notificacionesOff = Icons.Default.NotificationsOff

    // ── Navegación ─────────────────────────────────────────
    val volver = Icons.Default.ArrowBack
    val adelante = Icons.Default.ArrowForward
    val arriba = Icons.Default.KeyboardArrowUp
    val abajo = Icons.Default.KeyboardArrowDown
    val izquierda = Icons.Default.KeyboardArrowLeft
    val derecha = Icons.Default.KeyboardArrowRight

    // ── Reproductor ────────────────────────────────────────
    val play = Icons.Default.PlayArrow
    val pausa = Icons.Default.Pause
    val detener = Icons.Default.Stop
    val volumen = Icons.Default.VolumeUp
    val volumenBajo = Icons.Default.VolumeDown
    val volumenMudo = Icons.Default.VolumeOff
    val pantallaCompleta = Icons.Default.Fullscreen
    val pantallaNormal = Icons.Default.FullscreenExit
    val cast = Icons.Default.Cast

    // ── Info del evento ────────────────────────────────────
    val reloj = Icons.Default.Schedule
    val calendario = Icons.Default.CalendarToday
    val tv = Icons.Default.Tv
    val canales = Icons.Default.LiveTv
    val senal = Icons.Default.Sensors
    val wifi = Icons.Default.Wifi
    val estrella = Icons.Default.Star
    val estrellaBorde = Icons.Default.StarBorder
    val enVivo = Icons.Default.Circle
    val destacado = Icons.Default.Whatshot
    val megafono = Icons.Default.Campaign
    val categoria = Icons.Default.Category

    // ── Estados ────────────────────────────────────────────
    val ok = Icons.Default.Check
    val okCirculo = Icons.Default.CheckCircle
    val error = Icons.Default.ErrorOutline
    val advertencia = Icons.Default.Warning
    val info = Icons.Default.Info
    val bloqueado = Icons.Default.Lock
    val sinConexion = Icons.Default.CloudOff

    // ── Listas / Vacíos ────────────────────────────────────
    val bandeja = Icons.Default.Inbox
    val sinResultados = Icons.Default.SearchOff
    val carpeta = Icons.Default.FolderOpen
    val lista = Icons.Default.ListAlt

    // ── Ajustes ────────────────────────────────────────────
    val calidad = Icons.Default.HighQuality
    val hd = Icons.Default.Hd
    val sd = Icons.Default.Sd
    val cache = Icons.Default.CleaningServices
    val borrar = Icons.Default.Delete
    val datos = Icons.Default.Storage
    val idioma = Icons.Default.Language
    val version = Icons.Default.Info

    // ── Extras ─────────────────────────────────────────────
    val cerrar = Icons.Default.Close
    val agregar = Icons.Default.Add
    val editar = Icons.Default.Edit
    val compartir = Icons.Default.Share
    val favorito = Icons.Default.Favorite
    val favoritoBorde = Icons.Default.FavoriteBorder
    val rayo = Icons.Default.Bolt
    val tendencia = Icons.Default.TrendingUp
    val grafico = Icons.Default.BarChart
    val filtro = Icons.Default.FilterList
    val orden = Icons.Default.Sort
    val buscarLupa = Icons.Default.ManageSearch
    val catalogo = Icons.Default.VideoLibrary
    val pelicula = Icons.Default.Movie
    val trofeo = Icons.Default.EmojiEvents
    val pelota = Icons.Default.SportsSoccer
    val grupos = Icons.Default.Groups
    val mas = Icons.Default.MoreVert
    val menu = Icons.Default.Menu
    val expandir = Icons.Default.ExpandMore
    val colapsar = Icons.Default.ExpandLess

    // ── Iconos outlined (secundarios) ──────────────────────
    val settingsOutlined = Icons.Outlined.Settings
    val searchOutlined = Icons.Outlined.Search
    val refreshOutlined = Icons.Outlined.Refresh

    // ── Iconos rounded (suaves) ────────────────────────────
    val playRounded = Icons.Rounded.PlayArrow
    val starRounded = Icons.Rounded.Star
    val favoriteRounded = Icons.Rounded.Favorite
}
