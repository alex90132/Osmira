package osmi.awg2

import android.os.Handler
import android.os.Looper

/**
 * Process-wide bridge between [AwgVpnService] (which owns the tunnel) and the
 * Flutter EventChannel (which lives in [MainActivity]'s engine). Keeps the last
 * status snapshot so a freshly-attached listener is primed immediately.
 */
object AwgVpnState {
    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableListOf<(Map<String, Any?>) -> Unit>()

    @Volatile
    private var last: Map<String, Any?> = mapOf(
        "state" to "disconnected",
        "rxBytes" to 0L,
        "txBytes" to 0L,
        "lastHandshake" to 0L,
    )

    fun current(): Map<String, Any?> = last

    fun addListener(l: (Map<String, Any?>) -> Unit) {
        synchronized(listeners) { listeners.add(l) }
        // Prime the new listener with the latest known state.
        main.post { l(last) }
    }

    fun removeListener(l: (Map<String, Any?>) -> Unit) {
        synchronized(listeners) { listeners.remove(l) }
    }

    fun publish(status: Map<String, Any?>) {
        last = status
        val snapshot = synchronized(listeners) { listeners.toList() }
        main.post { snapshot.forEach { it(status) } }
    }

    fun update(
        state: String,
        id: String? = null,
        rxBytes: Long = (last["rxBytes"] as? Long) ?: 0L,
        txBytes: Long = (last["txBytes"] as? Long) ?: 0L,
        lastHandshake: Long = (last["lastHandshake"] as? Long) ?: 0L,
        error: String? = null,
    ) {
        publish(
            mapOf(
                "state" to state,
                "id" to id,
                "rxBytes" to rxBytes,
                "txBytes" to txBytes,
                "lastHandshake" to lastHandshake,
                "error" to error,
            ),
        )
    }
}
