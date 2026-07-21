package osmi.awg2

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle

/**
 * Invisible bridge activity used by [AwgTileService] to start the tunnel.
 *
 * Android 12+ forbids starting a foreground service straight from a tile's
 * onClick (ForegroundServiceStartNotAllowedException), but starting one from a
 * visible activity is always allowed. This translucent, no-UI activity is that
 * visible context: it also owns the one-time VPN consent dialog, then starts
 * the service and finishes immediately, so the user just sees the shade close.
 */
class TileActionActivity : Activity() {

    private var pendingPayload: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val payload = TileConfigStore.load(this)
        if (payload == null) {
            openApp()
            finish()
            return
        }
        val consent = VpnService.prepare(this)
        if (consent != null) {
            pendingPayload = payload
            try {
                startActivityForResult(consent, REQ_CONSENT)
            } catch (_: Exception) {
                openApp()
                finish()
            }
        } else {
            startTunnel(payload)
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CONSENT && resultCode == Activity.RESULT_OK) {
            pendingPayload?.let { startTunnel(it) }
        }
        pendingPayload = null
        finish()
    }

    private fun startTunnel(payload: String) {
        val intent = Intent(this, AwgVpnService::class.java)
            .setAction(AwgVpnService.ACTION_CONNECT)
            .putExtra(AwgVpnService.EXTRA_PAYLOAD, payload)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun openApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return
        try {
            startActivity(launch)
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val REQ_CONSENT = 8001
    }
}
