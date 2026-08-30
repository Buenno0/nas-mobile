package com.buenno.ozymandias.firetv

import android.app.Application
import com.buenno.ozymandias.firetv.data.CapabilityDetector
import com.buenno.ozymandias.firetv.data.CredentialVault
import com.buenno.ozymandias.firetv.data.OzymandiasRepository
import com.buenno.ozymandias.firetv.data.ServerDiscovery

class OzymandiasApplication : Application() {
  lateinit var repository: OzymandiasRepository
  lateinit var vault: CredentialVault
  lateinit var discovery: ServerDiscovery

  override fun onCreate() {
    super.onCreate()
    repository = OzymandiasRepository(CapabilityDetector.detect(this))
    vault = CredentialVault(this)
    discovery = ServerDiscovery(this)
  }
}
