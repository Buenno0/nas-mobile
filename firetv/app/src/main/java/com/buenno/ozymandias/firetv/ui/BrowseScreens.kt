package com.buenno.ozymandias.firetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.zIndex
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.buenno.ozymandias.firetv.AppUiState
import com.buenno.ozymandias.firetv.AppViewModel
import com.buenno.ozymandias.firetv.BrowseMemory
import com.buenno.ozymandias.firetv.MainTab
import com.buenno.ozymandias.firetv.data.ContinueItem
import com.buenno.ozymandias.firetv.data.Credential
import com.buenno.ozymandias.firetv.data.HomeResponse
import com.buenno.ozymandias.firetv.data.MediaFile
import com.buenno.ozymandias.firetv.data.TitleCard
import com.buenno.ozymandias.firetv.data.TitleDetail
import com.buenno.ozymandias.firetv.data.TitleKind
import kotlinx.coroutines.delay

@Composable
fun MainScreen(tab: MainTab, ui: AppUiState, model: AppViewModel) {
  var railExpanded by remember { mutableStateOf(false) }
  val contentFocus = remember { FocusRequester() }
  val railFocus = remember { FocusRequester() }
  BackHandler(enabled = railExpanded) { contentFocus.requestFocus() }

  Box(Modifier.fillMaxSize().background(Background)) {
    Box(Modifier.fillMaxSize().padding(start = OzyTvTokens.railCollapsed)) {
      when (tab) {
        MainTab.HOME -> HomeScreen(ui.home, ui.credential, ui.error, ui.browseMemory, contentFocus, railFocus, model)
        MainTab.CATALOG -> CatalogScreen(ui, contentFocus, railFocus, model)
        MainTab.ACCOUNT -> AccountScreen(ui, contentFocus, railFocus, model)
      }
    }
    OzyNavigationRail(
      selected = tab,
      selectedFocusRequester = railFocus,
      contentFocusRequester = contentFocus,
      modifier = Modifier.align(Alignment.CenterStart).zIndex(20f),
      onExpanded = { railExpanded = it },
      select = model::selectTab,
    )
  }
}

@Composable
private fun HomeScreen(home: HomeResponse?, credential: Credential?, error: String?, memory: BrowseMemory, contentFocus: FocusRequester, railFocus: FocusRequester, model: AppViewModel) {
  if (home == null) {
    if (error != null) FullError(error, model::loadHome) else BrandStatus("Carregando seu acervo…")
    return
  }
  if (home.hero == null && home.continueItems.isEmpty() && home.rows.isEmpty()) {
    EmptyState("Seu acervo aparecerá aqui", "Adicione filmes ou séries ao servidor e atualize a biblioteca.")
    return
  }
  val columnState = rememberLazyListState(initialFirstVisibleItemIndex = memory.homeScroll)
  LazyColumn(state = columnState, modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(34.dp)) {
    home.hero?.let { hero ->
      item(key = "hero") { HomeHero(hero, credential, contentFocus, railFocus, memory.homeShelf < 0, { model.playTitle(hero.id) }, { model.openTitle(hero.id) }) }
    }
    if (home.continueItems.isNotEmpty()) {
      item(key = "continue") {
        ContinueShelf(home.continueItems, credential, memory, shelf = 0) { index, item ->
          model.rememberHomeFocus(0, index, columnState.firstVisibleItemIndex)
          model.openTitle(item.titleId)
        }
      }
    }
    itemsIndexed(home.rows, key = { _, row -> row.key }) { rowIndex, row ->
      val shelf = rowIndex + 1
      PosterShelf(row.title, row.items, credential, memory, shelf) { itemIndex, title ->
        model.rememberHomeFocus(shelf, itemIndex, columnState.firstVisibleItemIndex)
        model.openTitle(title.id)
      }
    }
    item { Spacer(Modifier.height(46.dp)) }
  }
}

