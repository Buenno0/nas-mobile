package com.buenno.ozymandias.firetv.ui

import android.net.Uri
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerView
import com.buenno.ozymandias.firetv.data.PlaybackSource
import kotlinx.coroutines.delay

private data class PlayerRuntime(val player: ExoPlayer, val session: MediaSession)

@androidx.annotation.OptIn(UnstableApi::class)
@Composable
fun TvPlayerScreen(
  source: PlaybackSource,
  saveProgress: (Long, Double, Double) -> Unit,
  changeAudio: (PlaybackSource, Int) -> Unit,
  playNext: (PlaybackSource) -> Unit,
  close: () -> Unit,
) {
  val context = LocalContext.current
  val lifecycleOwner = LocalLifecycleOwner.current
  val rootView = LocalView.current
  var runtime by remember(source.url) { mutableStateOf<PlayerRuntime?>(null) }
  var resumeAtMs by remember(source.url) { mutableLongStateOf(((source.file.position ?: 0.0) * 1_000).toLong()) }
  var positionMs by remember(source.url) { mutableLongStateOf(resumeAtMs) }
  var durationMs by remember(source.url) { mutableLongStateOf((source.file.duration * 1_000).toLong()) }
  var isPlaying by remember { mutableStateOf(true) }
  var controlsVisible by remember { mutableStateOf(true) }
  var interactionTick by remember { mutableIntStateOf(0) }
  var error by remember { mutableStateOf<String?>(null) }
  var audioIndex by remember { mutableIntStateOf(source.tracks.audio.indexOfFirst { it.isDefault }.coerceAtLeast(0)) }
  var subtitleIndex by remember { mutableIntStateOf(-1) }
  var speedIndex by remember { mutableIntStateOf(1) }
  val speeds = remember { listOf(.75f, 1f, 1.25f, 1.5f, 2f) }
  val primaryFocus = remember { FocusRequester() }
  val playerFocus = remember { FocusRequester() }

  fun persist(player: Player?) {
    val position = player?.currentPosition ?: positionMs
    val duration = (player?.duration ?: durationMs).takeIf { it > 0 && it != C.TIME_UNSET } ?: durationMs
    resumeAtMs = position.coerceAtLeast(0)
    positionMs = resumeAtMs
    durationMs = duration
    saveProgress(source.file.id, position / 1_000.0, duration / 1_000.0)
  }

  fun release(save: Boolean) {
    runtime?.let {
      if (save) persist(it.player)
      it.session.release()
      it.player.release()
    }
    runtime = null
  }

  fun buildPlayer(): PlayerRuntime {
    val player = ExoPlayer.Builder(context).build()
    val subtitles = source.tracks.subtitles.mapNotNull { track ->
      val url = track.url ?: return@mapNotNull null
      MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
        .setMimeType(MimeTypes.TEXT_VTT)
        .setLanguage(track.lang)
        .setLabel(track.label)
        .setSelectionFlags(if (track.isDefault) C.SELECTION_FLAG_DEFAULT else 0)
        .build()
    }
    val mediaItem = MediaItem.Builder()
      .setUri(source.url)
      .setMediaId(source.file.id.toString())
      .setMediaMetadata(androidx.media3.common.MediaMetadata.Builder().setTitle(source.title).build())
      .setSubtitleConfigurations(subtitles)
      .build()
    player.setMediaItem(mediaItem, resumeAtMs)
    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
      .setPreferredAudioLanguage(source.tracks.audio.getOrNull(audioIndex)?.lang)
      .setPreferredTextLanguage(null)
      .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
      .build()
    player.addListener(object : Player.Listener {
      override fun onIsPlayingChanged(value: Boolean) { isPlaying = value }
      override fun onPlayerError(playbackError: PlaybackException) {
        error = playbackError.localizedMessage ?: "Não foi possível reproduzir este arquivo."
      }
      override fun onPlaybackStateChanged(state: Int) {
        if (state == Player.STATE_ENDED) persist(player)
      }
    })
    player.prepare()
    player.playWhenReady = true
    return PlayerRuntime(player, MediaSession.Builder(context, player).build())
  }

  DisposableEffect(source.url, lifecycleOwner) {
    rootView.keepScreenOn = true
    runtime = buildPlayer()
    val observer = LifecycleEventObserver { _, event ->
      when (event) {
        Lifecycle.Event.ON_PAUSE -> runtime?.player?.let(::persist)
        Lifecycle.Event.ON_STOP -> release(save = true)
        Lifecycle.Event.ON_START -> if (runtime == null) runtime = buildPlayer()
        else -> Unit
      }
    }
    lifecycleOwner.lifecycle.addObserver(observer)
    onDispose {
      lifecycleOwner.lifecycle.removeObserver(observer)
      release(save = true)
      rootView.keepScreenOn = false
    }
  }

  LaunchedEffect(runtime) {
    var ticks = 0
    while (runtime != null) {
      delay(1_000)
      runtime?.player?.let { player ->
        positionMs = player.currentPosition.coerceAtLeast(0)
        player.duration.takeIf { it > 0 && it != C.TIME_UNSET }?.let { durationMs = it }
        ticks++
        if (ticks % 10 == 0) persist(player)
      }
    }
  }

  LaunchedEffect(controlsVisible, interactionTick) {
    if (controlsVisible) primaryFocus.requestFocus() else playerFocus.requestFocus()
  }

  LaunchedEffect(controlsVisible, isPlaying, interactionTick) {
    if (controlsVisible && isPlaying) {
      delay(4_000)
      controlsVisible = false
    }
  }

  BackHandler {
    if (controlsVisible) {
      controlsVisible = false
    } else {
      release(save = true)
      close()
    }
  }

  Box(
    // O único preto puro do app: as barras do vídeo precisam de preto real,
    // não do sépia do tema, senão a moldura brilha ao redor da imagem.
    Modifier.fillMaxSize().background(Color.Black)
      .focusRequester(playerFocus).focusable()
      .onPreviewKeyEvent { event ->
        if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        // Let BackHandler distinguish “hide controls” from “leave player”.
        if (event.key == Key.Back) return@onPreviewKeyEvent false
        interactionTick++
        if (!controlsVisible) {
          controlsVisible = true
          true
        } else {
          false
        }
      }
      .clickable {
        interactionTick++
        controlsVisible = !controlsVisible
      },
  ) {
    runtime?.player?.let { player ->
      AndroidView(
        factory = { viewContext ->
          PlayerView(viewContext).apply {
            useController = false
            this.player = player
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
          }
        },
        update = { it.player = player },
        modifier = Modifier.fillMaxSize(),
      )
    }

    if (controlsVisible) {
      Column(
        Modifier.align(Alignment.BottomCenter).fillMaxWidth()
          .background(
            Brush.verticalGradient(
              listOf(Color.Transparent, Background.copy(alpha = .62f), Background.copy(alpha = .96f))
            )
          )
          .padding(horizontal = OzyTvTokens.gutter, vertical = 30.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        Text(source.title, color = Ink, style = OzyType.title, maxLines = 1)
        Spacer(Modifier.height(6.dp))
        // Barra de posiÃ§Ã£o, nÃ£o controle: quem navega o filme sÃ£o os botÃµes de
        // Â±10 s. Por isso a cabeÃ§a nÃ£o usa o halo Ã¢mbar, que em todo o resto do
        // app significa "isto estÃ¡ com o foco".
        val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Ink.copy(alpha = .18f))) {
          Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().clip(CircleShape).background(Accent))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
          Text(clock(positionMs), color = Muted, style = OzyType.caption)
          Text("−${clock((durationMs - positionMs).coerceAtLeast(0))}", color = Muted, style = OzyType.caption)
        }
        Row(
          Modifier.fillMaxWidth().padding(top = 8.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
          OzySecondaryAction("−10 s") { runtime?.player?.seekBack() }
          OzyPrimaryAction(
            if (isPlaying) "Pausar" else "Reproduzir",
            if (isPlaying) OzyGlyph.PAUSE else OzyGlyph.PLAY,
            Modifier.focusRequester(primaryFocus),
          ) { runtime?.player?.let { if (it.isPlaying) it.pause() else it.play() } }
          OzySecondaryAction("+10 s") { runtime?.player?.seekForward() }
          Spacer(Modifier.weight(1f))
          if (source.tracks.audio.isNotEmpty()) {
            OzySecondaryAction("Áudio: ${source.tracks.audio.getOrNull(audioIndex)?.label ?: "Padrão"}") {
              audioIndex = (audioIndex + 1) % source.tracks.audio.size
              persist(runtime?.player)
              changeAudio(source, source.tracks.audio[audioIndex].idx)
            }
          }
          if (source.tracks.subtitles.isNotEmpty()) {
            val label = if (subtitleIndex < 0) "Desligada" else source.tracks.subtitles[subtitleIndex].label
            OzySecondaryAction("Legenda: $label") {
              subtitleIndex = if (subtitleIndex + 1 >= source.tracks.subtitles.size) -1 else subtitleIndex + 1
              runtime?.player?.let { player ->
                player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                  .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, subtitleIndex < 0)
                  .setPreferredTextLanguage(source.tracks.subtitles.getOrNull(subtitleIndex)?.lang)
                  .build()
              }
            }
          }
          OzySecondaryAction("${speeds[speedIndex]}×") {
            speedIndex = (speedIndex + 1) % speeds.size
            runtime?.player?.setPlaybackSpeed(speeds[speedIndex])
          }
          if (source.nextFileId != null) OzySecondaryAction("Próximo episódio") {
            persist(runtime?.player)
            playNext(source)
          }
        }
        error?.let { Text(it, color = Danger, style = OzyType.caption) }
      }
    }
  }
}

private fun clock(milliseconds: Long): String {
  val total = (milliseconds / 1_000).coerceAtLeast(0)
  val hours = total / 3_600
  val minutes = (total % 3_600) / 60
  val seconds = total % 60
  return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%02d:%02d".format(minutes, seconds)
}
