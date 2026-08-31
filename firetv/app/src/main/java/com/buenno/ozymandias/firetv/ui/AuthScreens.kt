package com.buenno.ozymandias.firetv.ui

import android.graphics.Bitmap
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.buenno.ozymandias.firetv.data.DeviceStartResponse
import com.buenno.ozymandias.firetv.data.ServerCandidate
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

@Composable
private fun AuthShell(eyebrow: String, title: String, subtitle: String, content: @Composable () -> Unit) {
  Row(
    Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 58.dp),
    horizontalArrangement = Arrangement.spacedBy(72.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(Modifier.width(430.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
      OzyMark(size = 78.dp)
      Text(eyebrow.uppercase(), color = Accent, fontSize = 13.sp, letterSpacing = 2.8.sp, fontWeight = FontWeight.Bold)
      Text(title, color = Ink, fontSize = 42.sp, lineHeight = 46.sp, fontWeight = FontWeight.Bold)
      Text(subtitle, color = Muted, fontSize = 18.sp, lineHeight = 26.sp)
    }
    Box(
      Modifier.weight(1f).clip(RoundedCornerShape(22.dp)).background(Surface)
        .border(1.dp, Line, RoundedCornerShape(22.dp)).padding(30.dp),
    ) { content() }
  }
}

@Composable
fun ServerScreen(discovered: List<ServerCandidate>, recent: List<String>, error: String?, connect: (String) -> Unit) {
  var address by remember { mutableStateOf("") }
  AuthShell("Seu acervo, na sua rede", "Escolha seu servidor", "Encontramos servidores Ozymandias na rede local. Você também pode usar um endereço seguro externo.") {
    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
      if (discovered.isNotEmpty()) {
        item { AuthSectionTitle("Encontrados na rede") }
        items(discovered, key = { it.url }) { server -> ServerChoice(server.name, server.url, OzyGlyph.WIFI) { connect(server.url) } }
      }
      if (recent.isNotEmpty()) {
        item { AuthSectionTitle("Recentes") }
        items(recent.take(3), key = { it }) { server -> ServerChoice(server.substringAfter("://"), server, OzyGlyph.CLOCK) { connect(server) } }
      }
      item { AuthSectionTitle("Outro endereço") }
      item {
        OzyTextField(address, { address = it }, "URL do servidor", "http://ozymandias.local:8787")
      }
      item {
        Row(Modifier.padding(top = 6.dp)) {
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
  val color by animateColorAsState(if (focused) Elevated else Background.copy(alpha=.62f), tween(140), label = "server-row")
  Row(
    Modifier.fillMaxWidth().clip(RoundedCornerShape(15.dp)).background(color)
      .border(1.dp, if (focused) Color.White else Line, RoundedCornerShape(15.dp))
      .onFocusChanged { focused = it.isFocused }.ozyClickable(onClick = select).padding(17.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(16.dp),
  ) {
    Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(if (focused) Ink else Elevated), contentAlignment = Alignment.Center) {
      OzyIcon(glyph, tint = if (focused) Background else Accent)
    }
    Column(Modifier.weight(1f)) {
      Text(name, color = Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
      Text(address, color = Muted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
  }
}

@Composable
fun PairingScreen(server: String, pairing: DeviceStartResponse, error: String?, manual: (String) -> Unit, restart: (String) -> Unit) {
  AuthShell("Conectar uma TV", "Autorize pelo iPhone", "No Ozymandias do iPhone, abra Perfil › Conectar uma TV e aponte a câmera para o código.") {
    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(34.dp)) {
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Código da TV", color = Muted, fontSize = 13.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.SemiBold)
        Text(pairing.userCode, color = Accent, fontSize = 38.sp, letterSpacing = 4.sp, fontWeight = FontWeight.Bold)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          Box(Modifier.size(9.dp).clip(RoundedCornerShape(50)).background(Okay))
          Text("Aguardando autorização…", color = Ink, fontSize = 15.sp)
        }
        error?.let { ErrorPanel(it) }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          OzySecondaryAction("Usuário e senha", OzyGlyph.USER) { manual(server) }
          if (error != null) OzySecondaryAction("Novo código") { restart(server) }
        }
      }
      Box(Modifier.size(278.dp).clip(RoundedCornerShape(20.dp)).background(Color.White).padding(16.dp), contentAlignment = Alignment.Center) {
        Image(qrBitmap(pairing.verificationUriComplete).asImageBitmap(), "QR Code de pareamento", Modifier.fillMaxSize())
      }
    }
  }
}

@Composable
fun LoginScreen(server: String, error: String?, login: (String, String, String) -> Unit) {
  var username by remember { mutableStateOf("") }
  var password by remember { mutableStateOf("") }
  AuthShell("Entrada alternativa", "Entrar manualmente", server) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
      Text("Use a mesma conta configurada no servidor.", color = Muted, fontSize = 16.sp)
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
private fun OzyTextField(value: String, change: (String) -> Unit, label: String, placeholder: String = "", password: Boolean = false) {
  OutlinedTextField(
    value = value,
    onValueChange = change,
    label = { Text(label) },
    placeholder = { if (placeholder.isNotEmpty()) Text(placeholder) },
    singleLine = true,
    visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(14.dp),
    colors = OutlinedTextFieldDefaults.colors(
      focusedBorderColor = Accent, unfocusedBorderColor = Line, focusedLabelColor = Accent,
      unfocusedLabelColor = Muted, focusedTextColor = Ink, unfocusedTextColor = Ink,
      cursorColor = Accent, focusedContainerColor = Elevated, unfocusedContainerColor = Background.copy(alpha=.45f),
    ),
  )
}

@Composable private fun AuthSectionTitle(value: String) = Text(value.uppercase(), Modifier.padding(top = 8.dp, bottom = 2.dp), color = Muted, fontSize = 12.sp, letterSpacing = 1.7.sp, fontWeight = FontWeight.Bold)

@Composable
fun ErrorPanel(value: String) {
  Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(Danger.copy(alpha=.12f)).border(1.dp, Danger.copy(alpha=.35f), RoundedCornerShape(13.dp)).padding(14.dp)) {
    Text(value, color = Danger, fontSize = 14.sp)
  }
}

private fun qrBitmap(value: String): Bitmap {
  val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, 420, 420)
  return Bitmap.createBitmap(420, 420, Bitmap.Config.ARGB_8888).apply {
    for (y in 0 until 420) for (x in 0 until 420) setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
  }
}
