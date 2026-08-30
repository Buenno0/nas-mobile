package com.buenno.ozymandias.firetv

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.buenno.ozymandias.firetv.data.CredentialVault
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class AuthenticationFlowTest {
  @get:Rule val compose = createEmptyComposeRule()
  private lateinit var server: MockWebServer
  private var scenario: ActivityScenario<MainActivity>? = null

  @Before fun prepare() {
    runBlocking { CredentialVault(ApplicationProvider.getApplicationContext()).clear() }
    server = MockWebServer().apply { start() }
  }

  @After fun close() {
    scenario?.close()
    server.shutdown()
  }

  @Test fun serverPairingManualLoginHomeAccountAndLogout() {
    server.enqueue(json("""{"status":"ok","time":"now","api_version":2,"features":["device_pairing"]}"""))
    server.enqueue(json("""{
      "device_code":"secret-device-code","user_code":"ABCD-EFGH",
      "verification_uri":"${server.url("/conectar")}",
      "verification_uri_complete":"${server.url("/conectar?codigo=ABCD-EFGH")}",
      "expires_in":600,"interval":30
    }"""))
    server.enqueue(json("""{
      "username":"bueno","must_change_password":false,"is_admin":true,
      "token":"session-token","expira_em":"2099-01-01T00:00:00Z"
    }"""))
    server.enqueue(json("""{"continue":[],"rows":[]}"""))
    server.enqueue(json("""{"ok":true}"""))

    scenario = ActivityScenario.launch(MainActivity::class.java)
    compose.onNodeWithText("Escolha seu servidor").assertIsDisplayed()
    compose.onNodeWithText("URL do servidor").performTextInput(server.url("/").toString())
    compose.onNodeWithText("Conectar").performClick()
    compose.waitUntil(5_000) { compose.onAllNodesWithText("ABCD-EFGH").fetchSemanticsNodes().isNotEmpty() }
    compose.onNodeWithText("Conecte pelo celular").assertIsDisplayed()
    compose.onNodeWithText("Usar usuário e senha").performClick()
    compose.onNodeWithText("Usuário").performTextInput("bueno")
    compose.onNodeWithText("Senha").performTextInput("12345678")
    compose.onNodeWithText("Entrar").performClick()
    compose.waitUntil(5_000) { compose.onAllNodesWithText("Conta").fetchSemanticsNodes().isNotEmpty() }
    compose.onNodeWithText("Conta").performClick()
    compose.onNodeWithText("bueno").assertIsDisplayed()
    compose.onNodeWithText("Sair").performClick()
    compose.onNodeWithText("Escolha seu servidor").assertIsDisplayed()
  }

  private fun json(body: String) = MockResponse()
    .setHeader("Content-Type", "application/json")
    .setResponseCode(200)
    .setBody(body)
}
