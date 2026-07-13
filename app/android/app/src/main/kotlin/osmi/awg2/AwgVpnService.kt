package osmi.awg2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import org.amnezia.awg.GoBackend
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AmneziaWG tunnel host. Owns the TUN fd + the Go backend handle, keeps a
 * foreground notification, streams stats to [AwgVpnState] and auto-reconnects
 * when the tunnel stalls or the underlying network changes.
 */
class AwgVpnService : VpnService() {

    private val lock = Any()
    private var handle = -1
    private var tun: ParcelFileDescriptor? = null
    private var payload: JSONObject? = null

    @Volatile private var running = false
    private var poller: Thread? = null
    private val restarting = AtomicBoolean(false)
    private var generation = 0

    private var connectivity: ConnectivityManager? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                teardown(stopService = true)
                return START_NOT_STICKY
            }
            ACTION_CONNECT -> {
                val raw = intent.getStringExtra(EXTRA_PAYLOAD)
                if (raw == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForegroundNotification()
                Thread({ connect(JSONObject(raw)) }, "AwgConnect").start()
                // STICKY so the OS restarts us after being killed in background.
                return START_STICKY
            }
            else -> {
                // Restarted by the system (START_STICKY with null intent) or
                // Always-on VPN. Try to bring the last tunnel back up.
                if (payload != null) {
                    startForegroundNotification()
                    Thread({ connect(payload!!) }, "AwgReconnect").start()
                    return START_STICKY
                }
                stopSelf()
                return START_NOT_STICKY
            }
        }
    }

    private fun connect(cfg: JSONObject) {
        synchronized(lock) {
            try {
                if (handle != -1) return
                payload = cfg
                AwgVpnState.update("connecting", id = cfg.optString("id"))

                val tunFd = establishTun(cfg) ?: run {
                    AwgVpnState.update("error", error = "Не удалось создать TUN")
                    stopSelf()
                    return
                }
                val ifName = cfg.optString("name").ifBlank { "osmira" }
                    .replace(Regex("[^A-Za-z0-9_-]"), "_").take(15)
                val uapi = cfg.optString("uapi")

                val h = GoBackend.awgTurnOn(ifName, tunFd, uapi)
                if (h < 0) {
                    AwgVpnState.update("error", error = "Go backend error $h")
                    stopSelf()
                    return
                }
                handle = h
                protect(GoBackend.awgGetSocketV4(handle))
                protect(GoBackend.awgGetSocketV6(handle))
                running = true
                registerNetworkCallback()
                startPoller(cfg.optString("id"))
                Log.i(TAG, "Tunnel up: ${GoBackend.awgVersion()}")
            } catch (e: Throwable) {
                Log.e(TAG, "connect failed", e)
                AwgVpnState.update("error", error = e.message ?: "connect failed")
                stopSelf()
            }
        }
    }

    private fun establishTun(cfg: JSONObject): Int? {
        val builder = Builder()
        builder.setSession(cfg.optString("name").ifBlank { "Osmira" })

        val mode = cfg.optString("routingMode", "all")
        val apps = cfg.optJSONArray("apps")
        if (apps != null && mode != "all") {
            for (i in 0 until apps.length()) {
                val pkg = apps.optString(i)
                if (pkg.isBlank() || pkg == packageName) continue
                try {
                    if (mode == "include") builder.addAllowedApplication(pkg)
                    else builder.addDisallowedApplication(pkg)
                } catch (_: Exception) {
                    // Package no longer installed; skip it.
                }
            }
        }

        forEach(cfg.optJSONArray("addresses")) { a ->
            val (ip, prefix) = splitCidr(a)
            builder.addAddress(ip, prefix)
        }
        forEach(cfg.optJSONArray("dns")) { d -> builder.addDnsServer(d) }
        forEach(cfg.optJSONArray("searchDomains")) { s -> builder.addSearchDomain(s) }

        var sawDefaultRoute = false
        forEach(cfg.optJSONArray("routes")) { r ->
            val (ip, prefix) = splitCidr(r)
            if (prefix == 0) sawDefaultRoute = true
            builder.addRoute(ip, prefix)
        }

        // Kill-switch semantics: only skip allowFamily for a single-peer full
        // tunnel (everything already forced through the tun).
        val peerCount = cfg.optInt("peerCount", 1)
        if (!(sawDefaultRoute && peerCount == 1)) {
            builder.allowFamily(OsConstants.AF_INET)
            builder.allowFamily(OsConstants.AF_INET6)
        }

        builder.setMtu(cfg.optInt("mtu", 1280))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) setUnderlyingNetworks(null)
        builder.setBlocking(true)

        val pfd = builder.establish() ?: return null
        tun = pfd
        return pfd.detachFd()
    }

    private fun startPoller(id: String?) {
        val gen = ++generation
        poller = Thread({
            var connectedReported = false
            while (running && gen == generation && !Thread.currentThread().isInterrupted) {
                val stats = readStats()
                if (stats == null) {
                    sleep(2000); continue
                }
                val (rx, tx, hs) = stats
                val nowSec = System.currentTimeMillis() / 1000
                val age = if (hs > 0) nowSec - hs else Long.MAX_VALUE

                if (hs > 0) {
                    if (!connectedReported) {
                        connectedReported = true
                        updateNotification("Подключено")
                    }
                    AwgVpnState.update("connected", id, rx, tx, hs)
                } else {
                    AwgVpnState.update("connecting", id, rx, tx, 0)
                }

                // Stall detection: healthy handshakes refresh every ~2 min.
                if (connectedReported && age != Long.MAX_VALUE && age > STALL_SECONDS) {
                    Log.w(TAG, "Handshake stale (${age}s) — reconnecting")
                    scheduleRestart()
                    return@Thread
                }
                sleep(2000)
            }
        }, "AwgPoller").also { it.start() }
    }

    private fun readStats(): Triple<Long, Long, Long>? {
        val h = handle
        if (h == -1) return null
        val config = GoBackend.awgGetConfig(h) ?: return null
        var rx = 0L; var tx = 0L; var hs = 0L
        for (line in config.split("\n")) {
            when {
                line.startsWith("rx_bytes=") ->
                    rx += line.substring(9).toLongOrNull() ?: 0
                line.startsWith("tx_bytes=") ->
                    tx += line.substring(9).toLongOrNull() ?: 0
                line.startsWith("last_handshake_time_sec=") ->
                    hs = maxOf(hs, line.substring(24).toLongOrNull() ?: 0)
            }
        }
        return Triple(rx, tx, hs)
    }

    private fun scheduleRestart() {
        if (!running) return
        if (!restarting.compareAndSet(false, true)) return
        AwgVpnState.update("reconnecting", id = payload?.optString("id"))
        updateNotification("Переподключение…")
        Thread({
            try {
                val cfg = payload ?: return@Thread
                synchronized(lock) {
                    if (handle != -1) {
                        GoBackend.awgTurnOff(handle)
                        handle = -1
                    }
                    tun?.close(); tun = null
                }
                sleep(600)
                connect(cfg)
            } finally {
                restarting.set(false)
            }
        }, "AwgRestart").start()
    }

    private fun registerNetworkCallback() {
        if (netCallback != null) return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivity = cm
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .removeTransportType(NetworkCapabilities.TRANSPORT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            private var first = true
            override fun onAvailable(network: Network) {
                // The first callback fires for the network we came up on.
                if (first) { first = false; return }
                if (running) scheduleRestart()
            }
        }
        netCallback = cb
        try {
            cm.registerNetworkCallback(request, cb)
        } catch (e: Exception) {
            Log.w(TAG, "network callback registration failed", e)
            netCallback = null
        }
    }

    private fun teardown(stopService: Boolean) {
        synchronized(lock) {
            running = false
            generation++
            poller?.interrupt(); poller = null
            netCallback?.let { cb ->
                try { connectivity?.unregisterNetworkCallback(cb) } catch (_: Exception) {}
            }
            netCallback = null
            if (handle != -1) {
                GoBackend.awgTurnOff(handle)
                handle = -1
            }
            tun?.let { try { it.close() } catch (_: Exception) {} }
            tun = null
            payload = null
        }
        AwgVpnState.update("disconnected")
        if (stopService) {
            stopForegroundCompat()
            stopSelf()
        }
    }

    override fun onRevoke() {
        // User replaced us with another VPN / revoked consent.
        teardown(stopService = true)
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown(stopService = false)
        super.onDestroy()
    }

    // ── foreground notification ──────────────────────────────────────────
    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Osmira", NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false); lockscreenVisibility = Notification.VISIBILITY_SECRET }
            nm.createNotificationChannel(channel)
        }
        val notif = buildNotification("Подключение…")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun buildNotification(text: String): Notification {
        // ACTION_MAIN + LAUNCHER + NEW_TASK works exactly like tapping the app
        // icon: brings an existing task forward, or cold-starts the app if it
        // was killed — the vk-bridge behaviour.
        val launch = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        val open = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Osmira")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setColor(0xFF3B82F6.toInt())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .build()
    }

    // Refresh the ongoing notification's text when the tunnel state changes.
    private fun updateNotification(text: String) {
        if (!running) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            nm.notify(NOTIF_ID, buildNotification(text))
        } catch (_: Exception) {
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────
    private inline fun forEach(arr: org.json.JSONArray?, body: (String) -> Unit) {
        if (arr == null) return
        for (i in 0 until arr.length()) {
            val v = arr.optString(i)
            if (v.isNotBlank()) body(v)
        }
    }

    private fun splitCidr(cidr: String): Pair<String, Int> {
        val parts = cidr.trim().split("/")
        val ip = parts[0]
        val prefix = parts.getOrNull(1)?.toIntOrNull()
            ?: if (ip.contains(":")) 128 else 32
        return ip to prefix
    }

    private fun sleep(ms: Long) = try { Thread.sleep(ms) } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
    }

    companion object {
        private const val TAG = "Osmira/Vpn"
        const val ACTION_CONNECT = "osmi.awg2.CONNECT"
        const val ACTION_DISCONNECT = "osmi.awg2.DISCONNECT"
        const val EXTRA_PAYLOAD = "payload"
        private const val CHANNEL_ID = "osmira_vpn"
        private const val NOTIF_ID = 1001
        private const val STALL_SECONDS = 180L
    }
}
