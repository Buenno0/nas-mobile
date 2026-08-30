package com.buenno.ozymandias.firetv.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.buenno.ozymandias.firetv.AppScreen
import com.buenno.ozymandias.firetv.AppUiState
import com.buenno.ozymandias.firetv.AppViewModel
import com.buenno.ozymandias.firetv.MainTab
import com.buenno.ozymandias.firetv.data.ContinueItem
import com.buenno.ozymandias.firetv.data.Credential
import com.buenno.ozymandias.firetv.data.DeviceStartResponse
import com.buenno.ozymandias.firetv.data.HomeResponse
import com.buenno.ozymandias.firetv.data.MediaFile
import com.buenno.ozymandias.firetv.data.ServerCandidate
import com.buenno.ozymandias.firetv.data.TitleCard
import com.buenno.ozymandias.firetv.data.TitleDetail
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

@Composable
fun OzymandiasApp(model: AppViewModel) {
  val ui by model.ui.collectAsStateWithLifecycle()
  val discovered by model.discoveredServers.collectAsStateWithLifecycle()
  BackHandler(enabled = ui.screen is AppScreen.Pairing || ui.screen is AppScreen.Login || ui.screen is AppScreen.Detail) { model.back() }

  Box(Modifier.fillMaxSize().background(Background)) {
    when (val screen = ui.screen) {
      AppScreen.Restoring -> CenterStatus("Restaurando sessão…")
      AppScreen.Servers -> ServerScreen(discovered, ui.recentServers, ui.error, model::connectServer)
      is AppScreen.Pairing -> PairingScreen(screen.server, screen.pairing, ui.error, model::showManualLogin, model::restartPairing)
      is AppScreen.Login -> LoginScreen(screen.server, ui.error, model::login)
      is AppScreen.Main -> MainScreen(screen.tab, ui, model)
      is AppScreen.Detail -> DetailScreen(screen.title, ui.credential, model::play)
      is AppScreen.Player -> TvPlayerScreen(screen.source, model::saveProgress, model::changeAudio, model::playNext, model::closePlayer)
    }
    if (ui.loading) {
      Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .62f)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
          CircularProgressIndicator(color = Accent)
          ui.preparation?.let { Text("Preparando ${it.percentage}%", Modifier.padding(top = 16.dp), color = Ink) }
        }
      }
    }
  }
}

@Composable
private fun ServerScreen(
  discovered: List<ServerCandidate>,
  recent: List<String>,
  error: String?,
  connect: (String) -> Unit,
) {
  var address by remember { mutableStateOf("") }
  Row(Modifier.fillMaxSize().padding(horizontal = 72.dp, vertical = 48.dp), horizontalArrangement = Arrangement.spacedBy(56.dp)) {
    BrandBlock("Escolha seu servidor", "O Ozymandias procura automaticamente na sua rede.")
    LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
      if (discovered.isNotEmpty()) {
        item { SectionLabel("ENCONTRADOS NA REDE") }
        items(discovered) { server -> TvButton(server.name, server.url) { connect(server.url) } }
      }
      if (recent.isNotEmpty()) {
        item { SectionLabel("RECENTES") }
        items(recent) { server -> TvButton(server.substringAfter("://"), server) { connect(server) } }
      }
      item {
        SectionLabel("OUTRO ENDEREÇO")
        OutlinedTextField(
          value = address,
          onValueChange = { address = it },
          label = { Text("URL do servidor") },
          placeholder = { Text("http://servidor.local:8787") },
          singleLine = true,
          modifier = Modifier.fillMaxWidth(),
        )
      }
      item { TvButton("Conectar", "LAN ou Cloudflare Tunnel", enabled = address.isNotBlank()) { connect(address) } }
      error?.let { item { ErrorText(it) } }
    }
  }
}

@Composable
private fun PairingScreen(
  server: String,
  pairing: DeviceStartResponse,
  error: String?,
  manual: (String) -> Unit,
  restart: (String) -> Unit,
) {
  Row(Modifier.fillMaxSize().padding(72.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(64.dp)) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(20.dp)) {
      Text("Conecte pelo celular", color = Ink, fontSize = 38.sp, fontWeight = FontWeight.Bold)
      Text("Abra o endereço abaixo ou escaneie o QR Code e autorize esta TV.", color = Muted, fontSize = 20.sp)
      Text(pairing.userCode, color = Accent, fontSize = 48.sp, fontWeight = FontWeight.Bold, letterSpacing = 5.sp)
      Text(pairing.verificationUri, color = Ink, fontSize = 17.sp)
      Text("Aguardando autorização…", color = Muted)
      error?.let { ErrorText(it) }
      Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        TvButton("Usar usuário e senha") { manual(server) }
        if (error != null) TvButton("Gerar outro código") { restart(server) }
      }
    }
    Image(qrBitmap(pairing.verificationUriComplete).asImageBitmap(), "QR Code de pareamento", Modifier.size(300.dp).background(Color.White).padding(16.dp))
  }
}