@Composable
private fun HomeHero(title: TitleCard, credential: Credential?, heroFocus: FocusRequester, railFocus: FocusRequester, requestInitialFocus: Boolean, play: () -> Unit, details: () -> Unit) {
  LaunchedEffect(title.id, requestInitialFocus) { if (requestInitialFocus) { delay(180); heroFocus.requestFocus() } }
  Box(Modifier.fillMaxWidth().height(510.dp)) {
    OzyArtwork(title.backdrop ?: title.poster, credential, ArtworkKind.BACKDROP, Modifier.fillMaxSize())
    Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Background, Background.copy(alpha=.88f), Background.copy(alpha=.18f), Color.Transparent))))
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent, Background.copy(alpha=.94f)))))
    Column(
      Modifier.align(Alignment.BottomStart).padding(start = 58.dp, bottom = 46.dp).width(680.dp),
      verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
      Text(heroMetadata(title), color = Color.White.copy(alpha=.76f), fontSize = 14.sp, letterSpacing = 1.1.sp, fontWeight = FontWeight.SemiBold)
      Text(title.name, color = Color.White, fontSize = 50.sp, lineHeight = 53.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
      Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        OzyPrimaryAction(
          if (title.kind == TitleKind.TV) "Continuar" else "Assistir",
          modifier = Modifier.focusRequester(heroFocus).focusProperties { left = railFocus },
          onClick = play,
        )
        OzyIconAction(OzyGlyph.INFO, "Detalhes", onClick = details)
      }
    }
  }
}

@Composable
private fun ContinueShelf(items: List<ContinueItem>, credential: Credential?, memory: BrowseMemory, shelf: Int, open: (Int, ContinueItem) -> Unit) {
  val initial = if (memory.homeShelf == shelf) memory.homeItem.coerceAtLeast(0) else 0
  val rowState = rememberLazyListState(initialFirstVisibleItemIndex = initial.coerceAtMost((items.size - 1).coerceAtLeast(0)))
  Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
    ShelfTitle("Continuar assistindo")
    LazyRow(state = rowState, contentPadding = PaddingValues(horizontal = 58.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
      itemsIndexed(items, key = { _, item -> item.fileId }) { index, item ->
        LandscapeCard(
          title = item.titleName,
          subtitle = item.label ?: remaining(item),
          image = item.backdrop ?: item.poster,
          credential = credential,
          progress = safeProgress(item.position, item.duration),
          restoreFocus = memory.homeShelf == shelf && memory.homeItem == index,
        ) { open(index, item) }
      }
    }
  }
}

@Composable
private fun PosterShelf(label: String, titles: List<TitleCard>, credential: Credential?, memory: BrowseMemory, shelf: Int, open: (Int, TitleCard) -> Unit) {
  val initial = if (memory.homeShelf == shelf) memory.homeItem.coerceAtLeast(0) else 0
  val rowState = rememberLazyListState(initialFirstVisibleItemIndex = initial.coerceAtMost((titles.size - 1).coerceAtLeast(0)))
  Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
    ShelfTitle(label)
    LazyRow(state = rowState, contentPadding = PaddingValues(horizontal = 58.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
      itemsIndexed(titles, key = { _, title -> title.id }) { index, title ->
        PosterCard(title, credential, memory.homeShelf == shelf && memory.homeItem == index) { open(index, title) }
      }
    }
  }
}

@Composable private fun ShelfTitle(value: String) = Text(value, Modifier.padding(horizontal = 58.dp), color = Ink, fontSize = 25.sp, fontWeight = FontWeight.SemiBold)

@Composable
private fun PosterCard(
  title: TitleCard,
  credential: Credential?,
  restoreFocus: Boolean = false,
  onFocused: () -> Unit = {},
  open: () -> Unit,
) {
  val requester = remember { FocusRequester() }
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) OzyTvTokens.focusScale else 1f, tween(140), label = "poster-scale")
  LaunchedEffect(restoreFocus) { if (restoreFocus) { delay(120); requester.requestFocus() } }
  Column(
    Modifier.width(OzyTvTokens.posterWidth).scale(scale).zIndex(if (focused) 2f else 0f)
      .focusRequester(requester).onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused() }.ozyClickable(onClick = open),
    verticalArrangement = Arrangement.spacedBy(9.dp),
  ) {
    OzyArtwork(
      title.poster, credential, ArtworkKind.POSTER,
      Modifier.fillMaxWidth().height(OzyTvTokens.posterHeight).clip(RoundedCornerShape(14.dp))
        .border(if (focused) 3.dp else 1.dp, if (focused) Color.White else Line, RoundedCornerShape(14.dp)),
    )
    Text(title.name, color = Ink, fontSize = 15.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    Text(title.year?.toString() ?: if (title.kind == TitleKind.TV) "Série" else "Filme", color = Muted, fontSize = 13.sp)
  }
}

