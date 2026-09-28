package com.buenno.ozymandias.firetv.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.buenno.ozymandias.firetv.MainTab

object OzyTvTokens {
  // Uma margem só, em todas as telas. Antes eram 48, 58, 76 e 88 conforme a tela.
  val gutter = 56.dp
  val railCollapsed = 82.dp
  val railExpanded = 210.dp

  // Dois raios: cards e painéis. O raio do halo de foco é a soma dos dois valores
  // abaixo, que é justamente `panelRadius` — os cantos ficam concêntricos.
  val cardRadius = 16.dp
  val panelRadius = 22.dp
  val focusInset = 6.dp

  val posterArtWidth = 144.dp
  val posterArtHeight = 216.dp
  val landscapeArtWidth = 256.dp
  val landscapeArtHeight = 144.dp
  val posterWidth = posterArtWidth + focusInset * 2
  val landscapeWidth = landscapeArtWidth + focusInset * 2

  // 76% da altura útil: sobra uma faixa da primeira prateleira, que é o convite
  // para descer. Ocupando a tela inteira, a Home parecia não ter mais nada.
  val heroHeight = 410.dp
  val detailHeroHeight = 320.dp

  val cardGap = 16.dp
  val sectionGap = 26.dp

  const val focusScale = 1.06f
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

// O único sinal de foco do app: nada de borda em repouso, e no foco um anel
// quente com halo âmbar e elevação. O halo mora numa faixa reservada de
// `focusInset`, então ele nunca é cortado pela lista que contém o card e o
// layout não pula quando o foco chega.
@Composable
fun OzyFocusFrame(
  focused: Boolean,
  modifier: Modifier = Modifier,
  shape: Shape = RoundedCornerShape(OzyTvTokens.cardRadius),
  content: @Composable BoxScope.() -> Unit,
) {
  val scale by animateFloatAsState(
    if (focused) OzyTvTokens.focusScale else 1f, tween(OzyTvTokens.fastMotion), label = "focus-scale")
  val halo by animateColorAsState(
    if (focused) FocusHalo else Color.Transparent, tween(OzyTvTokens.fastMotion), label = "focus-halo")
  Box(
    modifier
      .scale(scale)
      .background(halo, RoundedCornerShape(OzyTvTokens.panelRadius))
      .padding(OzyTvTokens.focusInset)
      .shadow(if (focused) 18.dp else 0.dp, shape, clip = false)
      .clip(shape)
      .then(if (focused) Modifier.border(2.dp, FocusRing, shape) else Modifier),
    content = content,
  )
}

enum class OzyGlyph { HOME, GRID, USER, PLAY, PAUSE, INFO, SERVER, WIFI, SEARCH, LOGOUT, CLOCK }

@Composable
fun OzyMark(modifier: Modifier = Modifier, size: Dp = 52.dp) {
  // Os Path saem do laço de desenho: `drawWithCache` só reconstrói quando o
  // tamanho muda, e não a cada frame. No rail a marca está sempre em tela.
  Spacer(
    modifier.size(size).semantics { contentDescription = "Ozymandias" }.drawWithCache {
      val sx = this.size.width / 96f
      val sy = this.size.height / 96f
      val body = Path().apply {
        moveTo(18f * sx, 22f * sy)
        cubicTo(18f * sx, 14f * sy, 27f * sx, 9f * sy, 48f * sx, 9f * sy)
        cubicTo(69f * sx, 9f * sy, 78f * sx, 14f * sy, 78f * sx, 22f * sy)
        lineTo(78f * sx, 52f * sy)
        cubicTo(78f * sx, 68f * sy, 66f * sx, 80f * sy, 48f * sx, 87f * sy)
        cubicTo(30f * sx, 80f * sy, 18f * sx, 68f * sy, 18f * sx, 52f * sy)
        close()
      }
      val crown = Path().apply {
        moveTo(24f * sx, 24f * sy)
        cubicTo(24f * sx, 18f * sy, 32f * sx, 14f * sy, 48f * sx, 14f * sy)
        cubicTo(64f * sx, 14f * sy, 72f * sx, 18f * sy, 72f * sx, 24f * sy)
        lineTo(72f * sx, 34f * sy); lineTo(24f * sx, 34f * sy); close()
      }
      val play = Path().apply {
        moveTo(41f * sx, 66f * sy); lineTo(41f * sx, 78f * sy); lineTo(55f * sx, 72f * sy); close()
      }
      val shade = AccentInk.copy(alpha = .38f)
      onDrawBehind {
        drawPath(body, Accent)
        drawPath(crown, shade)
        drawRect(shade, Offset(24f * sx, 36f * sy), Size(48f * sx, 4f * sy))
        drawCircle(AccentInk, 8f * sx, Offset(37f * sx, 53f * sy))
        drawCircle(AccentInk, 8f * sx, Offset(59f * sx, 53f * sy))
        drawPath(play, AccentInk)
      }
    }
  )
}

@Composable
fun OzyIcon(glyph: OzyGlyph, modifier: Modifier = Modifier, tint: Color = Ink, size: Dp = 24.dp) {
  Spacer(
    modifier.size(size).drawWithCache {
    val w = this.size.width
    val h = this.size.height
    val stroke = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round)
    // Estes dois são os únicos glifos que precisam de Path. `tint` é lido só no
    // desenho, então uma troca de cor no foco não reconstrói a geometria.
    val outline = when (glyph) {
      OzyGlyph.HOME -> Path().apply { moveTo(w * .15f, h * .48f); lineTo(w * .5f, h * .18f); lineTo(w * .85f, h * .48f); lineTo(w * .78f, h * .48f); lineTo(w * .78f, h * .82f); lineTo(w * .22f, h * .82f); lineTo(w * .22f, h * .48f) }
      OzyGlyph.PLAY -> Path().apply { moveTo(w * .34f, h * .22f); lineTo(w * .34f, h * .78f); lineTo(w * .76f, h * .5f); close() }
      else -> null
    }
    onDrawBehind {
    when (glyph) {
      OzyGlyph.HOME -> outline?.let { drawPath(it, tint, style = stroke) }
      OzyGlyph.GRID -> for (x in listOf(.18f, .56f)) for (y in listOf(.18f, .56f)) drawRoundRect(tint, Offset(w * x, h * y), Size(w * .26f, h * .26f), CornerRadius(2.dp.toPx()), style = stroke)
      OzyGlyph.USER -> { drawCircle(tint, w * .16f, Offset(w * .5f, h * .34f), style = stroke); drawArc(tint, 205f, 130f, false, Offset(w * .2f, h * .48f), Size(w * .6f, h * .43f), style = stroke) }
      OzyGlyph.PLAY -> outline?.let { drawPath(it, tint) }
      OzyGlyph.PAUSE -> { drawRoundRect(tint, Offset(w * .32f, h * .22f), Size(w * .12f, h * .56f), CornerRadius(1.5.dp.toPx())); drawRoundRect(tint, Offset(w * .56f, h * .22f), Size(w * .12f, h * .56f), CornerRadius(1.5.dp.toPx())) }
      OzyGlyph.INFO -> { drawCircle(tint, w * .38f, Offset(w * .5f, h * .5f), style = stroke); drawLine(tint, Offset(w * .5f, h * .45f), Offset(w * .5f, h * .7f), stroke.width, StrokeCap.Round); drawCircle(tint, stroke.width * .55f, Offset(w * .5f, h * .31f)) }
      OzyGlyph.SERVER -> { drawRoundRect(tint, Offset(w * .16f, h * .2f), Size(w * .68f, h * .58f), CornerRadius(3.dp.toPx()), style = stroke); drawLine(tint, Offset(w * .22f, h * .5f), Offset(w * .78f, h * .5f), stroke.width); drawCircle(tint, stroke.width * .7f, Offset(w * .28f, h * .65f)) }
      OzyGlyph.WIFI -> { drawArc(tint, 215f, 110f, false, Offset(w * .12f, h * .18f), Size(w * .76f, h * .64f), style = stroke); drawArc(tint, 215f, 110f, false, Offset(w * .28f, h * .38f), Size(w * .44f, h * .36f), style = stroke); drawCircle(tint, stroke.width * .75f, Offset(w * .5f, h * .78f)) }
      OzyGlyph.SEARCH -> { drawCircle(tint, w * .25f, Offset(w * .43f, h * .42f), style = stroke); drawLine(tint, Offset(w * .61f, h * .61f), Offset(w * .82f, h * .82f), stroke.width, StrokeCap.Round) }
      OzyGlyph.LOGOUT -> { drawArc(tint, 70f, 220f, false, Offset(w * .12f, h * .16f), Size(w * .58f, h * .68f), style = stroke); drawLine(tint, Offset(w * .42f, h * .5f), Offset(w * .88f, h * .5f), stroke.width, StrokeCap.Round); drawLine(tint, Offset(w * .72f, h * .35f), Offset(w * .88f, h * .5f), stroke.width, StrokeCap.Round); drawLine(tint, Offset(w * .72f, h * .65f), Offset(w * .88f, h * .5f), stroke.width, StrokeCap.Round) }
      OzyGlyph.CLOCK -> { drawCircle(tint, w * .36f, Offset(w * .5f, h * .5f), style = stroke); drawLine(tint, Offset(w * .5f, h * .5f), Offset(w * .5f, h * .29f), stroke.width, StrokeCap.Round); drawLine(tint, Offset(w * .5f, h * .5f), Offset(w * .66f, h * .58f), stroke.width, StrokeCap.Round) }
    }
    }
    }
  )
}

