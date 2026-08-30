package com.buenno.ozymandias.firetv.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsTest {
  @Test fun credentialDetectsExpiration() {
    val credential = Credential("https://example.com", "token", "2026-08-29T23:00:00Z", "bueno")
    assertFalse(credential.isExpired(1_788_044_399_000))
    assertTrue(credential.isExpired(1_788_044_401_000))
  }

  @Test fun invalidExpirationIsNotTrusted() {
    assertTrue(Credential("https://example.com", "token", "invalid", "bueno").isExpired())
  }

  @Test fun preferredFileResumesUnfinishedPlayback() {
    val fresh = mediaFile(1, position = 0.0)
    val resumed = mediaFile(2, position = 120.0)
    val detail = detail(listOf(fresh, resumed))
    assertEquals(2L, detail.preferredFile()?.id)
  }

  @Test fun preferredFileSkipsFinishedItems() {
    val finished = mediaFile(1, position = 100.0, finished = true)
    val fresh = mediaFile(2, position = 0.0)
    assertEquals(2L, detail(listOf(finished, fresh)).preferredFile()?.id)
  }

  @Test fun capabilitiesReportResolutionAndSelectedAudio() {
    val value = PlaybackCapabilities(setOf("h264", "hevc"), setOf("aac"), setOf("mp4"), 1920, 1080).query(3)
    assertTrue(value.contains("vid=h264,hevc"))
    assertTrue(value.contains("maxw=1920"))
    assertTrue(value.contains("maxh=1080"))
    assertTrue(value.contains("audio=3"))
  }

  private fun mediaFile(id: Long, position: Double, finished: Boolean = false) = MediaFile(
    id = id, relPath = "movie.mp4", name = "Movie", ext = "mp4", mediaType = "video",
    size = 100, duration = 600.0, position = position, finished = finished,
  )

  private fun detail(files: List<MediaFile>) = TitleDetail(
    id = 1, libraryId = 1, kind = TitleKind.MOVIE, name = "Movie", library = "Movies", files = files,
  )
}
