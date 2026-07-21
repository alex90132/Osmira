package osmi.awg2

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Persists the last-used connect payload so the quick-settings tile can bring
 * the tunnel up again from cold (when the app process isn't running).
 *
 * The payload embeds the WireGuard PRIVATE KEY (in its uapi string), so it is
 * NEVER written in the clear: it is sealed with an AES-256-GCM key held in the
 * hardware-backed Android Keystore (same posture as the encrypted tunnel store
 * on the Flutter side). Only this app, on this device, can decrypt it.
 */
object TileConfigStore {
    private const val PREFS = "osmira_tile"
    private const val KEY_CFG = "cfg"
    private const val KS_ALIAS = "osmira_tile_aes"
    private const val ANDROID_KS = "AndroidKeyStore"
    private const val GCM_TAG_BITS = 128

    fun save(context: Context, json: String) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_CFG, seal(json)).apply()
        } catch (_: Exception) {
            // Best-effort; the tile just won't be able to reconnect from cold.
        }
    }

    fun load(context: Context): String? {
        return try {
            val blob = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_CFG, null) ?: return null
            unseal(blob)
        } catch (_: Exception) {
            null
        }
    }

    fun hasConfig(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(KEY_CFG)

    private fun seal(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(ct, Base64.NO_WRAP)
    }

    private fun unseal(blob: String): String? {
        val parts = blob.split(":")
        if (parts.size != 2) return null
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ct = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(ct), Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KS).apply { load(null) }
        (ks.getEntry(KS_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KS)
        gen.init(
            KeyGenParameterSpec.Builder(
                KS_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }
}
