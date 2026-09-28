package com.buenno.ozymandias.firetv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.buenno.ozymandias.firetv.data.Credential

enum class ArtworkKind(val width: Int, val height: Int) {
  POSTER(OzyTvTokens.posterPixelsWidth, OzyTvTokens.posterPixelsHeight),
  LANDSCAPE(640, 360),
  BACKDROP(OzyTvTokens.backdropPixelsWidth, OzyTvTokens.backdropPixelsHeight),
}

@Composable
fun OzyArtwork(
  path: String?,
  credential: Credential?,
  kind: ArtworkKind,
  modifier: Modifier = Modifier,
  contentScale: ContentScale = ContentScale.Crop,
) {
  val url = path?.let { if (it.startsWith("http")) it else credential?.serverUrl + it }
  // Mesmo placeholder do iOS: um degradê da superfície elevada para o âmbar da
  // marca. Um retângulo chapado deixava buracos escuros na grade enquanto as
  // capas carregavam.
  val placeholder = Brush.linearGradient(listOf(Elevated, Accent.copy(alpha = .48f)))
  Box(modifier.background(placeholder), contentAlignment = Alignment.Center) {
    if (url == null) {
      OzyMark(size = if (kind == ArtworkKind.POSTER) 44.dp else 60.dp)
    } else {
      AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
          .data(url)
          .size(kind.width, kind.height)
          .apply { credential?.let { addHeader("Authorization", "Bearer ${it.token}") } }
          .build(),
        contentDescription = null,
        modifier = Modifier.fillMaxSize(),
        contentScale = contentScale,
      )
    }
  }
}
