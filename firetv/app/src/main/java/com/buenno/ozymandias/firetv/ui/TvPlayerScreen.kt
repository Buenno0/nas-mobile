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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
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
  var error by remember { mutableStateOf<String?>(null) }
  var audioIndex by remember { mutableIntStateOf(source.tracks.audio.indexOfFirst { it.isDefault }.coerceAtLeast(0)) }
  var subtitleIndex by remember { mutableIntStateOf(-1) }
  var speedIndex by remember { mutableIntStateOf(1) }
  val speeds = remember { listOf(.75f, 1f, 1.25f, 1.5f, 2f) }
  val primaryFocus = remember { FocusRequester() }

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

  LaunchedEffect(Unit) { primaryFocus.requestFocus() }

  BackHandler {
    if (controlsVisible.not()) controlsVisible = true
    else {
      release(save = true)
      close()
    }
  }

  Box(Modifier.fillMaxSize().background(Color.Black).clickable { controlsVisible = !controlsVisible }) {
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
          .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .94f))))
          .padding(horizontal = 56.dp, vertical = 34.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
      ) {
        Text(source.title, color = Color.White, fontSize = 25.sp)
        LinearProgressIndicator(
          progress = { if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f },
          modifier = Modifier.fillMaxWidth().height(7.dp),
          color = Accent,
          trackColor = Color.White.copy(alpha = .25f),
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          PlayerButton("−10 s") { runtime?.player?.seekBack() }
          PlayerButton(if (isPlaying) "Pausar" else "Reproduzir", Modifier.focusRequester(primaryFocus)) {
            runtime?.player?.let { if (it.isPlaying) it.pause() else it.play() }
          }
          PlayerButton("+10 s") { runtime?.player?.seekForward() }
          Text("${clock(positionMs)} / ${clock(durationMs)}", color = Color.White, modifier = Modifier.padding(horizontal = 8.dp))
          Spacer(Modifier.weight(1f))
          if (source.tracks.audio.isNotEmpty()) {
            PlayerButton("Áudio: ${source.tracks.audio.getOrNull(audioIndex)?.label ?: "Padrão"}") {
              audioIndex = (audioIndex + 1) % source.tracks.audio.size
              persist(runtime?.player)
              changeAudio(source, source.tracks.audio[audioIndex].idx)
            }
          }
          if (source.tracks.subtitles.isNotEmpty()) {
            val label = if (subtitleIndex < 0) "Desligada" else source.tracks.subtitles[subtitleIndex].label
            PlayerButton("Legenda: $label") {
              subtitleIndex = if (subtitleIndex + 1 >= source.tracks.subtitles.size) -1 else subtitleIndex + 1
              runtime?.player?.let { player ->
                player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                  .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, subtitleIndex < 0)
                  .setPreferredTextLanguage(source.tracks.subtitles.getOrNull(subtitleIndex)?.lang)
                  .build()
              }
            }
          }
          PlayerButton("${speeds[speedIndex]}×") {
            speedIndex = (speedIndex + 1) % speeds.size
            runtime?.player?.setPlaybackSpeed(speeds[speedIndex])
          }
          if (source.nextFileId != null) PlayerButton("Próximo episódio") {
            persist(runtime?.player)
            playNext(source)
          }
        }
        error?.let { Text(it, color = Danger, fontSize = 16.sp) }
      }
    }
  }
}

@Composable
private fun PlayerButton(label: String, modifier: Modifier = Modifier, action: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  Box(
    modifier.background(if (focused) Accent else Color.White.copy(alpha = .14f), RoundedCornerShape(9.dp))
      .border(2.dp, if (focused) Color.White else Color.Transparent, RoundedCornerShape(9.dp))
      .onFocusChanged { focused = it.isFocused }.focusable().clickable(onClick = action)
      .padding(horizontal = 15.dp, vertical = 11.dp),
  ) {
    Text(label, color = if (focused) Color.Black else Color.White, fontSize = 14.sp)
  }
}

private fun clock(milliseconds: Long): String {
  val total = (milliseconds / 1_000).coerceAtLeast(0)
  val hours = total / 3_600
  val minutes = (total % 3_600) / 60
  val seconds = total % 60
  return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%02d:%02d".format(minutes, seconds)
}
