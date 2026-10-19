package com.ritvijsrivastava.aether

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Native file handling for Aether on Android:
 *  - `pickPdfs`: the system document picker; each choice is streamed into a
 *    temporary file and its path returned (nothing is loaded into memory).
 *  - PDFs sent to the app ("Open with", "Share to") are copied the same way and
 *    pushed to Dart as `file` calls once Dart says it is `ready`.
 *
 * Dart removes each temporary file after importing it.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val io = Executors.newSingleThreadExecutor()
    private val counter = AtomicInteger(0)
    private var dartReady = false
    private val queue = ArrayList<String>()
    private var pickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    flush()
                    result.success(null)
                }
                "pickPdfs" -> pick(result)
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    // --- PDFs sent to the app ---------------------------------------------------

    private fun handleIntent(intent: Intent?) {
        val uris = urisFrom(intent)
        if (uris.isEmpty()) return
        // Consume it, so recreating the activity does not import it again.
        setIntent(Intent())
        copyAll(uris) { paths ->
            synchronized(queue) { queue.addAll(paths) }
            runOnUiThread { flush() }
        }
    }

    private fun urisFrom(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        return when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(streamExtra(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)
            else -> emptyList()
        }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun flush() {
        val ch = channel ?: return
        if (!dartReady) return
        val pending = synchronized(queue) { ArrayList(queue).also { queue.clear() } }
        for (path in pending) ch.invokeMethod("file", path)
    }

    // --- Picker -----------------------------------------------------------------

    private fun pick(result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_PICK)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_PICK) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pickResult ?: return
        pickResult = null
        val uris = ArrayList<Uri>()
        if (resultCode == RESULT_OK && data != null) {
            data.data?.let { uris.add(it) }
            val clip: ClipData? = data.clipData
            if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) }
        }
        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return
        }
        copyAll(uris.distinct()) { paths -> runOnUiThread { result.success(paths) } }
    }

    // --- Copying ----------------------------------------------------------------

    private fun copyAll(uris: List<Uri>, done: (List<String>) -> Unit) {
        io.execute {
            val paths = uris.mapNotNull { copyToCache(it) }
            done(paths)
        }
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            // Each copy gets its own folder so the file keeps its real name (the
            // title of the imported document comes from it).
            val dir = File(cacheDir, "incoming/${System.currentTimeMillis()}-${counter.getAndIncrement()}")
                .apply { mkdirs() }
            val out = File(dir, displayName(uri))
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) name = it.getString(0)
            }
        }
        if (name == null) name = uri.lastPathSegment
        val safe = (name ?: "document.pdf").replace(Regex("[^A-Za-z0-9._ -]"), "_")
        return if (safe.lowercase().endsWith(".pdf")) safe else "$safe.pdf"
    }

    companion object {
        private const val CHANNEL = "com.ritvijsrivastava.aether/files"
        private const val REQ_PICK = 4711
    }
}