@Composable
private fun LandscapeCard(title: String, subtitle: String, image: String?, credential: Credential?, progress: Double, restoreFocus: Boolean, open: () -> Unit) {
  val requester = remember { FocusRequester() }
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) OzyTvTokens.focusScale else 1f, tween(140), label = "landscape-scale")
  LaunchedEffect(restoreFocus) { if (restoreFocus) { delay(120); requester.requestFocus() } }
  Column(
    Modifier.width(OzyTvTokens.landscapeWidth).scale(scale).zIndex(if (focused) 2f else 0f)
      .focusRequester(requester).onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = open),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Box(Modifier.fillMaxWidth().height(OzyTvTokens.landscapeHeight).clip(RoundedCornerShape(14.dp)).border(if (focused) 3.dp else 1.dp, if (focused) Color.White else Line, RoundedCornerShape(14.dp))) {
      OzyArtwork(image, credential, ArtworkKind.LANDSCAPE, Modifier.fillMaxSize())
      Box(Modifier.align(Alignment.Center).size(46.dp).clip(CircleShape).background(Color.Black.copy(alpha=.62f)), contentAlignment = Alignment.Center) { OzyIcon(OzyGlyph.PLAY, tint = Color.White) }
      Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(progress.toFloat()).height(5.dp).background(Accent))
    }
    Text(title, color = Ink, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    Text(subtitle, color = Muted, fontSize = 13.sp, maxLines = 1)
  }
}

private enum class CatalogFilter { ALL, MOVIES, SERIES }

@Composable
private fun CatalogScreen(ui: AppUiState, contentFocus: FocusRequester, railFocus: FocusRequester, model: AppViewModel) {
  var query by remember { mutableStateOf("") }
  var filter by remember { mutableStateOf(CatalogFilter.ALL) }
  val gridState = rememberLazyGridState(initialFirstVisibleItemIndex = ui.browseMemory.catalogScroll)
  val selectedKind = when (filter) { CatalogFilter.MOVIES -> TitleKind.MOVIE; CatalogFilter.SERIES -> TitleKind.TV; else -> null }
  Column(Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 34.dp)) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
      Text("Catálogo", color = Ink, fontSize = 38.sp, fontWeight = FontWeight.Bold)
      Spacer(Modifier.weight(1f))
      Text("${ui.catalog.size} de ${ui.catalogTotal} títulos", color = Muted, fontSize = 14.sp)
    }
    Row(Modifier.padding(top = 18.dp, bottom = 24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
      OzySecondaryAction("Buscar", OzyGlyph.SEARCH, Modifier.focusRequester(contentFocus).focusProperties { left = railFocus }) { model.loadCatalog(query, selectedKind) }
      OutlinedTextField(
        value = query, onValueChange = { query = it }, singleLine = true,
        leadingIcon = { OzyIcon(OzyGlyph.SEARCH, tint = Muted) }, placeholder = { Text("Buscar no acervo") },
        modifier = Modifier.width(330.dp).focusProperties { left = railFocus }, shape = RoundedCornerShape(50),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Accent, unfocusedBorderColor = Line, focusedContainerColor = Elevated, unfocusedContainerColor = Surface, focusedTextColor = Ink, unfocusedTextColor = Ink),
      )
      FilterChip("Tudo", filter == CatalogFilter.ALL) { filter = CatalogFilter.ALL; model.loadCatalog(query, null) }
      FilterChip("Filmes", filter == CatalogFilter.MOVIES) { filter = CatalogFilter.MOVIES; model.loadCatalog(query, TitleKind.MOVIE) }
      FilterChip("Séries", filter == CatalogFilter.SERIES) { filter = CatalogFilter.SERIES; model.loadCatalog(query, TitleKind.TV) }
    }
    if (ui.catalog.isEmpty() && !ui.loading) {
      EmptyState("Nenhum título encontrado", if (query.isBlank()) "Seu catálogo está vazio." else "Tente buscar por outro nome.")
    } else {
      LazyVerticalGrid(
        columns = GridCells.Adaptive(OzyTvTokens.posterWidth), state = gridState,
        horizontalArrangement = Arrangement.spacedBy(22.dp), verticalArrangement = Arrangement.spacedBy(28.dp),
        contentPadding = PaddingValues(bottom = 42.dp),
      ) {
        itemsIndexed(ui.catalog, key = { _, title -> title.id }) { index, title ->
          PosterCard(
            title, ui.credential, ui.browseMemory.catalogItem == index,
            onFocused = {
              model.rememberCatalogFocus(index, gridState.firstVisibleItemIndex)
              if (index >= ui.catalog.lastIndex - 4 && ui.catalog.size < ui.catalogTotal && !ui.catalogLoadingMore) model.loadCatalog(query, selectedKind, reset = false)
            },
          ) { model.openTitle(title.id) }
        }
      }
    }
  }
}

