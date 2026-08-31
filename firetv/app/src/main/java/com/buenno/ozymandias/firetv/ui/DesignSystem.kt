package com.buenno.ozymandias.firetv.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.buenno.ozymandias.firetv.MainTab

object OzyTvTokens {
  val screenPadding = 54.dp
  val railCollapsed = 82.dp
  val railExpanded = 236.dp
  val cardRadius = 16.dp
  val posterWidth = 164.dp
  val posterHeight = 246.dp
  val landscapeWidth = 286.dp
  val landscapeHeight = 161.dp
  const val focusScale = 1.045f
  const val fastMotion = 140
  const val regularMotion = 180
  const val posterPixelsWidth = 328
  const val posterPixelsHeight = 492
  const val backdropPixelsWidth = 1280
  const val backdropPixelsHeight = 720
}

fun Modifier.ozyClickable(enabled: Boolean = true, onClick: () -> Unit): Modifier =
  onPreviewKeyEvent { event ->
    if (enabled && event.type == KeyEventType.KeyUp && (event.key == Key.DirectionCenter || event.key == Key.Enter)) {
      onClick()
      true
    } else {
      false
    }
  }.clickable(enabled = enabled, onClick = onClick)

enum class OzyGlyph { HOME, GRID, USER, PLAY, INFO, SERVER, WIFI, SEARCH, LOGOUT, CLOCK }

@Composable
fun OzyMark(modifier: Modifier = Modifier, size: Dp = 52.dp) {
  Canvas(modifier.size(size).semantics { contentDescription = "Ozymandias" }) {
    val sx = this.size.width / 96f
    val sy = this.size.height / 96f
    fun p(x: Float, y: Float) = Offset(x * sx, y * sy)
    val body = Path().apply {
      moveTo(18f * sx, 22f * sy)
      cubicTo(18f * sx, 14f * sy, 27f * sx, 9f * sy, 48f * sx, 9f * sy)
      cubicTo(69f * sx, 9f * sy, 78f * sx, 14f * sy, 78f * sx, 22f * sy)
      lineTo(78f * sx, 52f * sy)
      cubicTo(78f * sx, 68f * sy, 66f * sx, 80f * sy, 48f * sx, 87f * sy)
      cubicTo(30f * sx, 80f * sy, 18f * sx, 68f * sy, 18f * sx, 52f * sy)
      close()
    }
    drawPath(body, Accent)
    val crown = Path().apply {
      moveTo(24f * sx, 24f * sy)
      cubicTo(24f * sx, 18f * sy, 32f * sx, 14f * sy, 48f * sx, 14f * sy)
      cubicTo(64f * sx, 14f * sy, 72f * sx, 18f * sy, 72f * sx, 24f * sy)
      lineTo(72f * sx, 34f * sy); lineTo(24f * sx, 34f * sy); close()
    }
    drawPath(crown, AccentInk.copy(alpha = .38f))
    drawRect(AccentInk.copy(alpha = .38f), p(24f, 36f), androidx.compose.ui.geometry.Size(48f * sx, 4f * sy))
    drawCircle(AccentInk, 8f * sx, p(37f, 53f))
    drawCircle(AccentInk, 8f * sx, p(59f, 53f))
    val play = Path().apply {
      moveTo(41f * sx, 66f * sy); lineTo(41f * sx, 78f * sy); lineTo(55f * sx, 72f * sy); close()
    }
    drawPath(play, AccentInk)
  }
}

