package osmi.awg2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
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
    @Volatile private var generation = 0

    /**
     * Set once the system takes our VPN slot away — the user started another VPN
     * app or cleared our consent. Android allows exactly one active VPN, so any
     * attempt to re-establish here would kick the other client out, which then
     * re-establishes and kicks us out in turn: both apps ping-pong forever. So a
     * revoke is final, and only a fresh user-initiated connect clears it.
     */
    @Volatile private var revoked = false

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
                // A user-initiated connect comes with fresh consent, so this is
                // the one place a previous revoke is forgiven.
                revoked = false
                startForegroundNotification()
                Thread({ connect(JSONObject(raw)) }, "AwgConnect").start()
                // STICKY so the OS restarts us after being killed in background.
                return START_STICKY
            }
            else -> {
                // Restarted by the system (START_STICKY with null intent) or
                // Always-on VPN. Try to bring the last tunnel back up, but only
                // while the VPN slot is still ours.
                val cfg = payload
                if (cfg != null && !revoked && hasVpnConsent()) {
                    startForegroundNotification()
                    // System/always-on restart: keep retrying rather than erroring.
                    Thread({ connect(cfg, initial = false) }, "AwgReconnect").start()
                    return START_STICKY
                }
                stopSelf()
                return START_NOT_STICKY
            }
        }
    }

    private fun connect(cfg: JSONObject, initial: Boolean = true) {
        synchronized(lock) {
            try {
                if (handle != -1) return
                // A revoke may have landed while this thread was queued on the
                // lock; taking the tunnel back now would restart the ping-pong.
                if (revoked) {
                    logw("connect aborted: VPN slot was revoked")
                    return
                }
                payload = cfg
                // Remember the last user-initiated tunnel so the quick-settings
                // tile can bring it back up from cold (stored encrypted).
                if (initial) TileConfigStore.save(applicationContext, cfg.toString())
                // Config summary — deliberately excludes "uapi" (private key).
                logd(
                    "connect id=${cfg.optString("id")} name=${cfg.optString("name")} " +
                        "mtu=${cfg.optInt("mtu", 1280)} dns=${cfg.optJSONArray("dns")} " +
                        "routes=${cfg.optJSONArray("routes")?.length()} " +
                        "peerCount=${cfg.optInt("peerCount", 1)} " +
                        "routingMode=${cfg.optString("routingMode")} " +
                        "apps=${cfg.optJSONArray("apps")?.length() ?: 0}",
                )
                AwgVpnState.update("connecting", id = cfg.optString("id"))

                val tunFd = establishTun(cfg) ?: run {
                    // `establish()` returns null once the slot belongs to someone
                    // else, so name the real cause instead of blaming the TUN.
                    val busy = !hasVpnConsent()
                    if (busy) revoked = true
                    AwgVpnState.update(
                        "error",
                        error = if (busy) "Слот VPN занят другим приложением"
                        else "Не удалось создать TUN",
                    )
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
                startPoller(cfg.optString("id"), initial)
                logd("tunnel up: ${GoBackend.awgVersion()}")
            } catch (e: Throwable) {
                loge("connect failed", e)
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

        val mtu = cfg.optInt("mtu", 1280)
        builder.setMtu(mtu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) setUnderlyingNetworks(null)
        builder.setBlocking(true)

        logd(
            "tun mtu=$mtu defaultRoute=$sawDefaultRoute peerCount=$peerCount " +
                "killSwitch=${sawDefaultRoute && peerCount == 1}",
        )

        val pfd = builder.establish() ?: return null
        tun = pfd
        return pfd.detachFd()
    }

    private fun startPoller(id: String?, initial: Boolean) {
        val gen = ++generation
        poller = Thread({
            val connectStartMs = System.currentTimeMillis()
            var connectedReported = false
            var prevRx = 0L
            var prevTx = 0L
            // Wall-clock of the last time downlink (rx) actually advanced, used to
            // spot a "video frozen" stall: uplink keeps moving (requests /
            // retransmits) while nothing comes back.
            var lastRxProgressMs = System.currentTimeMillis()
            var rxStallReported = false
            while (running && gen == generation && !Thread.currentThread().isInterrupted) {
                val stats = readStats()
                if (stats == null) {
                    sleep(POLL_MS); continue
                }
                val (rx, tx, hs) = stats
                val nowMs = System.currentTimeMillis()
                val nowSec = nowMs / 1000
                val age = if (hs > 0) nowSec - hs else Long.MAX_VALUE
                val drx = rx - prevRx
                val dtx = tx - prevTx
                if (drx > 0) {
                    lastRxProgressMs = nowMs
                    rxStallReported = false
                }
                val rxIdleMs = nowMs - lastRxProgressMs

                // A revoke or teardown can land mid-iteration. Publishing after
                // that would overwrite the final "disconnected" with a stale
                // "connecting" and leave the UI spinning on a dead tunnel.
                if (!running || gen != generation) return@Thread

                if (hs > 0) {
                    if (!connectedReported) {
                        connectedReported = true
                        updateNotification("Подключено")
                    }
                    AwgVpnState.update("connected", id, rx, tx, hs)
                } else {
                    AwgVpnState.update("connecting", id, rx, tx, 0)
                }

                // Give up on an initial (user-initiated) connect that never gets
                // a handshake — server down / wrong endpoint / blocked port. This
                // is what otherwise spins "Подключение…" forever. Auto-reconnects
                // (initial=false) keep retrying so a brief outage doesn't kill an
                // always-on tunnel; either way the user can cancel from the UI.
                if (initial && !connectedReported &&
                    nowMs - connectStartMs > CONNECT_TIMEOUT_MS
                ) {
                    logw("connect timeout: no handshake in ${CONNECT_TIMEOUT_MS / 1000}s")
                    AwgVpnState.update(
                        "error",
                        id = id,
                        error = "Не удалось подключиться — сервер недоступен",
                    )
                    updateNotification("Не удалось подключиться")
                    teardown(stopService = true, announce = false)
                    return@Thread
                }

                if (BuildConfig.DEBUG) {
                    logd(
                        "poll rx=$rx(+$drx) tx=$tx(+$dtx) " +
                            "hsAge=${if (age == Long.MAX_VALUE) "-" else "${age}s"} " +
                            "rxIdle=${rxIdleMs / 1000}s",
                    )
                    // The signature of a YouTube-style hang: we're still sending
                    // (dtx > 0) but the downlink has been dead for a while and the
                    // handshake is still fresh (so it's NOT a dead tunnel — likely
                    // an MTU/path-MSS blackhole dropping large packets).
                    if (connectedReported && !rxStallReported && dtx > 0 && drx == 0L &&
                        rxIdleMs > RX_STALL_MS && age < STALL_SECONDS
                    ) {
                        rxStallReported = true
                        logw(
                            "RX-STALL: downlink frozen ${rxIdleMs / 1000}s while uplink " +
                                "active (+$dtx tx), handshake fresh (${age}s). " +
                                "Classic MTU/MSS blackhole — video buffering will hang.",
                        )
                    }
                }

                // Stall detection: healthy handshakes refresh every ~2 min.
                if (connectedReported && age != Long.MAX_VALUE && age > STALL_SECONDS) {
                    logw("handshake stale (${age}s) — reconnecting")
                    scheduleRestart("handshake-stale-${age}s")
                    return@Thread
                }

                prevRx = rx
                prevTx = tx
                sleep(POLL_MS)
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

    private fun scheduleRestart(reason: String) {
        if (!running || revoked) return
        if (!restarting.compareAndSet(false, true)) return
        val gen = generation
        logw("scheduleRestart reason=$reason")
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
                sleep(RESTART_DELAY_MS)
                // The tunnel may have been revoked or torn down while we slept;
                // `generation` moves on both a teardown and a newer poller.
                if (revoked || !running || generation != gen) {
                    logw("restart dropped (revoked=$revoked running=$running)")
                    return@Thread
                }
                // A stalled tunnel and a hijacked tunnel look identical from the
                // handshake counter, so confirm the VPN slot is still ours before
                // reconnecting. Without this the stall detector keeps re-arming
                // against a slot another client now owns.
                if (!hasVpnConsent()) {
                    yieldToOtherVpn()
                    return@Thread
                }
                connect(cfg, initial = false)
            } finally {
                restarting.set(false)
            }
        }, "AwgRestart").start()
    }

    /**
     * True while we still hold the system's single VPN slot. `prepare` returns a
     * consent intent once another app has taken it over. Failures are treated as
     * "still ours" so a quirky ROM can't block legitimate reconnects.
     */
    private fun hasVpnConsent(): Boolean =
        try {
            VpnService.prepare(this) == null
        } catch (e: Throwable) {
            logw("prepare() check failed", e)
            true
        }

    /**
     * Stand down for another VPN client. Reported as a plain disconnect rather
     * than an error: the user deliberately started the other VPN, so there is
     * nothing here for them to fix.
     */
    private fun yieldToOtherVpn() {
        revoked = true
        logw("another VPN client owns the tunnel — standing down")
        teardown(stopService = true)
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
                logd("underlying network changed: $network")
                if (running) scheduleRestart("network-changed")
            }
        }
        netCallback = cb
        try {
            cm.registerNetworkCallback(request, cb)
        } catch (e: Exception) {
            logw("network callback registration failed", e)
            netCallback = null
        }
    }

    private fun teardown(stopService: Boolean, announce: Boolean = true) {
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
        if (announce) AwgVpnState.update("disconnected")
        if (stopService) {
            stopForegroundCompat()
            stopSelf()
        }
    }

    override fun onRevoke() {
        // Another VPN app took the slot, or the user cleared our consent. Flag it
        // and stop the poller before anything else: the flags are what stop an
        // in-flight restart from grabbing the tunnel back.
        revoked = true
        running = false
        generation++
        logw("VPN slot revoked — yielding")
        // teardown() waits on the lock a running connect() may still hold, so it
        // must not run on the main thread.
        Thread({ teardown(stopService = true) }, "AwgRevoke").start()
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
            // Full-colour brand mark shown inside the push (large icons aren't
            // tinted, unlike the monochrome status-bar small icon).
            .setLargeIcon(Icon.createWithResource(this, R.drawable.ic_notification_large))
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

    // ── debug-only logging ───────────────────────────────────────────────
    // Every call is compiled to run only in debug builds; in release the guard
    // short-circuits before any string is built, so logging is fully inert.
    private fun logd(msg: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, msg)
    }

    private fun logw(msg: String, e: Throwable? = null) {
        if (BuildConfig.DEBUG) Log.w(TAG, msg, e)
    }

    private fun loge(msg: String, e: Throwable? = null) {
        if (BuildConfig.DEBUG) Log.e(TAG, msg, e)
    }

    companion object {
        private const val TAG = "Osmira/Vpn"
        const val ACTION_CONNECT = "osmi.awg2.CONNECT"
        const val ACTION_DISCONNECT = "osmi.awg2.DISCONNECT"
        const val EXTRA_PAYLOAD = "payload"
        private const val CHANNEL_ID = "osmira_vpn"
        private const val NOTIF_ID = 1001
        private const val STALL_SECONDS = 180L
        private const val POLL_MS = 2000L
        // Breather between tearing the old tunnel down and dialling again, so the
        // socket and route churn settles first.
        private const val RESTART_DELAY_MS = 600L
        // Max time an initial connect may sit without a handshake before we give
        // up and report an error (instead of spinning "Подключение…" forever).
        private const val CONNECT_TIMEOUT_MS = 20000L
        // How long the downlink can be idle (while uplink is active) before we
        // flag a probable video-hang / MTU blackhole in the logs.
        private const val RX_STALL_MS = 8000L
    }
}
