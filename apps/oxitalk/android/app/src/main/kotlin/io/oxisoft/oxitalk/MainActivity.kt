package io.oxisoft.oxitalk

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The app, and the target of Android's share sheet: what another app shares (files, images,
 * videos, text, links) is copied into the app's cache, since the content:// grant ends with
 * the share, and handed to Flutter on the "io.oxisoft.oxitalk/share" channel: Flutter asks
 * with takeShared; sharedArrived tells it something came while it runs.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val copier = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Copied paths and text waiting for Flutter; touched on the main thread only. */
    private val pendingPaths = mutableListOf<String>()
    private var pendingText = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShared" -> result.success(takePending())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not again when Android recreates the activity (rotation, back from the background).
        if (savedInstanceState == null) receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    override fun onDestroy() {
        copier.shutdown()
        super.onDestroy()
    }

    private fun takePending(): Map<String, Any>? {
        if (pendingPaths.isEmpty() && pendingText.isEmpty()) return null
        val shared = mapOf("paths" to pendingPaths.toList(), "text" to pendingText)
        pendingPaths.clear()
        pendingText = ""
        return shared
    }

    private fun receive(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = sharedUris(intent, action)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim() ?: ""
        // Handled once: a later recreation of the activity must not share it again.
        intent.action = Intent.ACTION_MAIN
        if (uris.isEmpty() && text.isEmpty()) return
        copier.execute {
            val paths = copyToCache(uris)
            main.post {
                pendingPaths.addAll(paths)
                if (text.isNotEmpty()) {
                    pendingText = if (pendingText.isEmpty()) text else "$pendingText\n$text"
                }
                channel?.invokeMethod("sharedArrived", null)
            }
        }
    }

    private fun sharedUris(intent: Intent, action: String): List<Uri> {
        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::add)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                ?.let(uris::addAll)
        }
        // Some apps put the files only in the clip data.
        if (uris.isEmpty()) {
            val clip = intent.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add)
            }
        }
        return uris.distinct()
    }

    /** Copies [uris] into cache/shared/<time>/, each under its own name; old shares go. */
    private fun copyToCache(uris: List<Uri>): List<String> {
        if (uris.isEmpty()) return emptyList()
        val root = File(cacheDir, "shared")
        val dayAgo = System.currentTimeMillis() - 24 * 60 * 60 * 1000
        root.listFiles()?.filter { it.lastModified() < dayAgo }?.forEach { it.deleteRecursively() }
        val dir = File(root, System.currentTimeMillis().toString())
        dir.mkdirs()
        val paths = mutableListOf<String>()
        for ((index, uri) in uris.withIndex()) {
            try {
                // Only content the sharing app grants; never a file:// path into our own data.
                if (uri.scheme != "content") continue
                val name = safeName(displayName(uri) ?: "shared-${index + 1}")
                var file = File(dir, name)
                var n = 1
                while (file.exists()) file = File(dir, "${n++}-$name")
                val input = contentResolver.openInputStream(uri) ?: continue
                input.use { stream -> file.outputStream().use { stream.copyTo(it) } }
                paths.add(file.absolutePath)
            } catch (e: Exception) {
                Log.w("OxiTalk", "Can't copy a shared file: ${e.javaClass.simpleName}")
            }
        }
        return paths
    }

    private fun displayName(uri: Uri): String? {
        val name = try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
                }
        } catch (e: Exception) {
            null
        }
        return name ?: uri.lastPathSegment
    }

    private fun safeName(name: String): String {
        val safe = name.substringAfterLast('/')
            .replace(Regex("[\\\\:*?\"<>|\\x00-\\x1f]"), "_")
            .trim()
        return if (safe.isEmpty() || safe == "." || safe == "..") "file" else safe
    }

    companion object {
        private const val CHANNEL = "io.oxisoft.oxitalk/share"
    }
}
