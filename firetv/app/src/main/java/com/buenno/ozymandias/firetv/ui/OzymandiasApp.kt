package com.buenno.ozymandias.firetv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.buenno.ozymandias.firetv.AppScreen
import com.buenno.ozymandias.firetv.AppViewModel

@Composable
fun OzymandiasApp(model: AppViewModel) {
  val ui by model.ui.collectAsStateWithLifecycle()
  val discovered by model.discoveredServers.collectAsStateWithLifecycle()

  BackHandler(enabled = ui.screen is AppScreen.Pairing || ui.screen is AppScreen.Login || ui.screen is AppScreen.Detail) {
    model.back()
  }

  Box(Modifier.fillMaxSize().background(Background)) {
    // Evita manter duas telas 1080p desenhadas durante crossfade no Fire Stick.
    when (val screen = ui.screen) {
      AppScreen.Restoring -> BrandStatus("Restaurando sessão…")
      AppScreen.Servers -> ServerScreen(discovered, ui.recentServers, ui.error, model::connectServer)
      is AppScreen.Pairing -> PairingScreen(screen.server, screen.pairing, ui.error, model::showManualLogin, model::restartPairing)
      is AppScreen.Login -> LoginScreen(screen.server, ui.error, model::login)
      is AppScreen.Main -> MainScreen(screen.tab, ui, model)
      is AppScreen.Detail -> DetailScreen(screen.title, ui.credential, model::play)
      is AppScreen.Player -> TvPlayerScreen(screen.source, model::saveProgress, model::changeAudio, model::playNext, model::closePlayer)
    }

    if (ui.loading) {
      Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .68f)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
          OzyMark(size = 58.dp)
          CircularProgressIndicator(color = Accent, strokeWidth = 3.dp)
          Text(ui.preparation?.let { "Preparando ${it.percentage}%" } ?: "Só um instante…", color = Ink)
        }
      }
    }
  }
}

@Composable
fun BrandStatus(message: String) {
  Column(
    Modifier.fillMaxSize(),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Center,
  ) {
    OzyMark(size = 82.dp)
    Text(message, Modifier.padding(top = 24.dp), color = Muted)
  }
}
