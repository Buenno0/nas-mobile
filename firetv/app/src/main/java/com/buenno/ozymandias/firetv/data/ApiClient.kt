package com.buenno.ozymandias.firetv.data

import java.io.IOException
import java.net.InetAddress
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class ApiException(val status: Int, override val message: String) : IOException(message)

object ServerAddress {
  suspend fun normalize(input: String): String = withContext(Dispatchers.IO) {
    var value = input.trim()
    if (!value.contains("://")) value = "http://$value"
    val uri = runCatching { URI(value) }.getOrNull()
      ?: throw IllegalArgumentException("O endereço do servidor não é válido.")
    val scheme = uri.scheme?.lowercase()
    require(scheme == "http" || scheme == "https") { "Use um endereço HTTP ou HTTPS." }
    require(uri.host != null && uri.userInfo == null && (uri.path.isNullOrEmpty() || uri.path == "/") && uri.query == null) {
      "Informe apenas o endereço e a porta do servidor."
    }
    if (scheme == "http") {
      val host = uri.host.lowercase()
      val local = host == "localhost" || host.endsWith(".local") ||
        runCatching { InetAddress.getAllByName(host).all { it.isSiteLocalAddress || it.isLoopbackAddress || it.isLinkLocalAddress } }.getOrDefault(false)
      require(local) { "Endereços públicos precisam usar HTTPS." }
    }
    URI(scheme, null, uri.host, uri.port, null, null, null).toString().removeSuffix("/")
  }
}

class ApiClient(
  val baseUrl: String,
  private val http: OkHttpClient = OkHttpClient.Builder().retryOnConnectionFailure(true).build(),
) {
  @PublishedApi internal val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
  private val mediaType = "application/json; charset=utf-8".toMediaType()

  suspend inline fun <reified T> get(path: String, token: String? = null): T =
    request(path, "GET", token, null, serializer())

  suspend inline fun <reified T, reified B> post(path: String, body: B, token: String? = null): T =
    request(path, "POST", token, json.encodeToString(serializer(), body), serializer())

  suspend inline fun <reified T> postEmpty(path: String, token: String? = null): T =
    request(path, "POST", token, "{}", serializer())

  suspend inline fun <reified B> put(path: String, body: B, token: String) {
    request<Unit>(path, "PUT", token, json.encodeToString(serializer(), body), null)
  }

  suspend fun pollDeviceToken(deviceCode: String): User? = withContext(Dispatchers.IO) {
    val body = json.encodeToString(DeviceCodeRequest.serializer(), DeviceCodeRequest(deviceCode))
      .toRequestBody(mediaType)
    val request = Request.Builder().url(resolve("/api/auth/device/token"))
      .header("Accept", "application/json").post(body).build()
    http.newCall(request).execute().use { response ->
      val text = response.body?.string().orEmpty()
      if (response.code == 202 || response.code == 429) return@withContext null
      if (!response.isSuccessful) {
        val error = runCatching { json.decodeFromString<ErrorResponse>(text).error }.getOrNull()
        throw ApiException(response.code, error ?: "Erro ${response.code} ao falar com o servidor.")
      }
      json.decodeFromString<User>(text)
    }
  }

  suspend fun <T> request(
    path: String,
    method: String,
    token: String?,
    body: String?,
    serializer: KSerializer<T>?,
  ): T = withContext(Dispatchers.IO) {
    val builder = Request.Builder().url(resolve(path)).header("Accept", "application/json")
    if (token != null) builder.header("Authorization", "Bearer $token")
    val requestBody = body?.toRequestBody(mediaType)
    builder.method(method, if (method == "GET") null else requestBody)
    val request = builder.build()
    var last: IOException? = null
    val attempts = if (method == "GET") 2 else 1
    repeat(attempts) { attempt ->
      try {
        http.newCall(request).execute().use { response ->
          val text = response.body?.string().orEmpty()
          if (!response.isSuccessful) {
            val error = runCatching { json.decodeFromString<ErrorResponse>(text).error }.getOrNull()
            throw ApiException(response.code, error ?: "Erro ${response.code} ao falar com o servidor.")
          }
          @Suppress("UNCHECKED_CAST")
          return@withContext if (serializer == null || response.code == 204) Unit as T
          else json.decodeFromString(serializer, text)
        }
      } catch (error: ApiException) {
        throw error
      } catch (error: IOException) {
        last = error
        if (attempt + 1 < attempts) delay(250)
      }
    }
    throw ApiException(0, last?.message ?: "Não foi possível falar com o servidor.")
  }

  fun resolve(path: String): String = if (path.startsWith("http://") || path.startsWith("https://")) path
  else baseUrl + if (path.startsWith('/')) path else "/$path"

  fun imageUrl(path: String?): String? = path?.let(::resolve)

  companion object {
    fun encoded(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.toString())
  }
}