@Composable
private fun FilterChip(label: String, selected: Boolean, choose: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val background by animateColorAsState(if (focused) Ink else if (selected) Elevated else Color.Transparent, tween(140), label = "chip")
  Text(
    label,
    Modifier.clip(RoundedCornerShape(50)).background(background).border(1.dp, if (focused) Color.White else if (selected) Accent else Line, RoundedCornerShape(50))
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = choose).padding(horizontal = 18.dp, vertical = 12.dp),
    color = if (focused) Background else if (selected) Accent else Muted, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
  )
}

@Composable
fun DetailScreen(title: TitleDetail, credential: Credential?, play: (TitleDetail, MediaFile?) -> Unit) {
  val episodes = title.seasons?.flatMap { it.episodes } ?: title.files
  val playFocus = remember { FocusRequester() }
  LaunchedEffect(title.id) { delay(180); playFocus.requestFocus() }
  LazyColumn(Modifier.fillMaxSize()) {
    item {
      Box(Modifier.fillMaxWidth().height(590.dp)) {
        OzyArtwork(title.backdropUrl ?: title.posterUrl, credential, ArtworkKind.BACKDROP, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Background, Background.copy(alpha=.9f), Background.copy(alpha=.18f), Color.Transparent))))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent, Background))))
        Column(Modifier.align(Alignment.BottomStart).padding(start = 76.dp, bottom = 54.dp).width(760.dp), verticalArrangement = Arrangement.spacedBy(13.dp)) {
          Text(detailMetadata(title), color = Color.White.copy(alpha=.76f), fontSize = 14.sp, letterSpacing = 1.sp, fontWeight = FontWeight.SemiBold)
          Text(title.name, color = Color.White, fontSize = 49.sp, lineHeight = 52.sp, fontWeight = FontWeight.Bold, maxLines = 2)
          title.overview?.let { Text(it, color = Color.White.copy(alpha=.82f), fontSize = 16.sp, lineHeight = 23.sp, maxLines = 4, overflow = TextOverflow.Ellipsis) }
          val preferred = title.preferredFile()
          Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OzyPrimaryAction(
              if ((preferred?.position ?: 0.0) > 0) "Continuar" else "Assistir",
              modifier = Modifier.focusRequester(playFocus),
            ) { play(title, null) }
          }
        }
      }
    }
    if (episodes.size > 1) {
      item { Text("Episódios", Modifier.padding(horizontal = 76.dp, vertical = 18.dp), color = Ink, fontSize = 27.sp, fontWeight = FontWeight.SemiBold) }
      itemsIndexed(episodes, key = { _, file -> file.id }) { _, file -> EpisodeRow(file) { play(title, file) } }
    }
    item { Spacer(Modifier.height(50.dp)) }
  }
}

