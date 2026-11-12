package io.oxisoft.oxitalk

import android.content.Context

/**
 * Gives the Rust core Android's certificate checking: the SDK's HTTPS client verifies servers
 * with the system trust manager through rustls-platform-verifier, which needs the app's
 * context before the first request. Without it signing in crashed in the core
 * ("Expect rustls-platform-verifier to be initialized").
 */
object TlsInit {
    @Volatile private var done = false

    @Synchronized
    fun ensure(context: Context) {
        if (done) return
        // The core Dart loads later; loading it here first is harmless, it is the same library.
        System.loadLibrary("oxitalk_core")
        init(context.applicationContext)
        done = true
    }

    @JvmStatic private external fun init(context: Context)
}