// Ação primária: preenchida em `Ink` com texto `AccentInk`. É o par quente
// equivalente ao vidro branco do botão de Assistir no iPhone — a HIG pede cor
// com parcimônia sobre conteúdo colorido, e branco puro sobre o fundo sépia era
// o que mais destoava entre os dois apps.
@Composable
fun OzyPrimaryAction(
  label: String,
  glyph: OzyGlyph = OzyGlyph.PLAY,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  onClick: () -> Unit,
) {
  ActionShell(modifier, enabled, onClick) { focused ->
    Row(
      Modifier
        .clip(CircleShape)
        .background(if (enabled) Ink else Ink.copy(alpha = .38f))
        .then(if (focused) Modifier.border(2.dp, Accent, CircleShape) else Modifier)
        .padding(horizontal = 26.dp, vertical = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
      OzyIcon(glyph, tint = AccentInk, size = 22.dp)
      Text(label, color = AccentInk, style = OzyType.label)
    }
  }
}

@Composable
fun OzySecondaryAction(
  label: String,
  glyph: OzyGlyph? = null,
  modifier: Modifier = Modifier,
  danger: Boolean = false,
  enabled: Boolean = true,
  onClick: () -> Unit,
) {
  ActionShell(modifier, enabled, onClick) { focused ->
    val content = if (focused) AccentInk else if (danger) Danger else Ink
    Row(
      Modifier
        .clip(CircleShape)
        .background(if (focused) Ink else Elevated)
        .border(1.dp, if (focused) Ink else Line, CircleShape)
        .padding(horizontal = 24.dp, vertical = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
      glyph?.let { OzyIcon(it, tint = content, size = 22.dp) }
      Text(label, color = content, style = OzyType.label)
    }
  }
}

@Composable
fun OzyIconAction(glyph: OzyGlyph, description: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
  ActionShell(modifier.semantics { contentDescription = description }, true, onClick) { focused ->
    Box(
      Modifier.size(54.dp).clip(CircleShape)
        .background(if (focused) Ink else Elevated.copy(alpha = .88f))
        .border(1.dp, if (focused) Ink else Line, CircleShape),
      contentAlignment = Alignment.Center,
    ) { OzyIcon(glyph, tint = if (focused) AccentInk else Ink) }
  }
}

// Casca comum das ações: escala, halo e captura de foco vivem num lugar só, para
// botão, chip e ação circular reagirem exatamente igual ao D-pad.
@Composable
private fun ActionShell(
  modifier: Modifier,
  enabled: Boolean,
  onClick: () -> Unit,
  content: @Composable (focused: Boolean) -> Unit,
) {
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(
    if (focused) OzyTvTokens.focusScale else 1f, tween(OzyTvTokens.fastMotion), label = "action-scale")
  val halo by animateColorAsState(
    if (focused) FocusHalo else Color.Transparent, tween(OzyTvTokens.fastMotion), label = "action-halo")
  Box(
    modifier
      .scale(scale)
      .background(halo, CircleShape)
      .padding(5.dp)
      .onFocusChanged { focused = it.isFocused }
      .ozyClickable(enabled, onClick),
  ) { content(focused) }
}

@Composable
fun OzyChip(label: String, selected: Boolean, modifier: Modifier = Modifier, choose: () -> Unit) {
  ActionShell(modifier, true, choose) { focused ->
    Text(
      label,
      Modifier.clip(CircleShape)
        .background(if (focused) Ink else if (selected) Accent.copy(alpha = .12f) else Color.Transparent)
        .border(1.dp, if (focused) Ink else if (selected) Accent.copy(alpha = .55f) else Line, CircleShape)
        .padding(horizontal = 22.dp, vertical = 13.dp),
      color = if (focused) AccentInk else if (selected) Accent else Muted,
      style = OzyType.label,
    )
  }
}

// Rótulo de seção em versalete. Substitui os cinco tratamentos diferentes que
// existiam para a mesma coisa nas telas de conta, catálogo e pareamento.
@Composable
fun OzyEyebrow(value: String, modifier: Modifier = Modifier, color: Color = Accent) =
  Text(value.uppercase(), modifier, color = color, style = OzyType.meta)

// A navegação deixa de ser um painel com borda e vira um degradê que dissolve no
// conteúdo: na TV, uma caixa desenhada por cima da arte parece um app dentro do
// app. A largura não é animada — relayout de tela cheia custa caro no Stick de 1 GB.
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
  val width = if (hasFocus) OzyTvTokens.railExpanded else OzyTvTokens.railCollapsed
  val veil = if (hasFocus) {
    Brush.horizontalGradient(listOf(Surface, Surface, Surface.copy(alpha = .96f), Background.copy(alpha = 0f)))
  } else {
    Brush.horizontalGradient(listOf(Background.copy(alpha = .96f), Background.copy(alpha = .82f), Background.copy(alpha = 0f)))
  }
  Column(
    modifier.width(width).fillMaxHeight().background(veil)
      .onFocusChanged { hasFocus = it.hasFocus; onExpanded(it.hasFocus) }.focusGroup()
      .padding(start = 20.dp, end = 14.dp, top = 30.dp, bottom = 30.dp),
    horizontalAlignment = Alignment.Start,
  ) {
    Row(Modifier.height(56.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
      OzyMark(size = 42.dp)
      if (hasFocus) Text("Ozymandias", color = Ink, style = OzyType.shelf, maxLines = 1)
    }
    Spacer(Modifier.height(46.dp))
    RailItem("Início", OzyGlyph.HOME, selected == MainTab.HOME, hasFocus, if (selected == MainTab.HOME) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.HOME) }
    RailItem("Catálogo", OzyGlyph.GRID, selected == MainTab.CATALOG, hasFocus, if (selected == MainTab.CATALOG) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.CATALOG) }
    Spacer(Modifier.weight(1f))
    RailItem("Conta", OzyGlyph.USER, selected == MainTab.ACCOUNT, hasFocus, if (selected == MainTab.ACCOUNT) selectedFocusRequester else null, contentFocusRequester) { select(MainTab.ACCOUNT) }
  }
}

