package com.buenno.ozymandias.firetv

import com.buenno.ozymandias.firetv.data.ApiException
import com.buenno.ozymandias.firetv.data.Credential
import com.buenno.ozymandias.firetv.data.DeviceStartResponse
import com.buenno.ozymandias.firetv.data.HealthResponse
import com.buenno.ozymandias.firetv.data.HomeResponse
import com.buenno.ozymandias.firetv.data.HomeRow
import com.buenno.ozymandias.firetv.data.MediaFile
import com.buenno.ozymandias.firetv.data.MediaRepository
import com.buenno.ozymandias.firetv.data.MediaTracks
import com.buenno.ozymandias.firetv.data.PlaybackFile
import com.buenno.ozymandias.firetv.data.PlaybackSource
import com.buenno.ozymandias.firetv.data.PreparationProgress
import com.buenno.ozymandias.firetv.data.ServerCandidate
import com.buenno.ozymandias.firetv.data.SessionVault
import com.buenno.ozymandias.firetv.data.TitleCard
import com.buenno.ozymandias.firetv.data.TitleDetail
import com.buenno.ozymandias.firetv.data.TitleKind
import com.buenno.ozymandias.firetv.data.TitlesPage
import com.buenno.ozymandias.firetv.data.User
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppViewModelTest {
  private val repository = FakeRepository()
  private val vault = FakeVault()

  @Before fun useTestDispatcher() = Dispatchers.setMain(UnconfinedTestDispatcher())

  @After fun restoreDispatcher() = Dispatchers.resetMain()

  private fun model() = AppViewModel(repository, vault, emptyFlow())

  // ---------- restauração ----------

  @Test fun withoutCredentialTheAppAsksForAServer() = runTest {
    val ui = model().ui.value
    assertEquals(AppScreen.Servers, ui.screen)
    assertNull(ui.credential)
  }

  @Test fun expiredCredentialIsDiscardedBeforeAskingForAServer() = runTest {
    vault.stored = credential(expiresAt = "2000-01-01T00:00:00Z")
    val ui = model().ui.value
    assertEquals(AppScreen.Servers, ui.screen)
    assertTrue(vault.cleared)
  }

  @Test fun validCredentialRestoresTheSessionAndLoadsHome() = runTest {
    vault.stored = credential()
    val ui = model().ui.value
    assertEquals(AppScreen.Main(MainTab.HOME), ui.screen)
    assertEquals("bueno", ui.credential?.username)
    assertEquals(1, ui.home?.rows?.size)
  }

  // ---------- sessão revogada ----------

  @Test fun unauthorizedHomeEndsTheSessionAndExplainsWhy() = runTest {
    vault.stored = credential()
    repository.homeError = ApiException(401, "expirado")
    val ui = model().ui.value
    assertEquals(AppScreen.Servers, ui.screen)
    assertNull(ui.credential)
    assertTrue(vault.cleared)
    assertEquals("Sua sessão expirou. Conecte-se novamente.", ui.error)
  }

  // Uma falha de rede não é uma sessão inválida: a credencial fica, para o
  // usuário poder tentar de novo sem repetir o pareamento.
  @Test fun transientHomeFailureKeepsTheSession() = runTest {
    vault.stored = credential()
    repository.homeError = ApiException(0, "sem rede")
    val model = model()
    assertEquals(AppScreen.Main(MainTab.HOME), model.ui.value.screen)
    assertEquals("sem rede", model.ui.value.error)
    assertEquals("bueno", model.ui.value.credential?.username)
  }

  // ---------- catálogo ----------

  @Test fun catalogLoadsOnceWhenTheTabIsOpened() = runTest {
    vault.stored = credential()
    val model = model()
    model.selectTab(MainTab.CATALOG)
    assertEquals(1, repository.titleCalls)
    model.selectTab(MainTab.HOME)
    model.selectTab(MainTab.CATALOG)
    assertEquals(1, repository.titleCalls)
  }

  @Test fun nextPageIsAppendedWithoutRepeatingTitles() = runTest {
    vault.stored = credential()
    repository.pages = listOf(
      TitlesPage(listOf(card(1), card(2)), total = 3, offset = 0, limit = 2),
      TitlesPage(listOf(card(2), card(3)), total = 3, offset = 2, limit = 2),
    )
    val model = model()
    model.loadCatalog().join()
    model.loadCatalog(reset = false).join()
    assertEquals(listOf(1L, 2L, 3L), model.ui.value.catalog.map { it.id })
    assertEquals(3, model.ui.value.catalogTotal)
  }

  // A TV não reproduz música nem fotos; o que o servidor mandar desses tipos não
  // pode aparecer numa grade em que tudo é abrível.
  @Test fun catalogHidesWhatTheTelevisionCannotPlay() = runTest {
    vault.stored = credential()
    repository.pages = listOf(
      TitlesPage(
        listOf(card(1), card(2, TitleKind.ALBUM), card(3, TitleKind.PHOTOS), card(4, TitleKind.TV)),
        total = 4, offset = 0, limit = 60,
      ),
    )
    val model = model()
    model.loadCatalog().join()
    assertEquals(listOf(1L, 4L), model.ui.value.catalog.map { it.id })
  }

  @Test fun homeDropsRowsThatBecomeEmptyAfterFiltering() = runTest {
    vault.stored = credential()
    repository.home = HomeResponse(
      hero = card(9, TitleKind.ALBUM),
      rows = listOf(
        HomeRow("musica", "Música", listOf(card(2, TitleKind.ALBUM))),
        HomeRow("filmes", "Filmes", listOf(card(1))),
      ),
    )
    val ui = model().ui.value
    assertNull(ui.home?.hero)
    assertEquals(listOf("filmes"), ui.home?.rows?.map { it.key })
  }

  // ---------- navegação ----------

  @Test fun backLeavesASubTabTowardsHomeAndOnlyExitsFromThere() = runTest {
    vault.stored = credential()
    val model = model()
    model.selectTab(MainTab.CATALOG)
    assertTrue(model.ui.value.screen.allowsBack())
    model.back()
    assertEquals(AppScreen.Main(MainTab.HOME), model.ui.value.screen)
    // Na Início o app não trata mais o Back: quem fecha é o sistema.
    assertTrue(!model.ui.value.screen.allowsBack())
  }

  @Test fun backFromDetailReturnsToTheTabInUse() = runTest {
    vault.stored = credential()
    val model = model()
    model.selectTab(MainTab.CATALOG)
    model.openTitle(1).join()
    assertTrue(model.ui.value.screen is AppScreen.Detail)
    model.back()
    assertEquals(AppScreen.Main(MainTab.CATALOG), model.ui.value.screen)
  }

  @Test fun closingThePlayerGoesBackToTheTabInUse() = runTest {
    vault.stored = credential()
    val model = model()
    model.selectTab(MainTab.CATALOG)
    model.playTitle(1).join()
    assertTrue(model.ui.value.screen is AppScreen.Player)
    model.closePlayer()
    assertEquals(AppScreen.Main(MainTab.CATALOG), model.ui.value.screen)
  }

  // ---------- entrada e saída ----------

  // `connectValidatesAndOffersPairing` para no que o próprio connectServer faz.
  // A conclusão do pareamento roda num job separado, cancelável pelo botão de
  // "Usuário e senha", e `ServerAddress.normalize` salta para Dispatchers.IO —
  // essa combinação não é determinística num teste, então a validação da sessão
  // é exercitada pelo login, que segue o mesmo caminho em finishAuthentication.
  @Test fun connectValidatesAndOffersPairing() = runTest {
    val model = model()
    model.connectServer("http://ozymandias.local:8787").join()
    val screen = model.ui.value.screen
    assertTrue(screen is AppScreen.Pairing)
    assertEquals("K7QP-3M2X", (screen as AppScreen.Pairing).pairing.userCode)
    assertEquals(listOf("http://ozymandias.local:8787"), model.ui.value.recentServers)
    assertTrue(!model.ui.value.loading)
  }

  @Test fun loginStoresTheSessionAndOpensTheApp() = runTest {
    val model = model()
    model.login("http://ozymandias.local:8787", " bueno ", "12345678").join()
    assertEquals(AppScreen.Main(MainTab.HOME), model.ui.value.screen)
    assertEquals("http://ozymandias.local:8787", vault.stored?.serverUrl)
    assertEquals("token", vault.stored?.token)
    assertNull(model.ui.value.error)
  }

  // Uma resposta sem token não pode derrubar o app: o require de
  // finishAuthentication já escapou do runCatching uma vez.
  @Test fun aSessionWithoutATokenIsRefusedWithoutCrashing() = runTest {
    repository.user = User(username = "bueno", token = null, expiresAt = null)
    val model = model()
    model.login("http://ozymandias.local:8787", "bueno", "12345678").join()
    assertEquals("O servidor não devolveu uma sessão válida.", model.ui.value.error)
    assertNull(vault.stored)
    assertEquals(AppScreen.Servers, model.ui.value.screen)
    assertTrue(!model.ui.value.loading)
  }

  @Test fun logoutClearsEverythingAndKeepsTheServerInTheList() = runTest {
    vault.stored = credential()
    vault.recent = listOf("http://ozymandias.local:8787")
    val model = model()
    model.logout().join()
    assertEquals(AppScreen.Servers, model.ui.value.screen)
    assertNull(model.ui.value.credential)
    assertNull(model.ui.value.home)
    assertTrue(vault.cleared)
    assertEquals(listOf("http://ozymandias.local:8787"), model.ui.value.recentServers)
    assertTrue(repository.loggedOut)
  }
}

