package com.anonimus757.tvapp.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Logger observable en vivo. Se muestra en pantalla con toque largo en el logo FutTV.
 * Ayuda a diagnosticar problemas sin adb.
 */
object DebugLog {
    private val _lineas = MutableStateFlow<List<String>>(emptyList())
    val lineas: StateFlow<List<String>> = _lineas.asStateFlow()

    fun log(msg: String) {
        val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())
        val nueva = "[$t] $msg"
        _lineas.value = (_lineas.value + nueva).takeLast(30)
    }

    fun limpiar() { _lineas.value = emptyList() }
}
