package osmi.awg2

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick-settings tile that mirrors and controls the tunnel, just like the
 * AmneziaVPN tile: tap to connect the last-used profile, tap again to
 * disconnect. State is read from the process-wide [AwgVpnState] so the tile
 * always reflects what the service is doing, whether the toggle came from here
 * or from the app UI.
 */
class AwgTileService : TileService() {

    private val listener: (Map<String, Any?>) -> Unit = { refresh(it) }

    override fun onStartListening() {
        super.onStartListening()
        AwgVpnState.addListener(listener)
        refresh(AwgVpnState.current())
    }

    override fun onStopListening() {
        AwgVpnState.removeListener(listener)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val state = AwgVpnState.current()["state"] as? String ?: "disconnected"
        if (isActive(state)) {
            disconnect()
        } else {
            connect()
        }
    }

    private fun connect() {
        // No saved profile yet → open the app so the user picks/imports one.
        if (!TileConfigStore.hasConfig(this)) {
            collapseTo(launchIntent())
            return
        }
        // Bounce through the invisible bridge activity: FGS start (and the VPN
        // consent dialog, if needed) are only permitted from a visible context.
        collapseTo(
            Intent(this, TileActionActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        // Optimistic feedback; the state stream will correct it shortly.
        setTile("connecting")
    }

    private fun disconnect() {
        // The service is already running/foreground, so delivering a stop
        // command via startService is allowed even from the shade.
        val intent = Intent(this, AwgVpnService::class.java)
            .setAction(AwgVpnService.ACTION_DISCONNECT)
        try {
            startService(intent)
        } catch (_: Exception) {
        }
        setTile("disconnected")
    }

    private fun launchIntent(): Intent? =
        packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun collapseTo(intent: Intent?) {
        if (intent == null) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pi = PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        } catch (_: Exception) {
        }
    }

    private fun refresh(status: Map<String, Any?>) {
        setTile(status["state"] as? String ?: "disconnected")
    }

    private fun setTile(state: String) {
        val tile = qsTile ?: return
        val active = isActive(state)
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Osmira"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when (state) {
                "connected" -> "Подключено"
                "connecting" -> "Подключение…"
                "reconnecting" -> "Переподключение…"
                "error" -> "Ошибка"
                else -> "Отключено"
            }
        }
        try {
            tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_vpn)
        } catch (_: Exception) {
        }
        tile.updateTile()
    }

    private fun isActive(state: String): Boolean =
        state == "connected" || state == "connecting" || state == "reconnecting"
}