@Composable
private fun LoginScreen(server: String, error: String?, login: (String, String, String) -> Unit) {
  var username by remember { mutableStateOf("") }
  var password by remember { mutableStateOf("") }
  Row(Modifier.fillMaxSize().padding(72.dp), horizontalArrangement = Arrangement.spacedBy(64.dp), verticalAlignment = Alignment.CenterVertically) {
    BrandBlock("Entrar manualmente", server)
    Column(Modifier.width(500.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
      OutlinedTextField(username, { username = it }, label = { Text("Usuário") }, singleLine = true, modifier = Modifier.fillMaxWidth())
      OutlinedTextField(password, { password = it }, label = { Text("Senha") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
      TvButton("Entrar", enabled = username.isNotBlank() && password.isNotBlank()) { login(server, username, password) }
      error?.let { ErrorText(it) }
    }
  }
}

@Composable
private fun MainScreen(tab: MainTab, ui: AppUiState, model: AppViewModel) {
  Column(Modifier.fillMaxSize()) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 54.dp, vertical = 22.dp), verticalAlignment = Alignment.CenterVertically) {
      Text("Ozymandias", color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Bold)
      Spacer(Modifier.weight(1f))
      NavButton("Início", tab == MainTab.HOME) { model.selectTab(MainTab.HOME) }
      NavButton("Catálogo", tab == MainTab.CATALOG) { model.selectTab(MainTab.CATALOG) }
      NavButton("Conta", tab == MainTab.ACCOUNT) { model.selectTab(MainTab.ACCOUNT) }
    }
    when (tab) {
      MainTab.HOME -> HomeScreen(ui.home, ui.credential, ui.error, model::loadHome, model::openTitle)
      MainTab.CATALOG -> CatalogScreen(ui, model)
      MainTab.ACCOUNT -> AccountScreen(ui, model)
    }
  }
}

@Composable
private fun HomeScreen(home: HomeResponse?, credential: Credential?, error: String?, retry: () -> Unit, open: (Long) -> Unit) {
  if (home == null) {
    if (error != null) ErrorState(error, retry) else CenterStatus("Carregando seu acervo…")
    return
  }
  LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(28.dp)) {
    home.hero?.let { hero -> item { Hero(hero, credential) { open(hero.id) } } }
    if (home.continueItems.isNotEmpty()) item { ContinueShelf(home.continueItems, credential, open) }
    items(home.rows) { row -> TitleShelf(row.title, row.items, credential, open) }
    item { Spacer(Modifier.height(32.dp)) }
  }
}

@Composable
private fun Hero(title: TitleCard, credential: Credential?, open: () -> Unit) {
  Box(Modifier.fillMaxWidth().height(390.dp)) {
    AuthImage(title.backdrop ?: title.poster, credential, Modifier.fillMaxSize(), ContentScale.Crop)
    Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Background, Background.copy(.35f), Color.Transparent))))
    Column(Modifier.align(Alignment.CenterStart).padding(start = 58.dp).width(540.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
      Text(title.name, color = Ink, fontSize = 44.sp, lineHeight = 48.sp, fontWeight = FontWeight.Bold)
      Text(listOfNotNull(title.year?.toString(), title.genres).joinToString("  ·  "), color = Muted, fontSize = 18.sp)
      TvButton(if (title.kind == com.buenno.ozymandias.firetv.data.TitleKind.TV) "Ver episódios" else "Assistir") { open() }
    }
  }
}

@Composable
private fun ContinueShelf(items: List<ContinueItem>, credential: Credential?, open: (Long) -> Unit) {
  Shelf("Continuar assistindo") {
    items(items, key = { it.fileId }) { item ->
      Poster(item.titleName, item.poster, credential, progress = item.position / item.duration) { open(item.titleId) }
    }
  }
}

