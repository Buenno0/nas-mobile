package com.buenno.ozymandias.firetv.data

import android.content.Context
import android.media.MediaCodecList
import android.view.WindowManager

data class PlaybackCapabilities(
  val video: Set<String>,
  val audio: Set<String>,
  val containers: Set<String>,
  val maxWidth: Int,
  val maxHeight: Int,
) {
  fun query(audioTrack: Int? = null): String = buildList {
    add("vid=${video.sorted().joinToString(",")}")
    add("aud=${audio.sorted().joinToString(",")}")
    add("cont=${containers.sorted().joinToString(",")}")
    add("maxw=$maxWidth")
    add("maxh=$maxHeight")
    if (audioTrack != null) add("audio=$audioTrack")
  }.joinToString("&")
}

object CapabilityDetector {
  fun detect(context: Context): PlaybackCapabilities {
    val types = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
      .filterNot { it.isEncoder }.flatMap { it.supportedTypes.asIterable() }.map { it.lowercase() }.toSet()
    val video = buildSet {
      if ("video/avc" in types) add("h264")
      if ("video/hevc" in types) add("hevc")
      if ("video/x-vnd.on2.vp9" in types) add("vp9")
      if ("video/av01" in types) add("av1")
    }.ifEmpty { setOf("h264") }
    val audio = buildSet {
      if ("audio/mp4a-latm" in types) add("aac")
      if ("audio/mpeg" in types) add("mp3")
      if ("audio/ac3" in types) add("ac3")
      if ("audio/eac3" in types) add("eac3")
      if ("audio/flac" in types) add("flac")
      if ("audio/opus" in types) add("opus")
      if ("audio/vorbis" in types) add("vorbis")
    }.ifEmpty { setOf("aac", "mp3") }
    val display = context.getSystemService(WindowManager::class.java).defaultDisplay.mode
    return PlaybackCapabilities(
      video = video,
      audio = audio,
      containers = setOf("mp4", "m4v", "mov", "mkv", "webm", "ts", "m2ts", "m4a", "mp3", "ogg", "flac", "wav"),
      maxWidth = display.physicalWidth.coerceAtLeast(1280),
      maxHeight = display.physicalHeight.coerceAtLeast(720),
    )
  }
}
