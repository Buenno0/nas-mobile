package com.buenno.ozymandias.firetv.data

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerAddressTest {
  @Test fun addsSchemeAndAcceptsPrivateLan() = runTest {
    assertEquals("http://192.168.1.20:8787", ServerAddress.normalize(" 192.168.1.20:8787/ "))
  }

  @Test fun acceptsLocalHostname() = runTest {
    assertEquals("http://ozymandias.local:8787", ServerAddress.normalize("http://ozymandias.local:8787"))
  }

  @Test fun requiresHttpsForPublicHost() = runTest {
    val error = runCatching { ServerAddress.normalize("http://8.8.8.8:8787") }.exceptionOrNull()
    assertTrue(error is IllegalArgumentException)
    assertTrue(error?.message.orEmpty().contains("HTTPS"))
  }

  @Test fun acceptsPublicHttpsAndRemovesTrailingSlash() = runTest {
    assertEquals("https://media.example.com", ServerAddress.normalize("https://media.example.com/"))
  }

  @Test fun rejectsPathAndCredentials() = runTest {
    assertTrue(runCatching { ServerAddress.normalize("https://example.com/api") }.isFailure)
    assertTrue(runCatching { ServerAddress.normalize("https://user@example.com") }.isFailure)
  }
}