@Composable
private fun TitleShelf(label: String, titles: List<TitleCard>, credential: Credential?, open: (Long) -> Unit) {
  Shelf(label) { items(titles, key = { it.id }) { title -> Poster(title.name, title.poster, credential) { open(title.id) } } }
}

@Composable
private fun Shelf(label: String, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Text(label, Modifier.padding(horizontal = 54.dp), color = Ink, fontSize = 25.sp, fontWeight = FontWeight.SemiBold)
    LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 54.dp), horizontalArrangement = Arrangement.spacedBy(18.dp), content = content)
  }
}

@Composable
private fun CatalogScreen(ui: AppUiState, model: AppViewModel) {
  var query by remember { mutableStateOf("") }
  Column(Modifier.fillMaxSize().padding(horizontal = 54.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
      OutlinedTextField(query, { query = it }, label = { Text("Buscar") }, singleLine = true, modifier = Modifier.width(420.dp))
      TvButton("Buscar") { model.loadCatalog(query) }
      Text("${ui.catalog.size} de ${ui.catalogTotal}", color = Muted)
    }
    Spacer(Modifier.height(22.dp))
    LazyVerticalGrid(columns = GridCells.Adaptive(150.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
      items(ui.catalog, key = { it.id }) { title -> Poster(title.name, title.poster, ui.credential) { model.openTitle(title.id) } }
      if (ui.catalog.size < ui.catalogTotal) item { TvButton("Carregar mais") { model.loadCatalog(query, reset = false) } }
    }
  }
}

@Composable
private fun DetailScreen(title: TitleDetail, credential: Credential?, play: (TitleDetail, MediaFile?) -> Unit) {
  LazyColumn(Modifier.fillMaxSize()) {
    item {
      Box(Modifier.fillMaxWidth().height(410.dp)) {
        AuthImage(title.backdropUrl ?: title.posterUrl, credential, Modifier.fillMaxSize(), ContentScale.Crop)
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Background, Background.copy(.55f), Color.Transparent))))
        Column(Modifier.align(Alignment.CenterStart).padding(64.dp).width(600.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
          Text(title.name, color = Ink, fontSize = 43.sp, fontWeight = FontWeight.Bold)
          Text(listOfNotNull(title.year?.toString(), title.genres, title.rating?.let { "★ $it" }).joinToString("  ·  "), color = Muted)
          title.overview?.let { Text(it, color = Ink, fontSize = 17.sp, maxLines = 4, overflow = TextOverflow.Ellipsis) }
          TvButton(if ((title.preferredFile()?.position ?: 0.0) > 0) "Continuar" else "Assistir") { play(title, null) }
        }
      }
    }
    val episodes = title.seasons?.flatMap { it.episodes } ?: title.files
    if (episodes.size > 1) {
      item { Text("Episódios", Modifier.padding(54.dp, 24.dp, 54.dp, 12.dp), color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Bold) }
      items(episodes, key = { it.id }) { file ->
        TvButton(file.episode?.let { "E$it · ${file.episodeName ?: file.name}" } ?: file.name, duration(file.duration), Modifier.padding(horizontal = 54.dp)) { play(title, file) }
      }
    }
    item { Spacer(Modifier.height(40.dp)) }
  }
}

