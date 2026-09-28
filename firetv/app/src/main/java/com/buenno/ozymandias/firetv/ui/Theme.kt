package com.buenno.ozymandias.firetv.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

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

// O foco nunca usa branco puro: Ink é o branco quente do design system, e o halo
// é o âmbar da marca rebaixado. Branco #FFFFFF encostado no fundo sépia é o que
// fazia a TV parecer um app diferente do iPhone.
val FocusRing = Ink.copy(alpha = .94f)
val FocusHalo = Accent.copy(alpha = .16f)

// Escala tipográfica única da TV, lida a três metros. Sete degraus fecham
// todas as telas; antes eram dez tamanhos avulsos sem relação entre si.
object OzyType {
  val display = TextStyle(fontSize = 48.sp, lineHeight = 52.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp)
  val title = TextStyle(fontSize = 32.sp, lineHeight = 37.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp)
  val shelf = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.Medium)
  val body = TextStyle(fontSize = 17.sp, lineHeight = 25.sp)
  val label = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium)
  val caption = TextStyle(fontSize = 14.sp, lineHeight = 19.sp)
  val meta = TextStyle(fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.7.sp)
}

@Composable
fun OzymandiasTheme(content: @Composable () -> Unit) {
  MaterialTheme(
    colorScheme = darkColorScheme(
      primary = Accent,
      onPrimary = AccentInk,
      background = Background,
      onBackground = Ink,
      surface = Surface,
      onSurface = Ink,
      error = Danger,
    ),
    typography = MaterialTheme.typography.copy(
      headlineLarge = OzyType.display,
      headlineMedium = OzyType.title,
      titleLarge = OzyType.shelf,
      bodyLarge = OzyType.body,
      labelLarge = OzyType.label,
      bodyMedium = OzyType.caption,
      labelSmall = OzyType.meta,
    ),
    content = content,
  )
}
