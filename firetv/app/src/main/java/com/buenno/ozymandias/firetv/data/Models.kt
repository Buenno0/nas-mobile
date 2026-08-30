package com.buenno.ozymandias.firetv.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class HealthResponse(
  val status: String,
  val time: String = "",
  @SerialName("api_version") val apiVersion: Int = 1,
  val features: List<String> = emptyList(),
)

@Serializable data class ErrorResponse(val error: String)
@Serializable data class DeviceStartRequest(@SerialName("device_name") val deviceName: String, val client: String, val version: String)
@Serializable data class DeviceCodeRequest(@SerialName("device_code") val deviceCode: String)
@Serializable data class LoginRequest(val username: String, val password: String, val remember: Boolean, @SerialName("token_na_resposta") val tokenInResponse: Boolean)

@Serializable
data class User(
  val username: String,
  @SerialName("must_change_password") val mustChangePassword: Boolean = false,
  @SerialName("is_admin") val isAdmin: Boolean = false,
  val token: String? = null,
  @SerialName("expira_em") val expiresAt: String? = null,
)

@Serializable
data class Credential(val serverUrl: String, val token: String, val expiresAt: String, val username: String) {
  fun isExpired(nowEpochMillis: Long = System.currentTimeMillis()): Boolean =
    runCatching { java.time.Instant.parse(expiresAt).toEpochMilli() <= nowEpochMillis }.getOrDefault(true)
}

@Serializable
data class DeviceStartResponse(
  @SerialName("device_code") val deviceCode: String,
  @SerialName("user_code") val userCode: String,
  @SerialName("verification_uri") val verificationUri: String,
  @SerialName("verification_uri_complete") val verificationUriComplete: String,
  @SerialName("expires_in") val expiresIn: Int,
  val interval: Int,
)

@Serializable data class DevicePending(val status: String, val interval: Int = 2)

@Serializable
enum class TitleKind { @SerialName("movie") MOVIE, @SerialName("tv") TV, @SerialName("album") ALBUM, @SerialName("photos") PHOTOS }

@Serializable
data class TitleCard(
  val id: Long,
  @SerialName("library_id") val libraryId: Long,
  val kind: TitleKind,
  val name: String,
  val year: Int? = null,
  val rating: Double? = null,
  val poster: String? = null,
  val backdrop: String? = null,
  val genres: String? = null,
  val files: Int = 0,
  val duration: Double? = null,
  @SerialName("meta_state") val metaState: String = "",
)

@Serializable
data class ContinueItem(
  @SerialName("file_id") val fileId: Long,
  @SerialName("title_id") val titleId: Long,
  @SerialName("title_name") val titleName: String,
  val kind: TitleKind,
  val label: String? = null,
  val poster: String? = null,
  val backdrop: String? = null,
  val position: Double,
  val duration: Double,
)

@Serializable data class HomeRow(val key: String, val title: String, val items: List<TitleCard>)

@Serializable
data class HomeResponse(
  val hero: TitleCard? = null,
  @SerialName("continue") val continueItems: List<ContinueItem> = emptyList(),
  val rows: List<HomeRow> = emptyList(),
)

@Serializable data class Library(val id: Long, val name: String, val kind: String, val enabled: Boolean)

@Serializable
data class TitlesPage(val items: List<TitleCard>, val total: Int, val offset: Int, val limit: Int)

@Serializable
data class MediaFile(
  val id: Long,
  @SerialName("rel_path") val relPath: String,
  val name: String,
  val ext: String,
  @SerialName("media_type") val mediaType: String,
  val size: Long,
  val duration: Double,
  val width: Int? = null,
  val height: Int? = null,
  @SerialName("vcodec") val videoCodec: String? = null,
  @SerialName("acodec") val audioCodec: String? = null,
  val position: Double? = null,
  val finished: Boolean? = null,
  val season: Int? = null,
  val episode: Int? = null,
  @SerialName("episode_name") val episodeName: String? = null,
)

@Serializable
data class PlaybackFile(
  val id: Long,
  @SerialName("rel_path") val relPath: String,
  val name: String,
  val ext: String,
  @SerialName("media_type") val mediaType: String,
  val size: Long,
  val duration: Double,
  val width: Int? = null,
  val height: Int? = null,
  @SerialName("vcodec") val videoCodec: String? = null,
  @SerialName("acodec") val audioCodec: String? = null,
  val position: Double? = null,
  val finished: Boolean? = null,
  val season: Int? = null,
  val episode: Int? = null,
  @SerialName("episode_name") val episodeName: String? = null,
  @SerialName("title_id") val titleId: Long,
  @SerialName("title_name") val titleName: String,
  val kind: TitleKind,
) {
  fun mediaFile() = MediaFile(
    id, relPath, name, ext, mediaType, size, duration, width, height, videoCodec, audioCodec,
    position, finished, season, episode, episodeName,
  )
}

@Serializable data class Season(val number: Int, val episodes: List<MediaFile>)

@Serializable
data class TitleDetail(
  val id: Long,
  @SerialName("library_id") val libraryId: Long,
  val kind: TitleKind,
  val name: String,
  val year: Int? = null,
  val overview: String? = null,
  val rating: Double? = null,
  val genres: String? = null,
  @SerialName("poster_url") val posterUrl: String? = null,
  @SerialName("backdrop_url") val backdropUrl: String? = null,
  val library: String,
  val favorite: Boolean = false,
  val files: List<MediaFile> = emptyList(),
  val seasons: List<Season>? = null,
) {
  fun preferredFile(): MediaFile? {
    val playable = files.filter { it.mediaType != "photo" }
    return playable.firstOrNull { (it.position ?: 0.0) > 0 && it.finished != true }
      ?: playable.firstOrNull { it.finished != true }
      ?: playable.firstOrNull()
  }
}

@Serializable
data class MediaToken(
  val token: String,
  @SerialName("expira_em") val expiresAt: String,
  @SerialName("valido_por") val validFor: Int,
  @SerialName("param") val parameter: String,
)

@Serializable
data class PlaybackPlan(
  @SerialName("modo") val mode: String,
  @SerialName("motivo") val reason: String,
  val url: String = "",
  @SerialName("url_direta") val directUrl: String,
  @SerialName("preparo") val preparation: PreparationProgress? = null,
  val ffmpeg: Boolean,
  @SerialName("transcodificacao_ativa") val transcodingEnabled: Boolean,
)

@Serializable
data class PreparationProgress(
  @SerialName("estado") val state: String,
  @SerialName("percentual") val percentage: Int = 0,
  @SerialName("restante_segundos") val remainingSeconds: Int = 0,
  @SerialName("erro") val error: String? = null,
)

@Serializable
data class MediaTrack(
  val idx: Int,
  val codec: String? = null,
  val lang: String? = null,
  @SerialName("rotulo") val label: String,
  @SerialName("padrao") val isDefault: Boolean = false,
  @SerialName("forcada") val forced: Boolean = false,
  val url: String? = null,
  @SerialName("indisponivel") val unavailable: String? = null,
)

@Serializable data class MediaTracks(val audio: List<MediaTrack> = emptyList(), @SerialName("legendas") val subtitles: List<MediaTrack> = emptyList())
@Serializable data class NextEpisode(@SerialName("next") val nextFileId: Long? = null)
@Serializable data class ProgressRequest(val position: Double, val duration: Double)

data class PlaybackSource(
  val url: String,
  val file: MediaFile,
  val title: String,
  val tracks: MediaTracks,
  val nextFileId: Long?,
)

data class ServerCandidate(val name: String, val url: String)
