package com.buenno.ozymandias.firetv

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.buenno.ozymandias.firetv.data.ApiException
import com.buenno.ozymandias.firetv.data.Credential
import com.buenno.ozymandias.firetv.data.CredentialVault
import com.buenno.ozymandias.firetv.data.DeviceStartResponse
import com.buenno.ozymandias.firetv.data.HomeResponse
import com.buenno.ozymandias.firetv.data.MediaFile
import com.buenno.ozymandias.firetv.data.OzymandiasRepository
import com.buenno.ozymandias.firetv.data.PlaybackSource
import com.buenno.ozymandias.firetv.data.PreparationProgress
import com.buenno.ozymandias.firetv.data.ServerAddress
import com.buenno.ozymandias.firetv.data.ServerCandidate
import com.buenno.ozymandias.firetv.data.ServerDiscovery
import com.buenno.ozymandias.firetv.data.TitleCard
import com.buenno.ozymandias.firetv.data.TitleDetail
import com.buenno.ozymandias.firetv.data.TitleKind
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class MainTab { HOME, CATALOG, ACCOUNT }

sealed interface AppScreen {
  data object Restoring : AppScreen
  data object Servers : AppScreen
  data class Pairing(val server: String, val pairing: DeviceStartResponse) : AppScreen
  data class Login(val server: String) : AppScreen
  data class Main(val tab: MainTab = MainTab.HOME) : AppScreen
  data class Detail(val title: TitleDetail) : AppScreen
  data class Player(val source: PlaybackSource) : AppScreen
}

data class AppUiState(
  val screen: AppScreen = AppScreen.Restoring,
  val credential: Credential? = null,
  val home: HomeResponse? = null,
  val catalog: List<TitleCard> = emptyList(),
  val catalogTotal: Int = 0,
  val recentServers: List<String> = emptyList(),
  val loading: Boolean = false,
  val preparation: PreparationProgress? = null,
  val error: String? = null,
)

