package com.buenno.ozymandias.firetv.data

import kotlinx.coroutines.delay

class OzymandiasRepository(private val capabilities: PlaybackCapabilities) {
  suspend fun health(server: String): HealthResponse = ApiClient(server).get("/healthz")

  suspend fun startPairing(server: String, deviceName: String): DeviceStartResponse =
    ApiClient(server).post("/api/auth/device/start", DeviceStartRequest(deviceName, "firetv", "0.1.0"))

  suspend fun pollPairing(server: String, deviceCode: String, interval: Int): User {
    val api = ApiClient(server)
    while (true) {
      delay(interval.coerceAtLeast(2) * 1_000L)
      api.pollDeviceToken(deviceCode)?.let { return it }
    }
  }

  suspend fun login(server: String, username: String, password: String): User = ApiClient(server).post(
    "/api/auth/login",
    LoginRequest(username, password, remember = true, tokenInResponse = true),
  )

  suspend fun me(credential: Credential): User = ApiClient(credential.serverUrl).get("/api/auth/me", credential.token)
  suspend fun home(credential: Credential): HomeResponse = ApiClient(credential.serverUrl).get("/api/home", credential.token)
  suspend fun libraries(credential: Credential): List<Library> = ApiClient(credential.serverUrl).get("/api/libraries", credential.token)
  suspend fun titles(credential: Credential, offset: Int = 0, query: String = ""): TitlesPage {
    val path = "/api/titles?sort=recent&limit=60&offset=$offset" +
      if (query.isBlank()) "" else "&q=${ApiClient.encoded(query)}"
    return ApiClient(credential.serverUrl).get(path, credential.token)
  }
  suspend fun title(credential: Credential, id: Long): TitleDetail = ApiClient(credential.serverUrl).get("/api/titles/$id", credential.token)
  suspend fun file(credential: Credential, id: Long): PlaybackFile = ApiClient(credential.serverUrl).get("/api/files/$id", credential.token)

  suspend fun playback(
    credential: Credential,
    file: MediaFile,
    title: String,
    audioTrack: Int? = null,
    onPreparation: (PreparationProgress) -> Unit = {},
  ): PlaybackSource {
    val api = ApiClient(credential.serverUrl)
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

  suspend fun saveProgress(credential: Credential, fileId: Long, position: Double, duration: Double) {
    ApiClient(credential.serverUrl).put("/api/progress/$fileId", ProgressRequest(position, duration), credential.token)
  }

  suspend fun logout(credential: Credential) {
    runCatching { ApiClient(credential.serverUrl).postEmpty<Map<String, Boolean>>("/api/auth/logout", credential.token) }
  }

  private fun authorizeMediaUrl(api: ApiClient, path: String, token: MediaToken): String {
    val resolved = api.resolve(path)
    val separator = if (java.net.URI(resolved).query.isNullOrBlank()) "?" else "&"
    return resolved + separator + ApiClient.encoded(token.parameter) + "=" + ApiClient.encoded(token.token)
  }
}
