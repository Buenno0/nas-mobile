package com.buenno.ozymandias.firetv.data

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import java.net.Inet6Address
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

@Suppress("DEPRECATION")
class ServerDiscovery(context: Context) {
  private val manager = context.getSystemService(NsdManager::class.java)
  private val wifi = context.applicationContext.getSystemService(WifiManager::class.java)

  fun servers(): Flow<List<ServerCandidate>> = callbackFlow {
    val found = linkedMapOf<String, ServerCandidate>()
    val lock = wifi.createMulticastLock("ozymandias-discovery").apply {
      setReferenceCounted(false)
      acquire()
    }
    val listener = object : NsdManager.DiscoveryListener {
      override fun onDiscoveryStarted(serviceType: String) = Unit
      override fun onDiscoveryStopped(serviceType: String) = Unit
      override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { close() }
      override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
      override fun onServiceLost(serviceInfo: NsdServiceInfo) {
        found.remove(serviceInfo.serviceName)
        trySend(found.values.toList())
      }
      override fun onServiceFound(serviceInfo: NsdServiceInfo) {
        manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
          override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) = Unit
          override fun onServiceResolved(info: NsdServiceInfo) {
            val address = info.host.hostAddress ?: return
            val host = if (info.host is Inet6Address) "[$address]" else address
            found[info.serviceName] = ServerCandidate(info.serviceName, "http://$host:${info.port}")
            trySend(found.values.toList())
          }
        })
      }
    }
    manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    awaitClose {
      runCatching { manager.stopServiceDiscovery(listener) }
      if (lock.isHeld) lock.release()
    }
  }

  companion object { private const val SERVICE_TYPE = "_ozymandias._tcp." }
}
