package com.jrpbone.karaok

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.content.pm.ApplicationInfo
import android.os.Build
import android.provider.MediaStore
import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.InputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private class AudioPick(val result: MethodChannel.Result) {
        val cancellation = CancellationSignal()
        @Volatile var stopped = false
        @Volatile var copy: File? = null
        @Volatile var input: InputStream? = null
        var deadline: Runnable? = null
    }
    private var audioPick: AudioPick? = null
    private val audioWorker = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val maxAudioBytes = 25L * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "karaok/audio_picker")
            .setMethodCallHandler { call, result ->
                if (call.method == "publishPickerTestFixture" &&
                    applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Integration tests generate audio in app cache, then publish
                    // it to Downloads so the real document picker can select it.
                    val source = File(call.argument<String>("path") ?: "").canonicalFile
                    val name = call.argument<String>("name") ?: ""
                    if (!source.path.startsWith(cacheDir.canonicalPath + File.separator) ||
                        !name.matches(Regex("karaok-picker-[a-z0-9-]+\\.(wav|mp3)"))) {
                        result.error("invalid_fixture", "Invalid picker test fixture.", null)
                        return@setMethodCallHandler
                    }
                    audioWorker.execute {
                        var published: android.net.Uri? = null
                        try {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, name)
                                put(MediaStore.Downloads.MIME_TYPE, if (name.endsWith(".wav")) "audio/wav" else "audio/mpeg")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: error("Could not publish fixture")
                            published = uri
                            contentResolver.openOutputStream(uri)!!.use { output ->
                                source.inputStream().use { it.copyTo(output) }
                            }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            runOnUiThread { result.success(uri.toString()) }
                        } catch (error: Exception) {
                            published?.let { contentResolver.delete(it, null, null) }
                            runOnUiThread { result.error("fixture_failed", "Could not publish picker test fixture.", null) }
                        }
                    }
                } else if (call.method == "deletePickerTestFixture" &&
                    applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val uri = android.net.Uri.parse(call.argument<String>("uri") ?: "")
                    if (!uri.toString().startsWith(MediaStore.Downloads.EXTERNAL_CONTENT_URI.toString() + "/")) {
                        result.error("invalid_fixture", "Invalid picker test fixture.", null)
                    } else {
                        contentResolver.delete(uri, null, null)
                        result.success(null)
                    }
                } else if (call.method != "pickAudio") {
                    result.notImplemented()
                } else if (audioPick != null) {
                    result.error("busy", "A file selection is already open.", null)
                } else {
                    audioPick = AudioPick(result)
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivityForResult(intent, 47301)
                    } catch (error: Exception) {
                        audioPick = null
                        result.error("picker_unavailable", "Could not open the audio picker.", null)
                    }
                }
            }
    }

    @Deprecated("Activity result bridge for Flutter's document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 47301) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pick = audioPick ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            audioPick = null
            pick.result.success(null)
            return
        }
        // The user's time in the picker is unlimited. Provider I/O starts here
        // and has a deadline so a stalled cloud provider cannot wedge picking.
        pick.deadline = Runnable {
            if (audioPick === pick) {
                audioPick = null
                abandon(pick)
                pick.result.error("audio_timeout", "Reading the audio took too long. Please try another file.", null)
            }
        }.also { mainHandler.postDelayed(it, 30_000) }
        audioWorker.execute {
            try {
                var name = "selected_audio"
                var size: Long? = null
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null, pick.cancellation)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (nameColumn >= 0 && !cursor.isNull(nameColumn)) name = cursor.getString(nameColumn)
                        if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) size = cursor.getLong(sizeColumn)
                    }
                }
                ensureActive(pick)
                // Metadata is checked before opening the content stream. Providers
                // without a size are still bounded by the copy loop below.
                if (size != null && size!! > maxAudioBytes) throw AudioTooLarge()
                if (size == 0L) throw IllegalArgumentException("The audio file is empty.")
                val extension = name.substringAfterLast('.', "").lowercase()
                if (extension !in setOf("wav", "mp3", "m4a", "aac", "ogg", "flac")) {
                    throw IllegalArgumentException("This audio format is not supported.")
                }
                val directory = File(cacheDir, "karaok_audio_picker").apply { mkdirs() }
                // Only sweep our own abandoned cache files, never source media.
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                directory.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }?.forEach { it.delete() }
                val destination = File.createTempFile("audio-", ".$extension", directory)
                pick.copy = destination
                ensureActive(pick)
                var count = 0L
                contentResolver.openInputStream(uri)?.use { input ->
                    pick.input = input
                    ensureActive(pick)
                    destination.outputStream().use { output ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            ensureActive(pick)
                            val read = input.read(buffer)
                            ensureActive(pick)
                            if (read < 0) break
                            count += read
                            if (count > maxAudioBytes) throw AudioTooLarge()
                            output.write(buffer, 0, read)
                        }
                    }
                } ?: throw IllegalArgumentException("Could not open the audio file.")
                if (count == 0L) throw IllegalArgumentException("The audio file is empty.")
                runOnUiThread {
                    if (audioPick === pick && !pick.stopped) {
                        pick.deadline?.let { mainHandler.removeCallbacks(it) }
                        audioPick = null
                        pick.result.success(mapOf("path" to destination.path, "name" to name, "size" to count))
                    } else {
                        destination.delete()
                    }
                }
            } catch (error: Exception) {
                pick.copy?.delete()
                val message = when (error) {
                    is AudioTooLarge -> "The audio file exceeds the 25 MB limit."
                    is IllegalArgumentException -> error.message ?: "Could not read the audio file."
                    else -> "Could not read the audio file. Please try another file."
                }
                runOnUiThread {
                    if (audioPick === pick && !pick.stopped) {
                        pick.deadline?.let { mainHandler.removeCallbacks(it) }
                        audioPick = null
                        pick.result.error("audio_selection_failed", message, null)
                    }
                }
            } finally {
                pick.input = null
            }
        }
    }

    private fun abandon(pick: AudioPick) {
        pick.stopped = true
        pick.deadline?.let { mainHandler.removeCallbacks(it) }
        // Cancellation/close may involve a provider; keep both off the UI thread.
        audioWorker.execute {
            try { pick.cancellation.cancel() } catch (_: Exception) { }
        }
        audioWorker.execute {
            pick.copy?.delete()
            try { pick.input?.close() } catch (_: Exception) { }
            finally { pick.copy?.delete() }
        }
    }

    private fun ensureActive(pick: AudioPick) {
        check(!pick.stopped) { "Audio selection cancelled" }
        pick.cancellation.throwIfCanceled()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioPick?.let { abandon(it) }
        audioPick = null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "karaok/audio_picker").setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private class AudioTooLarge : Exception()
}