class AppViewModel(
  private val repository: OzymandiasRepository,
  private val vault: CredentialVault,
  discovery: ServerDiscovery,
) : ViewModel() {
  private val _ui = MutableStateFlow(AppUiState())
  val ui: StateFlow<AppUiState> = _ui.asStateFlow()
  val discoveredServers: StateFlow<List<ServerCandidate>> = discovery.servers()
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
  private var pairingJob: Job? = null

  init { restore() }

  fun restore() = viewModelScope.launch {
    val recent = vault.recentServers()
    _ui.value = _ui.value.copy(recentServers = recent, error = null)
    val credential = vault.load()
    if (credential == null || credential.isExpired()) {
      if (credential != null) vault.clear()
      _ui.value = _ui.value.copy(screen = AppScreen.Servers)
      return@launch
    }
    runCatching { repository.me(credential) }
      .onSuccess {
        _ui.value = _ui.value.copy(credential = credential, screen = AppScreen.Main(), error = null)
        loadHome()
      }
      .onFailure { error ->
        if (error is ApiException && error.status == 401) vault.clear()
        _ui.value = _ui.value.copy(screen = AppScreen.Servers, error = error.message)
      }
  }

  fun connectServer(input: String) = viewModelScope.launch {
    busy()
    try {
      val server = ServerAddress.normalize(input)
      val health = repository.health(server)
      require(health.status == "ok") { "O servidor ainda não está pronto." }
      vault.rememberServer(server)
      val pairing = repository.startPairing(server, "${Build.MANUFACTURER} ${Build.MODEL}")
      _ui.value = _ui.value.copy(
        screen = AppScreen.Pairing(server, pairing),
        recentServers = vault.recentServers(), loading = false, error = null,
      )
      pollPairing(server, pairing)
    } catch (error: Exception) {
      _ui.value = _ui.value.copy(loading = false, error = error.message)
    }
  }

  fun showManualLogin(server: String) {
    pairingJob?.cancel()
    _ui.value = _ui.value.copy(screen = AppScreen.Login(server), error = null)
  }

  fun restartPairing(server: String) = connectServer(server)

  private fun pollPairing(server: String, pairing: DeviceStartResponse) {
    pairingJob?.cancel()
    pairingJob = viewModelScope.launch {
      runCatching { repository.pollPairing(server, pairing.deviceCode, pairing.interval) }
        .onSuccess { user -> finishAuthentication(server, user.token, user.expiresAt, user.username) }
        .onFailure { _ui.value = _ui.value.copy(error = it.message) }
    }
  }

  fun login(server: String, username: String, password: String) = viewModelScope.launch {
    busy()
    runCatching { repository.login(server, username.trim(), password) }
      .onSuccess { finishAuthentication(server, it.token, it.expiresAt, it.username) }
      .onFailure { _ui.value = _ui.value.copy(loading = false, error = it.message) }
  }

  private suspend fun finishAuthentication(server: String, token: String?, expiresAt: String?, username: String) {
    require(!token.isNullOrBlank() && !expiresAt.isNullOrBlank()) { "O servidor não devolveu uma sessão válida." }
    val credential = Credential(server, token, expiresAt, username)
    vault.save(credential)
    _ui.value = _ui.value.copy(credential = credential, screen = AppScreen.Main(), loading = false, error = null)
    loadHome()
  }

  fun selectTab(tab: MainTab) {
    _ui.value = _ui.value.copy(screen = AppScreen.Main(tab), error = null)
    if (tab == MainTab.CATALOG && _ui.value.catalog.isEmpty()) loadCatalog()
  }

  fun loadHome() = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    runCatching { repository.home(credential) }
      .onSuccess { home ->
        val filtered = home.copy(
          hero = home.hero?.takeIf { it.kind == TitleKind.MOVIE || it.kind == TitleKind.TV },
          continueItems = home.continueItems.filter { it.kind == TitleKind.MOVIE || it.kind == TitleKind.TV },
          rows = home.rows.map { row -> row.copy(items = row.items.filter { it.kind == TitleKind.MOVIE || it.kind == TitleKind.TV }) }.filter { it.items.isNotEmpty() },
        )
        _ui.value = _ui.value.copy(home = filtered, error = null)
      }
      .onFailure {
        if (!invalidateSession(it) && _ui.value.home == null) _ui.value = _ui.value.copy(error = it.message)
      }
  }

  fun loadCatalog(query: String = "", reset: Boolean = true) = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    val offset = if (reset) 0 else _ui.value.catalog.size
    _ui.value = _ui.value.copy(loading = true, error = null)
    runCatching { repository.titles(credential, offset, query) }
      .onSuccess { page ->
        val items = page.items.filter { it.kind == TitleKind.MOVIE || it.kind == TitleKind.TV }
        _ui.value = _ui.value.copy(
          catalog = if (reset) items else (_ui.value.catalog + items).distinctBy { it.id },
          catalogTotal = page.total, loading = false,
        )
      }
      .onFailure {
        if (!invalidateSession(it)) _ui.value = _ui.value.copy(loading = false, error = it.message)
      }
  }

  fun openTitle(id: Long) = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    busy()
    runCatching { repository.title(credential, id) }
      .onSuccess { _ui.value = _ui.value.copy(screen = AppScreen.Detail(it), loading = false, error = null) }
      .onFailure {
        if (!invalidateSession(it)) _ui.value = _ui.value.copy(loading = false, error = it.message)
      }
  }

  fun play(title: TitleDetail, file: MediaFile? = null) = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    val selectedFile = file ?: title.preferredFile() ?: return@launch
    _ui.value = _ui.value.copy(loading = true, preparation = null, error = null)
    runCatching { repository.playback(credential, selectedFile, title.name) { progress -> _ui.value = _ui.value.copy(preparation = progress) } }
      .onSuccess { _ui.value = _ui.value.copy(screen = AppScreen.Player(it), loading = false, preparation = null) }
      .onFailure {
        if (!invalidateSession(it)) _ui.value = _ui.value.copy(loading = false, preparation = null, error = it.message)
      }
  }

  fun changeAudio(source: PlaybackSource, track: Int) = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    _ui.value = _ui.value.copy(loading = true, preparation = null, error = null)
    runCatching { repository.playback(credential, source.file, source.title, track) { progress -> _ui.value = _ui.value.copy(preparation = progress) } }
      .onSuccess { _ui.value = _ui.value.copy(screen = AppScreen.Player(it), loading = false, preparation = null) }
      .onFailure {
        if (!invalidateSession(it)) _ui.value = _ui.value.copy(loading = false, preparation = null, error = it.message)
      }
  }

  fun playNext(source: PlaybackSource) = viewModelScope.launch {
    val nextId = source.nextFileId ?: return@launch
    val credential = _ui.value.credential ?: return@launch
    _ui.value = _ui.value.copy(loading = true, preparation = null, error = null)
    runCatching {
      val next = repository.file(credential, nextId)
      repository.playback(credential, next.mediaFile(), next.titleName) { progress -> _ui.value = _ui.value.copy(preparation = progress) }
    }.onSuccess {
      _ui.value = _ui.value.copy(screen = AppScreen.Player(it), loading = false, preparation = null)
    }.onFailure {
      if (!invalidateSession(it)) _ui.value = _ui.value.copy(loading = false, preparation = null, error = it.message)
    }
  }

  fun saveProgress(fileId: Long, position: Double, duration: Double) = viewModelScope.launch {
    val credential = _ui.value.credential ?: return@launch
    runCatching { repository.saveProgress(credential, fileId, position, duration) }
  }

  fun closePlayer() {
    val source = (_ui.value.screen as? AppScreen.Player)?.source
    _ui.value = _ui.value.copy(screen = AppScreen.Main(), error = null)
    if (source != null) loadHome()
  }

  fun back() {
    _ui.value = when (_ui.value.screen) {
      is AppScreen.Detail -> _ui.value.copy(screen = AppScreen.Main())
      is AppScreen.Login, is AppScreen.Pairing -> _ui.value.copy(screen = AppScreen.Servers, error = null)
      else -> _ui.value
    }
  }

  fun logout() = viewModelScope.launch {
    pairingJob?.cancel()
    val credential = _ui.value.credential
    vault.clear()
    _ui.value = AppUiState(screen = AppScreen.Servers, recentServers = vault.recentServers())
    credential?.let { repository.logout(it) }
  }

  private suspend fun invalidateSession(error: Throwable): Boolean {
    if (error !is ApiException || error.status != 401) return false
    vault.clear()
    _ui.value = AppUiState(
      screen = AppScreen.Servers,
      recentServers = vault.recentServers(),
      error = "Sua sessão expirou. Conecte-se novamente.",
    )
    return true
  }

  private fun busy() { _ui.value = _ui.value.copy(loading = true, error = null) }

  class Factory(private val app: OzymandiasApplication) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T =
      AppViewModel(app.repository, app.vault, app.discovery) as T
  }
}
