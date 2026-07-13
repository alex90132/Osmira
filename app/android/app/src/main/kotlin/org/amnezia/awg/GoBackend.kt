package org.amnezia.awg

/**
 * JNI bridge to the pre-built `libwg-go.so` (amneziawg-go).
 *
 * The native symbols are hard-coded in `jni.c` as
 * `Java_org_amnezia_awg_GoBackend_*`, so this class MUST stay in package
 * `org.amnezia.awg` with class name `GoBackend` and static methods —
 * independent of the app's `applicationId` (osmi.awg2).
 */
object GoBackend {
    init {
        System.loadLibrary("wg-go")
    }

    /** Brings a tunnel up. Returns a handle (>= 0) or a negative error code. */
    @JvmStatic
    external fun awgTurnOn(ifName: String, tunFd: Int, settings: String): Int

    @JvmStatic
    external fun awgTurnOff(handle: Int)

    @JvmStatic
    external fun awgGetSocketV4(handle: Int): Int

    @JvmStatic
    external fun awgGetSocketV6(handle: Int): Int

    /** Returns the current uapi config dump (with rx/tx/handshake counters). */
    @JvmStatic
    external fun awgGetConfig(handle: Int): String?

    @JvmStatic
    external fun awgVersion(): String?
}