@Composable
fun OzyIcon(glyph: OzyGlyph, modifier: Modifier = Modifier, tint: Color = Ink) {
  Canvas(modifier.size(24.dp)) {
    val w = size.width
    val h = size.height
    val stroke = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round)
    when (glyph) {
      OzyGlyph.HOME -> {
        val path = Path().apply { moveTo(w * .15f, h * .48f); lineTo(w * .5f, h * .18f); lineTo(w * .85f, h * .48f); lineTo(w * .78f, h * .48f); lineTo(w * .78f, h * .82f); lineTo(w * .22f, h * .82f); lineTo(w * .22f, h * .48f) }
        drawPath(path, tint, style = stroke)
      }
      OzyGlyph.GRID -> for (x in listOf(.18f, .56f)) for (y in listOf(.18f, .56f)) drawRoundRect(tint, Offset(w*x, h*y), androidx.compose.ui.geometry.Size(w*.26f,h*.26f), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()), style = stroke)
      OzyGlyph.USER -> { drawCircle(tint, w*.16f, Offset(w*.5f,h*.34f), style = stroke); drawArc(tint, 205f, 130f, false, Offset(w*.2f,h*.48f), androidx.compose.ui.geometry.Size(w*.6f,h*.43f), style = stroke) }
      OzyGlyph.PLAY -> drawPath(Path().apply { moveTo(w*.34f,h*.22f); lineTo(w*.34f,h*.78f); lineTo(w*.76f,h*.5f); close() }, tint)
      OzyGlyph.INFO -> { drawCircle(tint, w*.38f, Offset(w*.5f,h*.5f), style=stroke); drawLine(tint, Offset(w*.5f,h*.45f), Offset(w*.5f,h*.7f), stroke.width, StrokeCap.Round); drawCircle(tint, stroke.width*.55f, Offset(w*.5f,h*.31f)) }
      OzyGlyph.SERVER -> { drawRoundRect(tint, Offset(w*.16f,h*.2f), androidx.compose.ui.geometry.Size(w*.68f,h*.58f), androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()), style=stroke); drawLine(tint,Offset(w*.22f,h*.5f),Offset(w*.78f,h*.5f),stroke.width); drawCircle(tint,stroke.width*.7f,Offset(w*.28f,h*.65f)) }
      OzyGlyph.WIFI -> { drawArc(tint, 215f, 110f, false, Offset(w*.12f,h*.18f), androidx.compose.ui.geometry.Size(w*.76f,h*.64f), style=stroke); drawArc(tint,215f,110f,false,Offset(w*.28f,h*.38f),androidx.compose.ui.geometry.Size(w*.44f,h*.36f),style=stroke); drawCircle(tint,stroke.width*.75f,Offset(w*.5f,h*.78f)) }
      OzyGlyph.SEARCH -> { drawCircle(tint,w*.25f,Offset(w*.43f,h*.42f),style=stroke); drawLine(tint,Offset(w*.61f,h*.61f),Offset(w*.82f,h*.82f),stroke.width,StrokeCap.Round) }
      OzyGlyph.LOGOUT -> { drawArc(tint, 70f, 220f, false, Offset(w*.12f,h*.16f), androidx.compose.ui.geometry.Size(w*.58f,h*.68f), style=stroke); drawLine(tint,Offset(w*.42f,h*.5f),Offset(w*.88f,h*.5f),stroke.width,StrokeCap.Round); drawLine(tint,Offset(w*.72f,h*.35f),Offset(w*.88f,h*.5f),stroke.width,StrokeCap.Round); drawLine(tint,Offset(w*.72f,h*.65f),Offset(w*.88f,h*.5f),stroke.width,StrokeCap.Round) }
      OzyGlyph.CLOCK -> { drawCircle(tint,w*.36f,Offset(w*.5f,h*.5f),style=stroke); drawLine(tint,Offset(w*.5f,h*.5f),Offset(w*.5f,h*.29f),stroke.width,StrokeCap.Round); drawLine(tint,Offset(w*.5f,h*.5f),Offset(w*.66f,h*.58f),stroke.width,StrokeCap.Round) }
    }
  }
}

@Composable
fun OzyPrimaryAction(label: String, glyph: OzyGlyph = OzyGlyph.PLAY, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) OzyTvTokens.focusScale else 1f, tween(OzyTvTokens.fastMotion), label = "primary-scale")
  Row(
    modifier.scale(scale).clip(RoundedCornerShape(50)).background(if (enabled) Color.White else Color.White.copy(alpha=.35f))
      .border(2.dp, if (focused) Accent else Color.Transparent, RoundedCornerShape(50))
      .onFocusChanged { focused = it.isFocused }.ozyClickable(enabled, onClick)
      .padding(horizontal = 24.dp, vertical = 13.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    OzyIcon(glyph, tint = Color.Black)
    androidx.compose.material3.Text(label, color = Color.Black, fontSize = 17.sp, fontWeight = FontWeight.Bold)
  }
}