@Composable
private fun EpisodeRow(file: MediaFile, play: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  Row(
    Modifier.padding(horizontal = 76.dp, vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(15.dp))
      .background(if (focused) Elevated else Surface).border(1.dp, if (focused) Color.White else Line, RoundedCornerShape(15.dp))
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = play).padding(horizontal = 20.dp, vertical = 15.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(18.dp),
  ) {
    Box(Modifier.size(46.dp).clip(CircleShape).background(if (focused) Color.White else Background), contentAlignment = Alignment.Center) { OzyIcon(OzyGlyph.PLAY, tint = if (focused) Color.Black else Accent) }
    Column(Modifier.weight(1f)) {
      Text(file.episode?.let { "E$it · ${file.episodeName ?: file.name}" } ?: file.name, color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      Text(duration(file.duration), color = Muted, fontSize = 13.sp)
    }
    val progress = safeProgress(file.position ?: 0.0, file.duration)
    if (progress > 0) {
      Box(Modifier.width(180.dp).height(4.dp).clip(RoundedCornerShape(50)).background(Line)) {
        Box(Modifier.fillMaxWidth(progress.toFloat()).fillMaxHeight().background(Accent))
      }
    }
  }
}

@Composable
private fun AccountScreen(ui: AppUiState, contentFocus: FocusRequester, railFocus: FocusRequester, model: AppViewModel) {
  val credential = ui.credential ?: return
  Row(Modifier.fillMaxSize().padding(horizontal = 88.dp, vertical = 64.dp), horizontalArrangement = Arrangement.spacedBy(70.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.width(430.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
      OzyMark(size = 88.dp)
      Text("Sua conta", color = Ink, fontSize = 42.sp, fontWeight = FontWeight.Bold)
      Text("Sessão confirmada neste Fire TV.", color = Muted, fontSize = 18.sp)
      Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(Okay))
        Text("Conectado", color = Okay, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
      }
    }
    Column(
      Modifier.weight(1f).clip(RoundedCornerShape(22.dp)).background(Surface).border(1.dp, Line, RoundedCornerShape(22.dp)).padding(28.dp),
      verticalArrangement = Arrangement.spacedBy(0.dp),
    ) {
      AccountRow("Usuário", credential.username, OzyGlyph.USER)
      AccountRow("Servidor", credential.serverUrl, OzyGlyph.SERVER)
      AccountRow("Sessão válida até", readableExpiry(credential.expiresAt), OzyGlyph.CLOCK, divider = false)
      Row(Modifier.padding(top = 26.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OzySecondaryAction("Trocar servidor", OzyGlyph.SERVER, Modifier.focusRequester(contentFocus).focusProperties { left = railFocus }) { model.changeServer() }
        OzySecondaryAction("Sair", OzyGlyph.LOGOUT, danger = true) { model.logout() }
      }
    }
  }
}

@Composable
private fun AccountRow(label: String, value: String, glyph: OzyGlyph, divider: Boolean = true) {
  Row(Modifier.fillMaxWidth().padding(vertical = 17.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
    Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(Elevated), contentAlignment = Alignment.Center) { OzyIcon(glyph, tint = Accent) }
    Column {
      Text(label.uppercase(), color = Muted, fontSize = 11.sp, letterSpacing = 1.3.sp, fontWeight = FontWeight.Bold)
      Text(value, color = Ink, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
  }
  if (divider) Box(Modifier.fillMaxWidth().height(1.dp).background(Line.copy(alpha=.7f)))
}

@Composable
private fun FullError(message: String, retry: () -> Unit) {
  Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
    OzyMark(size = 68.dp)
    Text("Não foi possível carregar", Modifier.padding(top = 20.dp), color = Ink, fontSize = 25.sp, fontWeight = FontWeight.SemiBold)
    Text(message, Modifier.padding(top = 8.dp), color = Danger, fontSize = 15.sp)
    Row(Modifier.padding(top = 20.dp)) { OzySecondaryAction("Tentar novamente", onClick = retry) }
  }
}

@Composable
private fun EmptyState(title: String, subtitle: String) {
  Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
    OzyMark(size = 68.dp)
    Text(title, Modifier.padding(top = 20.dp), color = Ink, fontSize = 25.sp, fontWeight = FontWeight.SemiBold)
    Text(subtitle, Modifier.padding(top = 8.dp), color = Muted, fontSize = 15.sp)
  }
}

private fun heroMetadata(title: TitleCard): String = listOfNotNull(
  if (title.kind == TitleKind.TV) "SÉRIE" else "FILME",
  title.year?.toString(),
  title.duration?.takeIf { it > 0 }?.let(::duration),
  title.rating?.takeIf { it > 0 }?.let { "★ ${"%.1f".format(it)}" },
).joinToString("  ·  ")

private fun detailMetadata(title: TitleDetail): String = listOfNotNull(
  if (title.kind == TitleKind.TV) "SÉRIE" else "FILME", title.year?.toString(), title.genres,
  title.rating?.takeIf { it > 0 }?.let { "★ ${"%.1f".format(it)}" },
).joinToString("  ·  ")

private fun duration(seconds: Double): String {
  val total = seconds.toLong().coerceAtLeast(0)
  val hours = total / 3600
  val minutes = (total % 3600) / 60
  return if (hours > 0) "${hours} h ${minutes} min" else "${minutes} min"
}

private fun remaining(item: ContinueItem): String = "faltam ${((item.duration - item.position).coerceAtLeast(0.0) / 60).toInt()} min"
private fun safeProgress(position: Double, duration: Double): Double = if (duration > 0) (position / duration).coerceIn(0.0, 1.0) else 0.0
private fun readableExpiry(value: String): String = runCatching {
  java.time.Instant.parse(value).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("dd/MM/yyyy 'às' HH:mm"))
}.getOrDefault(value)
