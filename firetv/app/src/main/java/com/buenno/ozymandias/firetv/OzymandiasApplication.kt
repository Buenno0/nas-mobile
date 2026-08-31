package com.buenno.ozymandias.firetv

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import com.buenno.ozymandias.firetv.data.CapabilityDetector
import com.buenno.ozymandias.firetv.data.CredentialVault
import com.buenno.ozymandias.firetv.data.OzymandiasRepository
import com.buenno.ozymandias.firetv.data.ServerDiscovery

class OzymandiasApplication : Application(), ImageLoaderFactory {
  lateinit var repository: OzymandiasRepository
  lateinit var vault: CredentialVault
  lateinit var discovery: ServerDiscovery

  override fun onCreate() {
    super.onCreate()
    repository = OzymandiasRepository(CapabilityDetector.detect(this))
    vault = CredentialVault(this)
    discovery = ServerDiscovery(this)
  }

  override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
    .memoryCache {
      MemoryCache.Builder(this)
        .maxSizeBytes(32 * 1024 * 1024)
        .build()
    }
    .diskCache {
      DiskCache.Builder()
        .directory(cacheDir.resolve("artwork"))
        .maxSizeBytes(200L * 1024L * 1024L)
        .build()
    }
    .crossfade(140)
    .respectCacheHeaders(false)
    .build()
}