@Composable
fun OzySecondaryAction(label: String, glyph: OzyGlyph? = null, modifier: Modifier = Modifier, danger: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) 1.035f else 1f, tween(OzyTvTokens.fastMotion), label = "secondary-scale")
  val border by animateColorAsState(if (focused) Color.White else Line, tween(OzyTvTokens.fastMotion), label = "secondary-border")
  Row(
    modifier.scale(scale).clip(RoundedCornerShape(50)).background(if (focused) Ink else Elevated)
      .border(1.dp, border, RoundedCornerShape(50)).onFocusChanged { focused = it.isFocused }
      .ozyClickable(enabled, onClick).padding(horizontal = 22.dp, vertical = 13.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    glyph?.let { OzyIcon(it, tint = if (focused) Background else if (danger) Danger else Ink) }
    androidx.compose.material3.Text(label, color = if (focused) Background else if (danger) Danger else Ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
  }
}

@Composable
fun OzyIconAction(glyph: OzyGlyph, description: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) OzyTvTokens.focusScale else 1f, tween(OzyTvTokens.fastMotion), label = "icon-scale")
  Box(
    modifier.size(52.dp).scale(scale).semantics { contentDescription = description }.clip(CircleShape).background(if (focused) Color.White else Color.Black.copy(alpha=.58f))
      .border(1.dp, if (focused) Color.White else Color.White.copy(alpha=.28f), CircleShape)
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) { OzyIcon(glyph, tint = if (focused) Color.Black else Color.White) }
}

@Composable
fun OzyNavigationRail(
  selected: MainTab,
  selectedFocusRequester: FocusRequester,
  contentFocusRequester: FocusRequester,
  modifier: Modifier = Modifier,
  onExpanded: (Boolean) -> Unit,
  select: (MainTab) -> Unit,
) {
  var hasFocus by remember { mutableStateOf(false) }
  // Animar largura força relayout da tela inteira no Fire Stick de 1 GB.
  val width = if (hasFocus) OzyTvTokens.railExpanded else OzyTvTokens.railCollapsed
  Column(
    modifier.width(width).fillMaxHeight().background(Background.copy(alpha=.97f))
      .border(width = 1.dp, color = Line.copy(alpha=.55f), shape = RoundedCornerShape(topEnd = 18.dp, bottomEnd = 18.dp))
      .onFocusChanged { hasFocus = it.hasFocus; onExpanded(it.hasFocus) }.focusGroup()
      .padding(horizontal = 14.dp, vertical = 28.dp),
    horizontalAlignment = Alignment.Start,
  ) {
    Row(Modifier.height(58.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
      OzyMark(size = 48.dp)
      if (hasFocus) androidx.compose.material3.Text("Ozymandias", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
    Spacer(Modifier.height(42.dp))
    RailItem("Início", OzyGlyph.HOME, selected == MainTab.HOME, hasFocus, if (selected == MainTab.HOME) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.HOME) }
    RailItem("Catálogo", OzyGlyph.GRID, selected == MainTab.CATALOG, hasFocus, if (selected == MainTab.CATALOG) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.CATALOG) }
    Spacer(Modifier.weight(1f))
    RailItem("Conta", OzyGlyph.USER, selected == MainTab.ACCOUNT, hasFocus, if (selected == MainTab.ACCOUNT) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.ACCOUNT) }
  }
}

@Composable
private fun RailItem(label: String, glyph: OzyGlyph, selected: Boolean, expanded: Boolean, requester: FocusRequester?, contentRequester: FocusRequester, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  Row(
    Modifier.then(if (requester != null) Modifier.focusRequester(requester).focusProperties { right = contentRequester } else Modifier)
      .semantics { contentDescription = label; this.selected = selected }
      .width(if (expanded) 208.dp else 54.dp).height(54.dp).clip(RoundedCornerShape(14.dp))
      .background(if (focused) Ink else if (selected) Elevated else Color.Transparent)
      .border(1.dp, if (focused) Color.White else if (selected) Line else Color.Transparent, RoundedCornerShape(14.dp))
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = onClick).padding(horizontal = 15.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    OzyIcon(glyph, tint = if (focused) Background else if (selected) Accent else Muted)
    if (expanded) androidx.compose.material3.Text(label, color = if (focused) Background else if (selected) Ink else Muted, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
  }
  Spacer(Modifier.height(8.dp))
}
