package com.buenno.ozymandias.firetv.data

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.delay

class OzymandiasRepository(private val capabilities: PlaybackCapabilities) : MediaRepository {
  private val clients = ConcurrentHashMap<String, ApiClient>()

  private fun clientFor(server: String): ApiClient = clients.getOrPut(server) { ApiClient(server) }

  override suspend fun health(server: String): HealthResponse = clientFor(server).get("/healthz")

  override suspend fun startPairing(server: String, deviceName: String): DeviceStartResponse =
    clientFor(server).post("/api/auth/device/start", DeviceStartRequest(deviceName, "firetv", "0.1.0"))

  // O código de pareamento vence no servidor. Sem um prazo aqui, a TV ficaria
  // exibindo um QR morto e consultando a rede para sempre; ao estourar, a tela
  // oferece gerar um código novo.
  override suspend fun pollPairing(server: String, deviceCode: String, interval: Int, expiresIn: Int): User {
    val api = clientFor(server)
    val step = interval.coerceAtLeast(MINIMUM_POLL_SECONDS)
    val window = expiresIn.coerceIn(MINIMUM_PAIRING_SECONDS, MAXIMUM_PAIRING_SECONDS)
    repeat((window / step).coerceAtLeast(1)) {
      delay(step * 1_000L)
      api.pollDeviceToken(deviceCode)?.let { return it }
    }
    throw ApiException(408, PAIRING_EXPIRED)
  }

  override suspend fun login(server: String, username: String, password: String): User = clientFor(server).post(
    "/api/auth/login",
    LoginRequest(username, password, remember = true, tokenInResponse = true),
  )

  override suspend fun me(credential: Credential): User = clientFor(credential.serverUrl).get("/api/auth/me", credential.token)
  override suspend fun home(credential: Credential): HomeResponse = clientFor(credential.serverUrl).get("/api/home", credential.token)
  suspend fun libraries(credential: Credential): List<Library> = clientFor(credential.serverUrl).get("/api/libraries", credential.token)
  override suspend fun titles(credential: Credential, offset: Int, query: String, kind: TitleKind?): TitlesPage {
    val path = "/api/titles?sort=recent&limit=60&offset=$offset" +
      (if (query.isBlank()) "" else "&q=${ApiClient.encoded(query)}") +
      (kind?.let { "&kind=${if (it == TitleKind.MOVIE) "movie" else "tv"}" } ?: "")
    return clientFor(credential.serverUrl).get(path, credential.token)
  }
  override suspend fun title(credential: Credential, id: Long): TitleDetail = clientFor(credential.serverUrl).get("/api/titles/$id", credential.token)
  override suspend fun file(credential: Credential, id: Long): PlaybackFile = clientFor(credential.serverUrl).get("/api/files/$id", credential.token)

  override suspend fun playback(
    credential: Credential,
    file: MediaFile,
    title: String,
    audioTrack: Int?,
    onPreparation: (PreparationProgress) -> Unit,
  ): PlaybackSource {
    val api = clientFor(credential.serverUrl)
    val query = capabilities.query(audioTrack)
    val mediaToken: MediaToken = api.postEmpty("/api/auth/media-token", credential.token)
    var plan: PlaybackPlan = api.get("/api/files/${file.id}/playback?$query", credential.token)
    if (plan.mode != "direct" && plan.url.isBlank()) {
      if (!plan.ffmpeg || !plan.transcodingEnabled) throw ApiException(415, plan.reason)
      api.postEmpty<PreparationProgress>("/api/files/${file.id}/prepare?$query", credential.token)
      while (plan.url.isBlank()) {
        delay(1_000)
        plan = api.get("/api/files/${file.id}/playback?$query", credential.token)
        plan.preparation?.let(onPreparation)
        if (plan.preparation?.state == "erro") throw ApiException(500, plan.preparation.error ?: plan.reason)
      }
    }
    val uri = java.net.URI(api.resolve(plan.url))
    val separator = if (uri.query.isNullOrBlank()) "?" else "&"
    val authorized = uri.toString() + separator + ApiClient.encoded(mediaToken.parameter) + "=" + ApiClient.encoded(mediaToken.token)
    val tracks = runCatching { api.get<MediaTracks>("/api/files/${file.id}/faixas", credential.token) }.getOrDefault(MediaTracks())
    val authorizedTracks = tracks.copy(
      subtitles = tracks.subtitles.map { track ->
        track.copy(url = track.url?.let { authorizeMediaUrl(api, it, mediaToken) })
      },
    )
    val next = runCatching { api.get<NextEpisode>("/api/files/${file.id}/next", credential.token).nextFileId }.getOrNull()
    return PlaybackSource(authorized, file, title, authorizedTracks, next)
  }

  override suspend fun saveProgress(credential: Credential, fileId: Long, position: Double, duration: Double) {
    clientFor(credential.serverUrl).put("/api/progress/$fileId", ProgressRequest(position, duration), credential.token)
  }

  override suspend fun logout(credential: Credential) {
    runCatching { clientFor(credential.serverUrl).postEmpty<Map<String, Boolean>>("/api/auth/logout", credential.token) }
  }

  private fun authorizeMediaUrl(api: ApiClient, path: String, token: MediaToken): String {
    val resolved = api.resolve(path)
    val separator = if (java.net.URI(resolved).query.isNullOrBlank()) "?" else "&"
    return resolved + separator + ApiClient.encoded(token.parameter) + "=" + ApiClient.encoded(token.token)
  }

  companion object {
    private const val MINIMUM_POLL_SECONDS = 2
    private const val MINIMUM_PAIRING_SECONDS = 60
    private const val MAXIMUM_PAIRING_SECONDS = 30 * 60
    internal const val PAIRING_EXPIRED =
      "O código da TV expirou antes da autorização. Gere um novo código."
  }
}
