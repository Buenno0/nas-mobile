package com.buenno.ozymandias.firetv.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.Json

private val Context.ozymandiasData by preferencesDataStore("ozymandias_tv")

class CredentialVault(private val context: Context) {
  private val json = Json { ignoreUnknownKeys = true }
  private val credentialKey = stringPreferencesKey("credential")
  private val recentKey = stringPreferencesKey("recent_servers")

  suspend fun save(credential: Credential) {
    val encoded = json.encodeToString(Credential.serializer(), credential)
    context.ozymandiasData.edit { it[credentialKey] = encrypt(encoded) }
    rememberServer(credential.serverUrl)
  }

  suspend fun load(): Credential? {
    val value = context.ozymandiasData.data.first()[credentialKey] ?: return null
    return runCatching { json.decodeFromString<Credential>(decrypt(value)) }.getOrNull()
  }

  suspend fun clear() {
    context.ozymandiasData.edit { it.remove(credentialKey) }
  }

  suspend fun recentServers(): List<String> {
    val raw = context.ozymandiasData.data.first()[recentKey] ?: return emptyList()
    return runCatching { json.decodeFromString<List<String>>(raw) }.getOrDefault(emptyList())
  }

  suspend fun rememberServer(server: String) {
    val updated = (listOf(server) + recentServers().filterNot { it == server }).take(3)
    context.ozymandiasData.edit { it[recentKey] = json.encodeToString(updated) }
  }

  private fun encrypt(value: String): String {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key())
    val payload = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    return Base64.encodeToString(payload, Base64.NO_WRAP)
  }

  private fun decrypt(value: String): String {
    val payload = Base64.decode(value, Base64.NO_WRAP)
    val iv = payload.copyOfRange(0, 12)
    val encrypted = payload.copyOfRange(12, payload.size)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
    return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
  }

  private fun key(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
    return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
      init(
        KeyGenParameterSpec.Builder(
          KEY_ALIAS,
          KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
          .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
          .setRandomizedEncryptionRequired(true)
          .build(),
      )
      generateKey()
    }
  }

  companion object { private const val KEY_ALIAS = "ozymandias.firetv.session.v1" }
}
