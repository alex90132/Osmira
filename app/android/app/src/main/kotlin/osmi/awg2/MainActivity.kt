package osmi.awg2

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private var statusListener: ((Map<String, Any?>) -> Unit)? = null
    private var importChannel: MethodChannel? = null
    private var pendingPrepare: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingImport: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Runtime hardening (anti-tamper + anti-frida). No-op in debug; in
        // release a failed check kills the process before super.onCreate so
        // instrumentation can't hook the engine/VPN setup.
        if (!SecurityChecks.runStartupChecks(this, BuildConfig.DEBUG)) return
        super.onCreate(savedInstanceState)
        ensureNotificationPermission()
    }

    // On Android 13+ the foreground-service notification (our connection push)
    // is silently suppressed unless POST_NOTIFICATIONS is granted at runtime.
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        try {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIF,
            )
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> handlePrepare(result)
                "connect" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) { result.error("bad_args", "no payload", null); return@setMethodCallHandler }
                    startVpn(JSONObject(args as Map<String, Any?>).toString())
                    result.success(null)
                }
                "disconnect" -> {
                    val intent = Intent(this, AwgVpnService::class.java)
                        .setAction(AwgVpnService.ACTION_DISCONNECT)
                    startService(intent)
                    result.success(null)
                }
                "status" -> result.success(AwgVpnState.current())
                "listApps" -> {
                    val includeSystem = (call.argument<Boolean>("includeSystem")) ?: false
                    // Enumerating packages + rasterizing icons is heavy; do it
                    // off the main thread and marshal the result back.
                    Thread({
                        val apps = try {
                            listApps(includeSystem)
                        } catch (e: Exception) {
                            null
                        }
                        runOnUiThread {
                            if (apps != null) result.success(apps)
                            else result.error("list_failed", "listApps failed", null)
                        }
                    }, "AwgListApps").start()
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, STATUS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val l: (Map<String, Any?>) -> Unit = { events.success(it) }
                    statusListener = l
                    AwgVpnState.addListener(l)
                }
                override fun onCancel(arguments: Any?) {
                    statusListener?.let { AwgVpnState.removeListener(it) }
                    statusListener = null
                }
            },
        )

        importChannel = MethodChannel(messenger, IMPORT_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitial" -> {
                        result.success(pendingImport)
                        pendingImport = null
                    }
                    "pickFile" -> handlePickFile(result)
                    else -> result.notImplemented()
                }
            }
        }

        // Capture the intent that launched us (file tap / vpn:// link).
        pendingImport = extractImport(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = extractImport(intent) ?: return
        val ch = importChannel
        if (ch != null) ch.invokeMethod("onImport", payload) else pendingImport = payload
    }

    // ── VPN consent ──────────────────────────────────────────────────────
    private fun handlePrepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare = result
        try {
            startActivityForResult(intent, REQ_PREPARE)
        } catch (e: Exception) {
            pendingPrepare = null
            result.error("prepare_failed", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_PREPARE -> {
                pendingPrepare?.success(resultCode == Activity.RESULT_OK)
                pendingPrepare = null
            }
            REQ_PICK -> {
                val res = pendingPick
                pendingPick = null
                val uri = data?.data
                if (res == null) return
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    res.success(null)
                    return
                }
                val text = readTextFromUri(uri)
                if (text == null) {
                    res.success(null)
                } else {
                    res.success(mapOf("name" to (displayName(uri) ?: ""), "text" to text))
                }
            }
        }
    }

    // ── document picker (SAF) ────────────────────────────────────────────
    private fun handlePickFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "a pick is already in progress", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        pendingPick = result
        try {
            startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("pick_failed", e.message, null)
        }
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
        }
    } catch (e: Exception) {
        null
    }

    private fun startVpn(payloadJson: String) {
        val intent = Intent(this, AwgVpnService::class.java)
            .setAction(AwgVpnService.ACTION_CONNECT)
            .putExtra(AwgVpnService.EXTRA_PAYLOAD, payloadJson)
        startService(intent)
    }

    // ── import extraction ────────────────────────────────────────────────
    private fun extractImport(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return null
                when (uri.scheme?.lowercase()) {
                    "vpn" -> intent.dataString
                    "content", "file" -> readTextFromUri(uri)
                    else -> intent.dataString
                }
            }
            // Telegram/mail "Share" a .vpn file → ACTION_SEND with EXTRA_STREAM.
            Intent.ACTION_SEND -> {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                uri?.let { readTextFromUri(it) }
                    ?: intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            }
            else -> null
        }
    }

    private fun readTextFromUri(uri: Uri): String? = try {
        contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText().trim() }
    } catch (e: Exception) {
        null
    }

    // ── installed apps ───────────────────────────────────────────────────
    private fun listApps(includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(launcher, 0)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any?>>()
        for (ri in resolved) {
            val ai = ri.activityInfo?.applicationInfo ?: continue
            val pkg = ai.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && !includeSystem) continue
            out.add(
                mapOf(
                    "package" to pkg,
                    "label" to pm.getApplicationLabel(ai).toString(),
                    "system" to isSystem,
                    "icon" to iconBytes(pm.getApplicationIcon(ai)),
                ),
            )
        }
        out.sortBy { (it["label"] as String).lowercase() }
        return out
    }

    private fun iconBytes(drawable: Drawable): ByteArray? = try {
        val size = 96
        val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(b)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(c)
            b
        }
        ByteArrayOutputStream().use { s ->
            bmp.compress(Bitmap.CompressFormat.PNG, 100, s)
            s.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    companion object {
        private const val VPN_CHANNEL = "osmi.awg2/vpn"
        private const val STATUS_CHANNEL = "osmi.awg2/vpn_status"
        private const val IMPORT_CHANNEL = "osmi.awg2/import"
        private const val REQ_PREPARE = 7001
        private const val REQ_PICK = 7002
        private const val REQ_NOTIF = 7003
    }
}