@Composable
private fun RailItem(
  label: String,
  glyph: OzyGlyph,
  selected: Boolean,
  expanded: Boolean,
  requester: FocusRequester?,
  contentRequester: FocusRequester,
  onClick: () -> Unit,
) {
  var focused by remember { mutableStateOf(false) }
  val content = if (focused) AccentInk else if (selected) Accent else Muted
  Row(
    Modifier.then(if (requester != null) Modifier.focusRequester(requester).focusProperties { right = contentRequester } else Modifier)
      .semantics { contentDescription = label; this.selected = selected }
      .width(if (expanded) 176.dp else 48.dp).height(48.dp).clip(RoundedCornerShape(14.dp))
      .background(if (focused) Ink else Color.Transparent)
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = onClick)
      .padding(horizontal = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    OzyIcon(glyph, tint = content, size = 22.dp)
    if (expanded) Text(label, color = content, style = OzyType.label, maxLines = 1)
  }
  Spacer(Modifier.height(10.dp))
}

// Composição de duas colunas usada pela conta e por todas as telas de entrada.
// Antes, pareamento e conta tinham estruturas diferentes para o mesmo problema e
// pareciam telas de produtos distintos.
@Composable
fun OzySplitShell(
  eyebrow: String,
  title: String,
  subtitle: String,
  modifier: Modifier = Modifier,
  aside: @Composable ColumnScope.() -> Unit = {},
  panel: @Composable BoxScope.() -> Unit,
) {
  Row(
    modifier.fillMaxSize().padding(horizontal = OzyTvTokens.gutter, vertical = 34.dp),
    horizontalArrangement = Arrangement.spacedBy(56.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(Modifier.width(370.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
      OzyMark(size = 56.dp)
      OzyEyebrow(eyebrow)
      Text(title, color = Ink, style = OzyType.display)
      Text(subtitle, color = Muted, style = OzyType.body)
      aside()
    }
    Box(
      Modifier.weight(1f).clip(RoundedCornerShape(OzyTvTokens.panelRadius)).background(Surface)
        .border(1.dp, Line, RoundedCornerShape(OzyTvTokens.panelRadius)).padding(30.dp),
      content = panel,
    )
  }
}

// Ponto de estado: verde para tudo certo, âmbar para espera, vermelho para falha.
@Composable
fun OzyStatus(label: String, tone: Color = Okay, modifier: Modifier = Modifier) {
  Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
    Box(Modifier.size(9.dp).clip(CircleShape).background(tone))
    Text(label, color = tone, style = OzyType.caption)
  }
}
