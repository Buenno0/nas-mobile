package com.buenno.ozymandias.firetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
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

// A arte alinha com a margem da tela, mas cada card reserva `focusInset` para o
// halo de foco — então a lista recua essa folga para as capas ficarem no gutter.
private val ShelfEdge = OzyTvTokens.gutter - OzyTvTokens.focusInset
private val CardSpacing = OzyTvTokens.cardGap - OzyTvTokens.focusInset * 2

// Largura sobre altura da capa. Declarar a proporção, e não a altura, deixa o
// mesmo card servir à prateleira (largura do token) e à grade (largura da célula).
private const val PosterAspect = 2f / 3f

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
    // Com a navegação aberta, o conteúdo recua para o segundo plano em vez de
    // disputar atenção com ela.
    if (railExpanded) {
      Box(Modifier.fillMaxSize().background(Background.copy(alpha = .55f)).zIndex(10f))
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
private fun HomeScreen(
  home: HomeResponse?,
  credential: Credential?,
  error: String?,
  memory: BrowseMemory,
  contentFocus: FocusRequester,
  railFocus: FocusRequester,
  model: AppViewModel,
) {
  if (home == null) {
    if (error != null) FullError(error, model::loadHome) else BrandStatus("Carregando seu acervo…")
    return
  }
  if (home.hero == null && home.continueItems.isEmpty() && home.rows.isEmpty()) {
    EmptyState("Seu acervo aparecerá aqui", "Adicione filmes ou séries ao servidor e atualize a biblioteca.")
    return
  }
  val columnState = rememberLazyListState(initialFirstVisibleItemIndex = memory.homeScroll)
  LazyColumn(
    state = columnState,
    modifier = Modifier.fillMaxSize(),
    verticalArrangement = Arrangement.spacedBy(OzyTvTokens.sectionGap),
  ) {
    home.hero?.let { hero ->
      item(key = "hero") {
        HomeHero(hero, credential, contentFocus, railFocus, memory.homeShelf < 0, { model.playTitle(hero.id) }, { model.openTitle(hero.id) })
      }
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

// Véu do hero em 12 paradas com suavização smoothstep. Poucas paradas lineares
// deixam uma faixa horizontal visível onde o preto translúcido encontra os tons
// médios da foto — é o mesmo cálculo que o HeroBanner do iOS usa.
private val HeroVeil: Brush = Brush.verticalGradient(
  colorStops = (0..12).map { step ->
    val t = step / 12f
    val eased = t * t * (3 - 2 * t)
    (0.34f + 0.66f * t) to Background.copy(alpha = eased)
  }.toTypedArray(),
)

private val HeroSideVeil: Brush = Brush.horizontalGradient(
  0f to Background.copy(alpha = .92f),
  0.22f to Background.copy(alpha = .74f),
  0.48f to Background.copy(alpha = .34f),
  0.72f to Color.Transparent,
)

@Composable
private fun HomeHero(
  title: TitleCard,
  credential: Credential?,
  heroFocus: FocusRequester,
  railFocus: FocusRequester,
  requestInitialFocus: Boolean,
  play: () -> Unit,
  details: () -> Unit,
) {
  LaunchedEffect(title.id, requestInitialFocus) {
    if (requestInitialFocus) { delay(180); heroFocus.requestFocus() }
  }
  Box(Modifier.fillMaxWidth().height(OzyTvTokens.heroHeight)) {
    OzyArtwork(title.backdrop ?: title.poster, credential, ArtworkKind.BACKDROP, Modifier.fillMaxSize())
    Box(Modifier.fillMaxSize().background(HeroSideVeil))
    Box(Modifier.fillMaxSize().background(HeroVeil))
    Column(
      Modifier.align(Alignment.BottomStart)
        .padding(start = OzyTvTokens.gutter, bottom = 40.dp, end = OzyTvTokens.gutter)
        .width(620.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      // Sem uppercase na linha inteira: viraria "2 H". Só o tipo de mídia sobe.
      Text(heroMetadata(title), color = Ink.copy(alpha = .74f), style = OzyType.meta)
      Text(title.name, color = Ink, style = OzyType.display, maxLines = 2, overflow = TextOverflow.Ellipsis)
      Row(
        Modifier.padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
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
private fun ShelfTitle(value: String) =
  Text(value, Modifier.padding(horizontal = OzyTvTokens.gutter), color = Ink, style = OzyType.shelf)

@Composable
private fun ContinueShelf(
  items: List<ContinueItem>,
  credential: Credential?,
  memory: BrowseMemory,
  shelf: Int,
  open: (Int, ContinueItem) -> Unit,
) {
  val initial = if (memory.homeShelf == shelf) memory.homeItem.coerceAtLeast(0) else 0
  val rowState = rememberLazyListState(initialFirstVisibleItemIndex = initial.coerceAtMost((items.size - 1).coerceAtLeast(0)))
  Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
    ShelfTitle("Continuar assistindo")
    LazyRow(
      state = rowState,
      contentPadding = PaddingValues(horizontal = ShelfEdge),
      horizontalArrangement = Arrangement.spacedBy(CardSpacing),
    ) {
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
private fun PosterShelf(
  label: String,
  titles: List<TitleCard>,
  credential: Credential?,
  memory: BrowseMemory,
  shelf: Int,
  open: (Int, TitleCard) -> Unit,
) {
  val initial = if (memory.homeShelf == shelf) memory.homeItem.coerceAtLeast(0) else 0
  val rowState = rememberLazyListState(initialFirstVisibleItemIndex = initial.coerceAtMost((titles.size - 1).coerceAtLeast(0)))
  Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
    ShelfTitle(label)
    LazyRow(
      state = rowState,
      contentPadding = PaddingValues(horizontal = ShelfEdge),
      horizontalArrangement = Arrangement.spacedBy(CardSpacing),
    ) {
      itemsIndexed(titles, key = { _, title -> title.id }) { index, title ->
        PosterCard(title, credential, memory.homeShelf == shelf && memory.homeItem == index) { open(index, title) }
      }
    }
  }
}

@Composable
private fun PosterCard(
  title: TitleCard,
  credential: Credential?,
  restoreFocus: Boolean = false,
  modifier: Modifier = Modifier.width(OzyTvTokens.posterWidth),
  onFocused: () -> Unit = {},
  open: () -> Unit,
) {
  val requester = remember { FocusRequester() }
  var focused by remember { mutableStateOf(false) }
  LaunchedEffect(restoreFocus) { if (restoreFocus) { delay(120); requester.requestFocus() } }
  Column(
    modifier.zIndex(if (focused) 2f else 0f)
      .focusRequester(requester)
      .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused() }
      .ozyClickable(onClick = open),
  ) {
    OzyFocusFrame(focused, Modifier.fillMaxWidth()) {
      OzyArtwork(
        title.poster, credential, ArtworkKind.POSTER,
        Modifier.fillMaxWidth().aspectRatio(PosterAspect),
      )
    }
    // Uma linha só: títulos de dois tamanhos diferentes quebravam em alturas
    // diferentes e desalinhavam as células vizinhas da grade.
    Text(
      title.name,
      Modifier.padding(horizontal = OzyTvTokens.focusInset, vertical = 2.dp),
      color = if (focused) Ink else Muted,
      style = OzyType.label,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      title.year?.toString() ?: if (title.kind == TitleKind.TV) "Série" else "Filme",
      Modifier.padding(horizontal = OzyTvTokens.focusInset),
      color = Muted.copy(alpha = .72f),
      style = OzyType.caption,
      maxLines = 1,
    )
  }
}

@Composable
private fun LandscapeCard(
  title: String,
  subtitle: String,
  image: String?,
  credential: Credential?,
  progress: Double,
  restoreFocus: Boolean,
  open: () -> Unit,
) {
  val requester = remember { FocusRequester() }
  var focused by remember { mutableStateOf(false) }
  LaunchedEffect(restoreFocus) { if (restoreFocus) { delay(120); requester.requestFocus() } }
  Column(
    Modifier.width(OzyTvTokens.landscapeWidth).zIndex(if (focused) 2f else 0f)
      .focusRequester(requester).onFocusChanged { focused = it.isFocused }
      .ozyClickable(onClick = open),
  ) {
    OzyFocusFrame(focused, Modifier.fillMaxWidth()) {
      OzyArtwork(
        image, credential, ArtworkKind.LANDSCAPE,
        Modifier.fillMaxWidth().height(OzyTvTokens.landscapeArtHeight),
      )
      Box(
        Modifier.align(Alignment.Center).size(44.dp).clip(CircleShape)
          .background(Background.copy(alpha = .62f)),
        contentAlignment = Alignment.Center,
      ) { OzyIcon(OzyGlyph.PLAY, tint = Ink, size = 20.dp) }
      Box(
        Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp)
          .background(Background.copy(alpha = .55f))
          .semantics { contentDescription = watchedLabel(progress) },
      ) {
        Box(Modifier.fillMaxWidth(progress.toFloat()).fillMaxHeight().background(Accent))
      }
    }
    Text(
      title,
      Modifier.padding(horizontal = OzyTvTokens.focusInset, vertical = 2.dp),
      color = if (focused) Ink else Muted,
      style = OzyType.label,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      subtitle,
      Modifier.padding(horizontal = OzyTvTokens.focusInset),
      color = Muted.copy(alpha = .72f),
      style = OzyType.caption,
      maxLines = 1,
    )
  }
}

private enum class CatalogFilter { ALL, MOVIES, SERIES }

@Composable
private fun CatalogScreen(ui: AppUiState, contentFocus: FocusRequester, railFocus: FocusRequester, model: AppViewModel) {
  var query by remember { mutableStateOf("") }
  var filter by remember { mutableStateOf(CatalogFilter.ALL) }
  val gridState = rememberLazyGridState(initialFirstVisibleItemIndex = ui.browseMemory.catalogScroll)
  val selectedKind = when (filter) {
    CatalogFilter.MOVIES -> TitleKind.MOVIE
    CatalogFilter.SERIES -> TitleKind.TV
    else -> null
  }
  Column(Modifier.fillMaxSize().padding(top = 40.dp)) {
    Row(
      Modifier.fillMaxWidth().padding(horizontal = OzyTvTokens.gutter),
      verticalAlignment = Alignment.Bottom,
    ) {
      Text("Catálogo", color = Ink, style = OzyType.title)
      Spacer(Modifier.weight(1f))
      Text("${ui.catalog.size} de ${ui.catalogTotal} títulos", color = Muted, style = OzyType.caption)
    }
    Row(
      Modifier.padding(start = ShelfEdge, end = ShelfEdge, top = 18.dp, bottom = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      OutlinedTextField(
        value = query,
        onValueChange = { query = it },
        singleLine = true,
        leadingIcon = { OzyIcon(OzyGlyph.SEARCH, tint = Muted, size = 20.dp) },
        placeholder = { Text("Buscar no acervo", style = OzyType.label) },
        textStyle = OzyType.label,
        modifier = Modifier.width(320.dp)
          .focusRequester(contentFocus).focusProperties { left = railFocus },
        shape = CircleShape,
        colors = OutlinedTextFieldDefaults.colors(
          focusedBorderColor = Accent, unfocusedBorderColor = Line,
          focusedContainerColor = Elevated, unfocusedContainerColor = Surface,
          focusedTextColor = Ink, unfocusedTextColor = Ink,
          focusedPlaceholderColor = Muted, unfocusedPlaceholderColor = Muted,
          cursorColor = Accent,
        ),
      )
      Spacer(Modifier.width(6.dp))
      OzyChip("Tudo", filter == CatalogFilter.ALL) { filter = CatalogFilter.ALL; model.loadCatalog(query, null) }
      OzyChip("Filmes", filter == CatalogFilter.MOVIES) { filter = CatalogFilter.MOVIES; model.loadCatalog(query, TitleKind.MOVIE) }
      OzyChip("Séries", filter == CatalogFilter.SERIES) { filter = CatalogFilter.SERIES; model.loadCatalog(query, TitleKind.TV) }
      Spacer(Modifier.weight(1f))
      OzySecondaryAction("Buscar", OzyGlyph.SEARCH) { model.loadCatalog(query, selectedKind) }
    }
    if (ui.catalog.isEmpty() && !ui.loading) {
      EmptyState("Nenhum título encontrado", if (query.isBlank()) "Seu catálogo está vazio." else "Tente buscar por outro nome.")
    } else {
      // Colunas fixas: com `Adaptive`, a densidade da grade mudava entre uma
      // busca e outra e a tela parecia outra a cada filtro.
      LazyVerticalGrid(
        columns = GridCells.Fixed(5),
        state = gridState,
        horizontalArrangement = Arrangement.spacedBy(CardSpacing),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(start = ShelfEdge, end = ShelfEdge, bottom = 42.dp),
      ) {
        itemsIndexed(ui.catalog, key = { _, title -> title.id }) { index, title ->
          PosterCard(
            title, ui.credential, ui.browseMemory.catalogItem == index,
            modifier = Modifier.fillMaxWidth(),
            onFocused = {
              model.rememberCatalogFocus(index, gridState.firstVisibleItemIndex)
              if (index >= ui.catalog.lastIndex - 4 && ui.catalog.size < ui.catalogTotal && !ui.catalogLoadingMore) {
                model.loadCatalog(query, selectedKind, reset = false)
              }
            },
          ) { model.openTitle(title.id) }
        }
      }
    }
  }
}

@Composable
fun DetailScreen(title: TitleDetail, credential: Credential?, play: (TitleDetail, MediaFile?) -> Unit) {
  val episodes = title.seasons?.flatMap { it.episodes } ?: title.files
  val playFocus = remember { FocusRequester() }
  LaunchedEffect(title.id) { delay(180); playFocus.requestFocus() }
  LazyColumn(Modifier.fillMaxSize()) {
    item {
      Box(Modifier.fillMaxWidth().height(OzyTvTokens.detailHeroHeight)) {
        OzyArtwork(title.backdropUrl ?: title.posterUrl, credential, ArtworkKind.BACKDROP, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(HeroSideVeil))
        Box(Modifier.fillMaxSize().background(HeroVeil))
        Column(
          Modifier.align(Alignment.BottomStart)
            .padding(start = OzyTvTokens.gutter, end = OzyTvTokens.gutter, bottom = 32.dp)
            .width(680.dp),
          verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          Text(detailMetadata(title), color = Ink.copy(alpha = .74f), style = OzyType.meta)
          Text(title.name, color = Ink, style = OzyType.display, maxLines = 2, overflow = TextOverflow.Ellipsis)
          title.overview?.let {
            Text(it, color = Ink.copy(alpha = .78f), style = OzyType.body, maxLines = 3, overflow = TextOverflow.Ellipsis)
          }
          val preferred = title.preferredFile()
          Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OzyPrimaryAction(
              if ((preferred?.position ?: 0.0) > 0) "Continuar" else "Assistir",
              modifier = Modifier.focusRequester(playFocus),
            ) { play(title, null) }
          }
        }
      }
    }
    if (episodes.size > 1) {
      item {
        Text(
          "Episódios",
          Modifier.padding(horizontal = OzyTvTokens.gutter, vertical = 16.dp),
          color = Ink,
          style = OzyType.shelf,
        )
      }
      itemsIndexed(episodes, key = { _, file -> file.id }) { index, file ->
        EpisodeRow(index + 1, file) { play(title, file) }
      }
    }
    item { Spacer(Modifier.height(50.dp)) }
  }
}

@Composable
private fun EpisodeRow(number: Int, file: MediaFile, play: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val progress = safeProgress(file.position ?: 0.0, file.duration)
  OzyFocusFrame(
    focused,
    Modifier.padding(horizontal = ShelfEdge, vertical = 3.dp).fillMaxWidth()
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = play),
  ) {
    Row(
      Modifier.fillMaxWidth().background(if (focused) Elevated else Surface)
        .padding(horizontal = 18.dp, vertical = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      Box(
        Modifier.size(46.dp).clip(RoundedCornerShape(12.dp))
          .background(if (focused) Ink else Elevated),
        contentAlignment = Alignment.Center,
      ) {
        Text(
          file.episode?.let { "E$it" } ?: "E$number",
          color = if (focused) AccentInk else Accent,
          style = OzyType.label,
        )
      }
      Column(Modifier.weight(1f)) {
        Text(
          file.episodeName ?: file.name,
          color = Ink,
          style = OzyType.label,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(duration(file.duration), color = Muted, style = OzyType.caption)
      }
      if (progress > 0) {
        Box(
          Modifier.width(150.dp).height(5.dp).clip(CircleShape).background(Line)
            .semantics { contentDescription = watchedLabel(progress) },
        ) {
          Box(Modifier.fillMaxWidth(progress.toFloat()).fillMaxHeight().background(Accent))
        }
      }
    }
  }
}

@Composable
private fun AccountScreen(ui: AppUiState, contentFocus: FocusRequester, railFocus: FocusRequester, model: AppViewModel) {
  val credential = ui.credential ?: return
  OzySplitShell(
    eyebrow = "Esta televisão",
    title = "Sua conta",
    subtitle = "A sessão foi confirmada pelo seu iPhone e vale neste aparelho.",
    aside = { OzyStatus("Conectado", Okay, Modifier.padding(top = 6.dp)) },
  ) {
    Column(Modifier.fillMaxWidth()) {
      AccountRow("Usuário", credential.username, OzyGlyph.USER)
      AccountRow("Servidor", credential.serverUrl, OzyGlyph.SERVER)
      AccountRow("Sessão válida até", readableExpiry(credential.expiresAt), OzyGlyph.CLOCK, divider = false)
      Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OzySecondaryAction(
          "Trocar servidor",
          OzyGlyph.SERVER,
          Modifier.focusRequester(contentFocus).focusProperties { left = railFocus },
        ) { model.changeServer() }
        OzySecondaryAction("Sair", OzyGlyph.LOGOUT, danger = true) { model.logout() }
      }
    }
  }
}

@Composable
private fun AccountRow(label: String, value: String, glyph: OzyGlyph, divider: Boolean = true) {
  Row(
    Modifier.fillMaxWidth().padding(vertical = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    Box(
      Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(Elevated),
      contentAlignment = Alignment.Center,
    ) { OzyIcon(glyph, tint = Accent, size = 20.dp) }
    Column {
      OzyEyebrow(label, color = Muted)
      Text(value, Modifier.padding(top = 3.dp), color = Ink, style = OzyType.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
  }
  if (divider) Box(Modifier.fillMaxWidth().height(1.dp).background(Line.copy(alpha = .7f)))
}

@Composable
private fun FullError(message: String, retry: () -> Unit) {
  Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
    OzyMark(size = 60.dp)
    Text("Não foi possível carregar", Modifier.padding(top = 18.dp), color = Ink, style = OzyType.shelf)
    Text(message, Modifier.padding(top = 6.dp), color = Danger, style = OzyType.caption)
    Row(Modifier.padding(top = 18.dp)) { OzySecondaryAction("Tentar novamente", onClick = retry) }
  }
}

@Composable
private fun EmptyState(title: String, subtitle: String) {
  Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
    OzyMark(size = 60.dp)
    Text(title, Modifier.padding(top = 18.dp), color = Ink, style = OzyType.shelf)
    Text(subtitle, Modifier.padding(top = 6.dp), color = Muted, style = OzyType.caption)
  }
}

private fun heroMetadata(title: TitleCard): String = listOfNotNull(
  if (title.kind == TitleKind.TV) "SÉRIE" else "FILME",
  title.year?.toString(),
  title.duration?.takeIf { it > 0 }?.let(::duration),
  title.rating?.takeIf { it > 0 }?.let { "★ ${"%.1f".format(it)}" },
).joinToString("  ·  ")

private fun detailMetadata(title: TitleDetail): String = listOfNotNull(
  if (title.kind == TitleKind.TV) "SÉRIE" else "FILME",
  title.year?.toString(),
  title.genres,
  title.rating?.takeIf { it > 0 }?.let { "★ ${"%.1f".format(it)}" },
).joinToString("  ·  ")

private fun duration(seconds: Double): String {
  val total = seconds.toLong().coerceAtLeast(0)
  val hours = total / 3600
  val minutes = (total % 3600) / 60
  return if (hours > 0) "$hours h $minutes min" else "$minutes min"
}

private fun remaining(item: ContinueItem): String =
  "faltam ${((item.duration - item.position).coerceAtLeast(0.0) / 60).toInt()} min"

// A barra de progresso é a única informação do card que não existe como texto;
// sem isto o leitor de tela não tem como dizer quanto já foi assistido.
private fun watchedLabel(progress: Double): String = "${(progress * 100).toInt()}% assistido"

private fun safeProgress(position: Double, duration: Double): Double =
  if (duration > 0) (position / duration).coerceIn(0.0, 1.0) else 0.0

private fun readableExpiry(value: String): String = runCatching {
  java.time.Instant.parse(value).atZone(java.time.ZoneId.systemDefault())
    .format(java.time.format.DateTimeFormatter.ofPattern("dd/MM/yyyy 'às' HH:mm"))
}.getOrDefault(value)
