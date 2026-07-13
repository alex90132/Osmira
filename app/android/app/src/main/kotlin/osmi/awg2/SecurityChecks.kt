package osmi.awg2

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

/**
 * Runtime hardening, modelled on ritmik's `SecurityChecks`. Two checks:
 *
 *  1. **Anti-tampering (signature pinning)** — the sha256 fingerprint of the
 *     running APK's signing certificate is compared against a hard-coded
 *     reference. If someone repacks/re-signs Osmira (to inject telemetry,
 *     strip stealth, add ads) the fingerprint won't match.
 *
 *  2. **Frida detection** — scans `/proc/self/maps` for Frida gadget/server
 *     markers. Frida is the go-to tool for hooking calls / stealing the
 *     WireGuard keys or tunnel config at runtime.
 *
 * Both are **silent no-ops in debug builds** (BuildConfig.DEBUG) and **hard**
 * in release: on trip the process is killed instantly, giving the attacker no
 * hint which check fired.
 *
 * The reference fingerprint is stored as a raw byte array (not a hex string)
 * so R8 can't fold it and a SMALI decompile shows only opaque bytes.
 */
internal object SecurityChecks {

    /**
     * SHA-256 of the release signing certificate (osmira-release.jks, alias
     * `osmira`). Regenerate this array if the keystore changes:
     *   keytool -list -v -keystore osmira-release.jks -alias osmira
     */
    private val RELEASE_SIGNATURE_SHA256: ByteArray = byteArrayOf(
        0x5E.toByte(), 0x8F.toByte(), 0x5A.toByte(), 0xFD.toByte(),
        0x00.toByte(), 0xFD.toByte(), 0x0D.toByte(), 0x82.toByte(),
        0x13.toByte(), 0x00.toByte(), 0x2A.toByte(), 0x98.toByte(),
        0x5E.toByte(), 0x6C.toByte(), 0x08.toByte(), 0x16.toByte(),
        0xD4.toByte(), 0x25.toByte(), 0x1D.toByte(), 0x61.toByte(),
        0x62.toByte(), 0xB6.toByte(), 0x11.toByte(), 0x16.toByte(),
        0xED.toByte(), 0x8A.toByte(), 0xB8.toByte(), 0xEA.toByte(),
        0xB0.toByte(), 0xBC.toByte(), 0x2C.toByte(), 0x0D.toByte(),
    )

    /**
     * Runs both checks. Call from `MainActivity.onCreate` *before*
     * super.onCreate — the earlier, the less an attacker can swap out.
     *
     * @return true if OK; false means a check failed and the process is being
     *         killed.
     */
    fun runStartupChecks(context: Context, isDebugBuild: Boolean): Boolean {
        if (isDebugBuild) return true

        // No logging on trip: the attacker must get zero hint about which check
        // fired (see class doc) — just kill the process silently.
        if (!verifySignature(context)) {
            killSelf()
            return false
        }
        if (detectFrida()) {
            killSelf()
            return false
        }
        return true
    }

    @SuppressLint("PackageManagerGetSignatures")
    private fun verifySignature(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            val pkg = context.packageName
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES)
                val signingInfo = info.signingInfo ?: return false
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures
            } ?: return false

            val md = MessageDigest.getInstance("SHA-256")
            for (sig in signatures) {
                if (sig == null) continue
                val digest = md.digest(sig.toByteArray())
                if (digest.contentEquals(RELEASE_SIGNATURE_SHA256)) return true
            }
            false
        } catch (_: Throwable) {
            // Any PackageManager failure → refuse rather than pass a tampered APK.
            false
        }
    }

    private fun detectFrida(): Boolean {
        return try {
            val markers = arrayOf(
                buildMarkerFridaGadget(),
                buildMarkerFridaAgent(),
                buildMarkerGumJs(),
                buildMarkerLinjector(),
            )
            val maps = File("/proc/self/maps")
            if (!maps.exists() || !maps.canRead()) return false
            maps.bufferedReader().useLines { lines ->
                for (line in lines) {
                    for (m in markers) {
                        if (line.contains(m)) return true
                    }
                }
            }
            false
        } catch (_: Throwable) {
            false
        }
    }

    private fun killSelf() {
        try {
            android.os.Process.killProcess(android.os.Process.myPid())
        } catch (_: Throwable) {
        }
        kotlin.system.exitProcess(10)
    }

    // Markers assembled from char codes so `strings classes.dex` won't reveal them.
    private fun buildMarkerFridaGadget(): String =
        String(charArrayOf('f', 'r', 'i', 'd', 'a', '-', 'g', 'a', 'd', 'g', 'e', 't'))

    private fun buildMarkerFridaAgent(): String =
        String(charArrayOf('f', 'r', 'i', 'd', 'a', '-', 'a', 'g', 'e', 'n', 't'))

    private fun buildMarkerGumJs(): String =
        String(charArrayOf('g', 'u', 'm', '-', 'j', 's', '-', 'l', 'o', 'o', 'p'))

    private fun buildMarkerLinjector(): String =
        String(charArrayOf('l', 'i', 'n', 'j', 'e', 'c', 't', 'o', 'r'))
}
