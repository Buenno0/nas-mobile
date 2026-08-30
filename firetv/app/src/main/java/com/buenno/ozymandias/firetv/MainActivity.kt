package com.buenno.ozymandias.firetv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.buenno.ozymandias.firetv.ui.OzymandiasApp
import com.buenno.ozymandias.firetv.ui.OzymandiasTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      OzymandiasTheme {
        val model: AppViewModel = viewModel(factory = AppViewModel.Factory(application as OzymandiasApplication))
        OzymandiasApp(model)
      }
    }
  }
}