// ---------- duplos ----------

private fun credential(expiresAt: String = "2099-01-01T00:00:00Z") =
  Credential("http://ozymandias.local:8787", "token", expiresAt, "bueno")

private fun card(id: Long, kind: TitleKind = TitleKind.MOVIE) =
  TitleCard(id = id, libraryId = 1, kind = kind, name = "Título $id")

private fun mediaFile(id: Long = 10) = MediaFile(
  id = id, relPath = "a.mp4", name = "Arquivo", ext = ".mp4", mediaType = "video",
  size = 1, duration = 100.0,
)

private class FakeVault : SessionVault {
  var stored: Credential? = null
  var recent: List<String> = emptyList()
  var cleared = false

  override suspend fun save(credential: Credential) {
    stored = credential
    rememberServer(credential.serverUrl)
  }

  override suspend fun load(): Credential? = stored
  override suspend fun clear() { stored = null; cleared = true }
  override suspend fun recentServers(): List<String> = recent
  override suspend fun rememberServer(server: String) {
    recent = (listOf(server) + recent.filterNot { it == server }).take(3)
  }
}

private class FakeRepository : MediaRepository {
  var user = User(username = "bueno", token = "token", expiresAt = "2099-01-01T00:00:00Z")
  var home = HomeResponse(hero = card(1), rows = listOf(HomeRow("recentes", "Recentes", listOf(card(1)))))
  var pages = listOf(TitlesPage(listOf(card(1)), total = 1, offset = 0, limit = 60))
  var homeError: Throwable? = null
  var titleCalls = 0
  var loggedOut = false

