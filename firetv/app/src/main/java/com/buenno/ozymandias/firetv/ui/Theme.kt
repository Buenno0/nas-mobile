package com.buenno.ozymandias.firetv.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Background = Color(0xFF0C0A08)
val Surface = Color(0xFF16130F)
val Elevated = Color(0xFF211C15)
val Line = Color(0xFF40372B)
val Ink = Color(0xFFF4EFE4)
val Muted = Color(0xFFA99A84)
val Accent = Color(0xFFD29A44)
val Danger = Color(0xFFE08163)
val AccentInk = Color(0xFF1A1206)
val Okay = Color(0xFF7FB79A)
val Warning = Color(0xFFDCA84A)

@Composable
fun OzymandiasTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = darkColorScheme(
      primary = Accent,
      onPrimary = Color(0xFF1A1206),
      background = Background,
      onBackground = Ink,
      surface = Surface,
      onSurface = Ink,
      error = Danger,
    ),
    content = content,
  )
}
