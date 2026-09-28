package com.buenno.ozymandias.firetv.data

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingTest {
  private val server = MockWebServer()
  private val repository =
    OzymandiasRepository(PlaybackCapabilities(setOf("h264"), setOf("aac"), setOf("mp4"), 1920, 1080))

  @After fun stop() = server.shutdown()

  // O servidor nunca autoriza: o polling precisa desistir no fim da janela em
  // vez de consultar a rede para sempre.
  @Test fun expiredCodeStopsPolling() = runTest {
    server.dispatcher = pending()
    val error = runCatching {
      repository.pollPairing(url(), "device-code", interval = 10, expiresIn = 120)
    }.exceptionOrNull() as ApiException
    assertEquals(408, error.status)
    assertEquals(OzymandiasRepository.PAIRING_EXPIRED, error.message)
    // Janela de 120s consultada a cada 10s: doze tentativas e nada além disso.
    assertEquals(12, server.requestCount)
  }

  // Uma janela absurdamente curta vinda do servidor não pode reprovar o
  // pareamento antes da primeira consulta.
  @Test fun shortWindowIsRaisedToTheMinimum() = runTest {
    server.dispatcher = pending()
    val error = runCatching {
      repository.pollPairing(url(), "device-code", interval = 30, expiresIn = 1)
    }.exceptionOrNull()
    assertTrue(error is ApiException)
    // 1s vira o piso de 60s, então ainda cabem duas tentativas de 30s.
    assertEquals(2, server.requestCount)
  }

  @Test fun authorizedCodeReturnsTheSession() = runTest {
    var calls = 0
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        calls += 1
        return if (calls < 3) MockResponse().setResponseCode(202)
        else MockResponse().setResponseCode(200).setBody(
          """{"username":"bueno","must_change_password":false,"is_admin":true,""" +
            """"token":"tv-token","expira_em":"2099-01-01T00:00:00Z"}""",
        )
      }
    }
    val user = repository.pollPairing(url(), "device-code", interval = 5, expiresIn = 600)
    assertEquals("bueno", user.username)
    assertEquals("tv-token", user.token)
  }

  // Um OkHttpClient por requisição faria a TV reabrir a conexão a cada chamada;
  // com o cliente compartilhado, a segunda requisição sai pela mesma conexão
  // (sequenceNumber > 0).
  @Test fun repeatedCallsReuseTheSameConnection() = runTest {
    repeat(2) { server.enqueue(MockResponse().setBody("""{"status":"ok"}""")) }
    val address = url()
    repository.health(address)
    repository.health(address)
    assertEquals(0, server.takeRequest().sequenceNumber)
    assertEquals(1, server.takeRequest().sequenceNumber)
  }

  private fun pending() = object : Dispatcher() {
    override fun dispatch(request: RecordedRequest) = MockResponse().setResponseCode(202)
  }

  private fun url() = server.url("/").toString().removeSuffix("/")
}