  override suspend fun health(server: String) = HealthResponse(status = "ok")

  override suspend fun startPairing(server: String, deviceName: String) = DeviceStartResponse(
    deviceCode = "device", userCode = "K7QP-3M2X", verificationUri = "$server/tv",
    verificationUriComplete = "$server/tv?codigo=K7QP-3M2X", expiresIn = 600, interval = 5,
  )

  // Espera, como o servidor real espera pela autorização no celular. Devolver na
  // hora fazia a tela de pareamento sumir antes da asserção, de forma intermitente.
  val pairingGate = CompletableDeferred<User>()

  override suspend fun pollPairing(server: String, deviceCode: String, interval: Int, expiresIn: Int) =
    pairingGate.await()

  override suspend fun login(server: String, username: String, password: String) = user

  override suspend fun me(credential: Credential) = user

  override suspend fun home(credential: Credential): HomeResponse {
    homeError?.let { throw it }
    return home
  }

  override suspend fun titles(credential: Credential, offset: Int, query: String, kind: TitleKind?): TitlesPage {
    val page = pages.getOrNull(titleCalls) ?: pages.last()
    titleCalls++
    return page
  }

  override suspend fun title(credential: Credential, id: Long) = TitleDetail(
    id = id, libraryId = 1, kind = TitleKind.MOVIE, name = "Título $id", library = "Filmes",
    files = listOf(mediaFile()),
  )

  override suspend fun file(credential: Credential, id: Long) = PlaybackFile(
    id = id, relPath = "a.mp4", name = "Arquivo", ext = ".mp4", mediaType = "video", size = 1,
    duration = 100.0, titleId = 1, titleName = "Título 1", kind = TitleKind.MOVIE,
  )

  override suspend fun playback(
    credential: Credential,
    file: MediaFile,
    title: String,
    audioTrack: Int?,
    onPreparation: (PreparationProgress) -> Unit,
  ) = PlaybackSource("http://ozymandias.local:8787/stream/10?t=abc", file, title, MediaTracks(), null)

  override suspend fun saveProgress(credential: Credential, fileId: Long, position: Double, duration: Double) = Unit

  override suspend fun logout(credential: Credential) { loggedOut = true }
}
