package com.buenno.ozymandias.firetv.data

// As duas dependências do AppViewModel viram contratos para que a máquina de
// estados do app possa ser exercitada sem rede, sem Keystore e sem Android.
interface MediaRepository {
  suspend fun health(server: String): HealthResponse
  suspend fun startPairing(server: String, deviceName: String): DeviceStartResponse
  suspend fun pollPairing(server: String, deviceCode: String, interval: Int, expiresIn: Int): User
  suspend fun login(server: String, username: String, password: String): User
  suspend fun me(credential: Credential): User
  suspend fun home(credential: Credential): HomeResponse
  suspend fun titles(
    credential: Credential,
    offset: Int = 0,
    query: String = "",
    kind: TitleKind? = null,
  ): TitlesPage
  suspend fun title(credential: Credential, id: Long): TitleDetail
  suspend fun file(credential: Credential, id: Long): PlaybackFile
  suspend fun playback(
    credential: Credential,
    file: MediaFile,
    title: String,
    audioTrack: Int? = null,
    onPreparation: (PreparationProgress) -> Unit = {},
  ): PlaybackSource
  suspend fun saveProgress(credential: Credential, fileId: Long, position: Double, duration: Double)
  suspend fun logout(credential: Credential)
}

interface SessionVault {
  suspend fun save(credential: Credential)
  suspend fun load(): Credential?
  suspend fun clear()
  suspend fun recentServers(): List<String>
  suspend fun rememberServer(server: String)
}
