package com.buenno.ozymandias.firetv.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.buenno.ozymandias.firetv.data.DeviceStartResponse
import com.buenno.ozymandias.firetv.data.ServerCandidate
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

@Composable
fun ServerScreen(
  discovered: List<ServerCandidate>,
  recent: List<String>,
  error: String?,
  connect: (String) -> Unit,
) {
  var address by remember { mutableStateOf("") }
  OzySplitShell(
    eyebrow = "Seu acervo, na sua rede",
    title = "Escolha seu servidor",
    subtitle = "Encontramos servidores Ozymandias na rede local. Você também pode usar um endereço seguro externo.",
  ) {
    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      if (discovered.isNotEmpty()) {
        item { SectionTitle("Encontrados na rede") }
        items(discovered, key = { it.url }) { server ->
          ServerChoice(server.name, server.url, OzyGlyph.WIFI) { connect(server.url) }
        }
      }
      if (recent.isNotEmpty()) {
        item { SectionTitle("Recentes") }
        items(recent.take(3), key = { it }) { server ->
          ServerChoice(server.substringAfter("://"), server, OzyGlyph.CLOCK) { connect(server) }
        }
      }
      item { SectionTitle("Outro endereço") }
      item { OzyTextField(address, { address = it }, "URL do servidor", "http://ozymandias.local:8787") }
      item {
        Row(Modifier.padding(top = 4.dp)) {
          OzyPrimaryAction("Conectar", OzyGlyph.SERVER, enabled = address.isNotBlank()) { connect(address) }
        }
      }
      error?.let { item { ErrorPanel(it) } }
    }
  }
}

@Composable
private fun ServerChoice(name: String, address: String, glyph: OzyGlyph, select: () -> Unit) {
  var focused by remember { mutableStateOf(false) }
  OzyFocusFrame(
    focused,
    Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = select),
  ) {
    Row(
      Modifier.fillMaxWidth().background(if (focused) Elevated else Surface).padding(14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Box(
        Modifier.size(42.dp).clip(RoundedCornerShape(12.dp)).background(if (focused) Ink else Elevated),
        contentAlignment = Alignment.Center,
      ) { OzyIcon(glyph, tint = if (focused) AccentInk else Accent, size = 20.dp) }
      Column(Modifier.weight(1f)) {
        Text(name, color = Ink, style = OzyType.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(address, color = Muted, style = OzyType.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
    }
  }
}

@Composable
fun PairingScreen(
  server: String,
  pairing: DeviceStartResponse,
  error: String?,
  manual: (String) -> Unit,
  restart: (String) -> Unit,
) {
  OzySplitShell(
    eyebrow = "Conectar uma TV",
    title = "Autorize pelo iPhone",
    subtitle = "No Ozymandias do iPhone, abra Perfil › Conectar uma TV e aponte a câmera para o código.",
    aside = {
      OzyStatus(
        if (error == null) "Aguardando autorização…" else "Pareamento interrompido",
        if (error == null) Okay else Danger,
        Modifier.padding(top = 6.dp),
      )
    },
  ) {
    Row(
      Modifier.fillMaxSize(),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(28.dp),
    ) {
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OzyEyebrow("Código da TV", color = Muted)
        Text(pairing.userCode, color = Accent, style = OzyType.display)
        error?.let { ErrorPanel(it) }
        Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          OzySecondaryAction("Usuário e senha", OzyGlyph.USER) { manual(server) }
          if (error != null) OzySecondaryAction("Novo código") { restart(server) }
        }
      }
      Box(
        Modifier.size(232.dp).clip(RoundedCornerShape(OzyTvTokens.panelRadius)).background(Ink).padding(14.dp),
        contentAlignment = Alignment.Center,
      ) {
        Image(
          rememberQrCode(pairing.verificationUriComplete),
          "QR Code de pareamento",
          Modifier.fillMaxSize(),
        )
      }
    }
  }
}

@Composable
fun LoginScreen(server: String, error: String?, login: (String, String, String) -> Unit) {
  var username by remember { mutableStateOf("") }
  var password by remember { mutableStateOf("") }
  OzySplitShell(
    eyebrow = "Entrada alternativa",
    title = "Entrar manualmente",
    subtitle = server,
  ) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
      Text("Use a mesma conta configurada no servidor.", color = Muted, style = OzyType.body)
      OzyTextField(username, { username = it }, "Usuário")
      OzyTextField(password, { password = it }, "Senha", password = true)
      Row(Modifier.padding(top = 4.dp)) {
        OzyPrimaryAction("Entrar", OzyGlyph.USER, enabled = username.isNotBlank() && password.isNotBlank()) {
          login(server, username, password)
        }
      }
      error?.let { ErrorPanel(it) }
    }
  }
}

@Composable
private fun OzyTextField(
  value: String,
  change: (String) -> Unit,
  label: String,
  placeholder: String = "",
  password: Boolean = false,
) {
  OutlinedTextField(
    value = value,
    onValueChange = change,
    label = { Text(label, style = OzyType.caption) },
    placeholder = { if (placeholder.isNotEmpty()) Text(placeholder, style = OzyType.label) },
    textStyle = OzyType.label,
    singleLine = true,
    visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(OzyTvTokens.cardRadius),
    colors = OutlinedTextFieldDefaults.colors(
      focusedBorderColor = Accent, unfocusedBorderColor = Line, focusedLabelColor = Accent,
      unfocusedLabelColor = Muted, focusedTextColor = Ink, unfocusedTextColor = Ink,
      focusedPlaceholderColor = Muted, unfocusedPlaceholderColor = Muted,
      cursorColor = Accent, focusedContainerColor = Elevated, unfocusedContainerColor = Surface,
    ),
  )
}

@Composable
private fun SectionTitle(value: String) =
  OzyEyebrow(value, Modifier.padding(top = 10.dp, bottom = 2.dp), color = Muted)

@Composable
fun ErrorPanel(value: String) {
  Row(
    Modifier.fillMaxWidth().clip(RoundedCornerShape(OzyTvTokens.cardRadius))
      .background(Danger.copy(alpha = .12f))
      .border(1.dp, Danger.copy(alpha = .35f), RoundedCornerShape(OzyTvTokens.cardRadius))
      .padding(12.dp),
  ) {
    Text(value, color = Danger, style = OzyType.caption)
  }
}

// O código só muda quando o servidor emite outro, mas a tela recompõe a cada
// mudança de estado do pareamento. Sem `remember`, cada recomposição redesenhava
// o QR pixel por pixel na thread principal — 176 mil chamadas de `setPixel`.
@Composable
private fun rememberQrCode(value: String): ImageBitmap = remember(value) {
  val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, 420, 420)
  val width = matrix.width
  val height = matrix.height
  val dark = AccentInk.toArgb()
  val light = Ink.toArgb()
  val pixels = IntArray(width * height) { index ->
    if (matrix[index % width, index / width]) dark else light
  }
  Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    .apply { setPixels(pixels, 0, width, 0, 0, width, height) }
    .asImageBitmap()
}