@Composable
private fun AccountScreen(ui: AppUiState, model: AppViewModel) {
  val credential = ui.credential ?: return
  Row(Modifier.fillMaxSize().padding(70.dp), horizontalArrangement = Arrangement.spacedBy(70.dp)) {
    BrandBlock("Conta", "Sessão confirmada")
    Column(Modifier.width(560.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
      InfoRow("Usuário", credential.username)
      InfoRow("Servidor", credential.serverUrl)
      InfoRow("Válida até", credential.expiresAt)
      TvButton("Sair") { model.logout() }
    }
  }
}

@Composable
private fun Poster(name: String, image: String?, credential: Credential?, progress: Double? = null, open: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val scale by animateFloatAsState(if (focused) 1.07f else 1f, label = "poster")
  Column(
    Modifier.width(150.dp).scale(scale).onFocusChanged { focused = it.isFocused }.focusable().clickable(onClick = open),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Box(Modifier.fillMaxWidth().height(225.dp).clip(RoundedCornerShape(10.dp)).background(Elevated).border(if (focused) 3.dp else 1.dp, if (focused) Accent else Line, RoundedCornerShape(10.dp))) {
      AuthImage(image, credential, Modifier.fillMaxSize(), ContentScale.Crop)
      progress?.let { Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(it.toFloat().coerceIn(0f, 1f)).height(5.dp).background(Accent)) }
    }
    Text(name, color = Ink, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
  }
}

@Composable
private fun TvButton(title: String, subtitle: String? = null, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  val color by animateColorAsState(if (focused && enabled) Accent else Elevated, label = "button")
  val scale by animateFloatAsState(if (focused && enabled) 1.04f else 1f, label = "button-scale")
  Row(
    modifier.fillMaxWidth().scale(scale).clip(RoundedCornerShape(12.dp)).background(color)
      .border(1.dp, if (focused) Accent else Line, RoundedCornerShape(12.dp))
      .onFocusChanged { focused = it.isFocused }.focusable(enabled).clickable(enabled = enabled, onClick = onClick).padding(18.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(Modifier.weight(1f)) {
      Text(title, color = if (focused) Color(0xFF1A1206) else Ink, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
      subtitle?.let { Text(it, color = if (focused) Color(0xFF4A3315) else Muted, fontSize = 13.sp, maxLines = 1) }
    }
  }
}

@Composable private fun TvButton(title: String, modifier: Modifier = Modifier, onClick: () -> Unit) = TvButton(title, null, modifier, true, onClick)

@Composable
private fun NavButton(label: String, selected: Boolean, onClick: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  Text(
    label,
    Modifier.padding(horizontal = 6.dp).clip(RoundedCornerShape(8.dp)).background(if (focused || selected) Elevated else Color.Transparent)
      .border(1.dp, if (focused) Accent else Color.Transparent, RoundedCornerShape(8.dp))
      .onFocusChanged { focused = it.isFocused }.focusable().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 12.dp),
    color = if (selected || focused) Accent else Muted,
    fontWeight = FontWeight.SemiBold,
  )
}

@Composable
private fun AuthImage(path: String?, credential: Credential?, modifier: Modifier, scale: ContentScale) {
  val url = path?.let { if (it.startsWith("http")) it else credential?.serverUrl + it }
  AsyncImage(
    model = url?.let { ImageRequest.Builder(androidx.compose.ui.platform.LocalContext.current).data(it).apply { credential?.let { addHeader("Authorization", "Bearer ${it.token}") } }.crossfade(true).build() },
    contentDescription = null,
    modifier = modifier,
    contentScale = scale,
  )
}

@Composable private fun BrandBlock(title: String, subtitle: String) = Column(Modifier.width(420.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
  Text("OZYMANDIAS", color = Accent, fontSize = 18.sp, letterSpacing = 4.sp, fontWeight = FontWeight.Bold)
  Text(title, color = Ink, fontSize = 38.sp, lineHeight = 42.sp, fontWeight = FontWeight.Bold)
  Text(subtitle, color = Muted, fontSize = 18.sp)
}
@Composable private fun SectionLabel(value: String) = Text(value, color = Muted, fontSize = 13.sp, letterSpacing = 2.sp, modifier = Modifier.padding(top = 12.dp))
@Composable private fun ErrorText(value: String) = Text(value, color = Danger, fontSize = 15.sp)
@Composable private fun CenterStatus(value: String) = Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(value, color = Muted, fontSize = 20.sp) }
@Composable private fun ErrorState(value: String, retry: () -> Unit) = Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) { ErrorText(value); Spacer(Modifier.height(18.dp)); TvButton("Tentar novamente", Modifier.width(300.dp), retry) }
@Composable private fun InfoRow(label: String, value: String) = Column(Modifier.fillMaxWidth().background(Surface, RoundedCornerShape(12.dp)).border(1.dp, Line, RoundedCornerShape(12.dp)).padding(18.dp)) { Text(label.uppercase(), color = Muted, fontSize = 12.sp); Text(value, color = Ink, fontSize = 18.sp) }

private fun duration(seconds: Double): String {
  val total = seconds.toLong().coerceAtLeast(0)
  val hours = total / 3600
  val minutes = (total % 3600) / 60
  return if (hours > 0) "${hours}h ${minutes}min" else "${minutes} min"
}

private fun qrBitmap(value: String): Bitmap {
  val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, 420, 420)
  return Bitmap.createBitmap(420, 420, Bitmap.Config.ARGB_8888).apply {
    for (y in 0 until 420) for (x in 0 until 420) setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
  }
}
