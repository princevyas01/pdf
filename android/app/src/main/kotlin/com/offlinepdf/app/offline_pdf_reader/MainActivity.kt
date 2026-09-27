package com.offlinepdf.app.offline_pdf_reader

import android.content.Intent
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val TAG = "PdfIntent"
    private val CHANNEL = "com.offlinepdf.app/intent"
    private var pendingPayload: Map<String, Any?>? = null
    private var methodChannel: MethodChannel? = null
    private var dartIntentHandlerReady = false
    private val executor = Executors.newSingleThreadExecutor()
    private var mediaStoreObserver: ContentObserver? = null
    private val debounceHandler = Handler(Looper.getMainLooper())
    private var debounceRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        mediaStoreObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (e: Exception) {}
            mediaStoreObserver = null
        }
        executor.shutdown()
        super.onDestroy()
    }

    private fun registerMediaStoreObserver() {
        if (mediaStoreObserver != null) return
        mediaStoreObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                debounceRunnable?.let { debounceHandler.removeCallbacks(it) }
                debounceRunnable = Runnable {
                    methodChannel?.invokeMethod("onMediaStorePdfChanged", null)
                }
                debounceHandler.postDelayed(debounceRunnable!!, 800)
            }
        }
        try {
            contentResolver.registerContentObserver(
                MediaStore.Files.getContentUri("external"),
                true,
                mediaStoreObserver!!
            )
            Log.d(TAG, "Registered MediaStore ContentObserver")
        } catch (e: Exception) {
            Log.w(TAG, "Unable to register MediaStore ContentObserver: ${e.message}")
        }
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }
                if (display != null) {
                    val modes = display.supportedModes
                    var selectedMode: Display.Mode? = null
                    var bestRefreshRate = 0f

                    for (mode in modes) {
                        if (mode.refreshRate >= 119.0f && mode.refreshRate <= 121.0f) {
                            selectedMode = mode
                            bestRefreshRate = mode.refreshRate
                            break
                        }
                    }

                    if (selectedMode == null) {
                        for (mode in modes) {
                            if (mode.refreshRate <= 120.0f && mode.refreshRate > bestRefreshRate) {
                                bestRefreshRate = mode.refreshRate
                                selectedMode = mode
                            }
                        }
                    }

                    if (selectedMode == null) {
                        for (mode in modes) {
                            if (mode.refreshRate > bestRefreshRate) {
                                bestRefreshRate = mode.refreshRate
                                selectedMode = mode
                            }
                        }
                    }

                    if (selectedMode != null) {
                        val lp = window.attributes
                        lp.preferredDisplayModeId = selectedMode.modeId
                        @Suppress("DEPRECATION")
                        lp.preferredRefreshRate = bestRefreshRate
                        window.attributes = lp
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to enable high refresh rate: ${e.message}")
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        val type = intent.type

        Log.d(TAG, "Handling intent action: $action, type: $type")

        if (Intent.ACTION_VIEW == action || Intent.ACTION_EDIT == action || Intent.ACTION_SEND == action || Intent.ACTION_SEND_MULTIPLE == action) {
            val urisToProcess = mutableListOf<Uri>()

            if (Intent.ACTION_SEND == action) {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                if (uri != null) urisToProcess.add(uri)
            } else if (Intent.ACTION_SEND_MULTIPLE == action) {
                val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                }
                if (!uris.isNullOrEmpty()) {
                    urisToProcess.addAll(uris)
                }
            } else {
                val uri = intent.data
                if (uri != null) urisToProcess.add(uri)
            }

            if (urisToProcess.isNotEmpty()) {
                val callerPkg = callingActivity?.packageName ?: callingPackage

                executor.execute {
                    val payloads = mutableListOf<Map<String, Any?>>()

                    for (uri in urisToProcess) {
                        val payload = resolveUriToPayload(uri, action, type, callerPkg)
                        if (payload != null) {
                            payloads.add(payload)
                        }
                    }

                    if (payloads.isNotEmpty()) {
                        val firstPayload = payloads[0]
                        val compositePayload = mutableMapOf<String, Any?>()
                        compositePayload.putAll(firstPayload)
                        compositePayload["documents"] = payloads
                        compositePayload["requestId"] = UUID.randomUUID().toString()

                        runOnUiThread {
                            if (!isFinishing && !isDestroyed) {
                                if (dartIntentHandlerReady && methodChannel != null) {
                                    methodChannel?.invokeMethod("onPdfOpened", compositePayload)
                                    Log.d(TAG, "Dispatched ${payloads.size} intent document(s) payload to Dart")
                                } else {
                                    pendingPayload = compositePayload
                                    Log.d(TAG, "Stored pending ${payloads.size} intent document(s) payload for Dart")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private fun resolveUriToPayload(uri: Uri, action: String, mimeType: String?, callingPackage: String?): Map<String, Any?>? {
        return try {
            val uriString = uri.toString()
            Log.d(TAG, "Resolving URI: $uriString")

            val rawName = getFileNameFromUri(uri) ?: "External_Document.pdf"
            val originalFileName = sanitizeFileName(rawName)

            var directPath: String? = null
            if (uri.scheme == "file") {
                val f = File(uri.path ?: "")
                if (f.exists() && f.isFile && f.canRead()) {
                    directPath = f.absolutePath
                }
            } else if (uri.scheme == "content") {
                try {
                    contentResolver.query(uri, arrayOf(MediaStore.Files.FileColumns.DATA), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val dataIdx = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                            if (dataIdx != -1) {
                                val p = cursor.getString(dataIdx)
                                if (!p.isNullOrBlank()) {
                                    val f = File(p)
                                    if (f.exists() && f.isFile && f.canRead()) {
                                        directPath = f.absolutePath
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {}
            }

            if (directPath != null) {
                return mapOf(
                    "localPath" to directPath,
                    "originalUri" to uriString,
                    "fileName" to originalFileName,
                    "mimeType" to (mimeType ?: "application/pdf"),
                    "action" to action,
                    "sourceApp" to (callingPackage ?: "external"),
                    "isExternalLaunch" to true,
                    "requestId" to UUID.randomUUID().toString()
                )
            }

            // Fallback for streamed content URIs (e.g. email attachments) where direct file path is unavailable:
            // Use temporary cache directory (cacheDir/temp_external_pdfs) so it is NOT persistent in app filesDir
            val targetDir = File(cacheDir, "temp_external_pdfs")
            if (!targetDir.exists() && !targetDir.mkdirs() && !targetDir.exists()) {
                Log.e(TAG, "Unable to create temp external PDF directory: ${targetDir.absolutePath}")
                return null
            }
            val internalName = "${System.currentTimeMillis()}_${UUID.randomUUID()}.pdf"
            val targetFile = File(targetDir, internalName)

            val success = copyUriAtomically(uri, targetFile)
            if (!success) {
                return null
            }

            mapOf(
                "localPath" to targetFile.absolutePath,
                "originalUri" to uriString,
                "fileName" to originalFileName,
                "mimeType" to (mimeType ?: "application/pdf"),
                "action" to action,
                "sourceApp" to (callingPackage ?: "external"),
                "isExternalLaunch" to true,
                "isTemporary" to true,
                "requestId" to UUID.randomUUID().toString()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error resolving PDF URI $uri: ${e.message}", e)
            null
        }
    }

    private fun copyUriAtomically(uri: Uri, targetFile: File): Boolean {
        if (targetFile.exists()) {
            targetFile.delete()
        }

        val tempFile = File(
            targetFile.parentFile,
            "${targetFile.name}.${UUID.randomUUID()}.tmp"
        )

        try {
            val uriString = uri.toString()
            val inputStream: InputStream? = if (uriString.startsWith("content://")) {
                contentResolver.openInputStream(uri)
            } else if (uriString.startsWith("file://")) {
                val sourcePath = uri.path ?: return false
                val sourceFile = File(sourcePath)
                if (!sourceFile.exists() || !sourceFile.isFile) return false
                sourceFile.inputStream()
            } else {
                val sourceFile = File(uriString)
                if (!sourceFile.exists() || !sourceFile.isFile) return false
                sourceFile.inputStream()
            }

            if (inputStream == null) {
                return false
            }

            inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }

            if (!tempFile.exists() || tempFile.length() == 0L || !hasPdfHeader(tempFile)) {
                tempFile.delete()
                return false
            }

            if (!tempFile.renameTo(targetFile)) {
                tempFile.delete()
                return false
            }

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed atomic copy from $uri: ${e.message}", e)
            if (tempFile.exists()) tempFile.delete()
            if (targetFile.exists()) targetFile.delete()
            return false
        }
    }

    private fun hasPdfHeader(file: File): Boolean {
        return try {
            file.inputStream().use { input ->
                val header = ByteArray(5)
                val read = input.read(header)
                read == 5 &&
                    header[0] == '%'.code.toByte() &&
                    header[1] == 'P'.code.toByte() &&
                    header[2] == 'D'.code.toByte() &&
                    header[3] == 'F'.code.toByte() &&
                    header[4] == '-'.code.toByte()
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun sanitizeFileName(rawName: String): String {
        val cleaned = rawName
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .trim()
            .trim('.')

        if (cleaned.isEmpty()) {
            return "External_Document.pdf"
        }

        val limited = if (cleaned.length > 180) {
            cleaned.take(180)
        } else {
            cleaned
        }

        return if (limited.lowercase().endsWith(".pdf")) {
            limited
        } else {
            "$limited.pdf"
        }
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            result = cursor.getString(nameIndex)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to query displayName: ${e.message}")
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/') ?: -1
            if (cut != -1 && result != null) {
                result = result.substring(cut + 1)
            }
        }
        return result
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        registerMediaStoreObserver()

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "markIntentHandlerReady" -> {
                    dartIntentHandlerReady = true
                    if (pendingPayload != null) {
                        channel.invokeMethod("onPdfOpened", pendingPayload)
                        pendingPayload = null
                    }
                    result.success(true)
                }
                "getInitialPdfRequest" -> {
                    result.success(pendingPayload)
                    pendingPayload = null
                }
                "queryMediaStorePdfs" -> {
                    executor.execute {
                        try {
                            val pdfPaths = linkedSetOf<String>()

                            val uri = MediaStore.Files.getContentUri("external")

                            val projection = arrayOf(
                                MediaStore.Files.FileColumns._ID,
                                MediaStore.Files.FileColumns.DISPLAY_NAME,
                                MediaStore.Files.FileColumns.MIME_TYPE,
                                MediaStore.Files.FileColumns.DATA,
                                MediaStore.Files.FileColumns.RELATIVE_PATH
                            )

                            val selection =
                                "(${MediaStore.Files.FileColumns.MIME_TYPE} = ?)" +
                                " OR LOWER(${MediaStore.Files.FileColumns.DISPLAY_NAME}) LIKE ?"

                            val selectionArgs = arrayOf(
                                "application/pdf",
                                "%.pdf"
                            )

                            contentResolver.query(
                                uri,
                                projection,
                                selection,
                                selectionArgs,
                                null
                            )?.use { cursor ->

                                val dataIndex =
                                    cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)

                                val displayNameIndex =
                                    cursor.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)

                                val relativePathIndex =
                                    cursor.getColumnIndex(MediaStore.Files.FileColumns.RELATIVE_PATH)

                                while (cursor.moveToNext()) {
                                    try {
                                        val displayName =
                                            if (displayNameIndex >= 0)
                                                cursor.getString(displayNameIndex)
                                            else
                                                null

                                        val dataPath =
                                            if (dataIndex >= 0)
                                                cursor.getString(dataIndex)
                                            else
                                                null

                                        val relativePath =
                                            if (relativePathIndex >= 0)
                                                cursor.getString(relativePathIndex)
                                            else
                                                null

                                        var resolvedPath: String? = null

                                        // Prefer direct MediaStore DATA path when available and valid
                                        if (!dataPath.isNullOrBlank() &&
                                            dataPath.lowercase().endsWith(".pdf")) {
                                            val file = File(dataPath)

                                            if (file.exists() &&
                                                file.isFile &&
                                                file.canRead()) {
                                                resolvedPath = file.absolutePath
                                            }
                                        }

                                        // Fallback for MediaStore entries where DATA is unavailable
                                        if (resolvedPath == null &&
                                            !relativePath.isNullOrBlank() &&
                                            !displayName.isNullOrBlank() &&
                                            displayName.lowercase().endsWith(".pdf")) {

                                            val candidate = File(
                                                Environment
                                                    .getExternalStorageDirectory()
                                                    .absolutePath +
                                                File.separator +
                                                relativePath +
                                                displayName
                                            )

                                            if (candidate.exists() &&
                                                candidate.isFile &&
                                                candidate.canRead()) {
                                                resolvedPath = candidate.absolutePath
                                            }
                                        }

                                        if (!resolvedPath.isNullOrBlank()) {
                                            pdfPaths.add(resolvedPath)
                                        }
                                    } catch (rowError: Exception) {
                                        Log.w(
                                            TAG,
                                            "Skipping one MediaStore PDF row: ${rowError.message}"
                                        )
                                    }
                                }
                            }

                            Log.d(
                                TAG,
                                "MediaStore PDF candidates: ${pdfPaths.size}"
                            )

                            runOnUiThread {
                                result.success(pdfPaths.toList())
                            }
                        } catch (e: Exception) {
                            Log.e(
                                TAG,
                                "Error querying MediaStore for PDFs",
                                e
                            )

                            runOnUiThread {
                                result.success(emptyList<String>())
                            }
                        }
                    }
                }
                "compressImage" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val targetBytes = call.argument<Number>("targetBytes")?.toLong() ?: 102400L

                    if (inputPath == null || outputPath == null) {
                        result.error("INVALID_ARGS", "Missing paths", null)
                    } else {
                        executor.execute {
                            try {
                                val res = compressImageToTarget(inputPath, outputPath, targetBytes)
                                runOnUiThread {
                                    result.success(res)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error compressing image: ${e.message}", e)
                                runOnUiThread {
                                    result.error("COMPRESS_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun compressImageToTarget(inputPath: String, outputPath: String, targetBytes: Long): Map<String, Any?> {
        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            throw IllegalArgumentException("Input image file not found at $inputPath")
        }

        val originalSize = inputFile.length()
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(inputPath, options)

        val origWidth = options.outWidth
        val origHeight = options.outHeight

        if (origWidth <= 0 || origHeight <= 0) {
            throw IllegalArgumentException("Unable to decode image dimensions from $inputPath")
        }

        val ext = inputPath.substringAfterLast('.', "jpg").lowercase()
        val (format, actualExt) = when (ext) {
            "png" -> Pair(Bitmap.CompressFormat.PNG, "png")
            "webp" -> Pair(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else @Suppress("DEPRECATION") Bitmap.CompressFormat.WEBP,
                "webp"
            )
            "jpeg" -> Pair(Bitmap.CompressFormat.JPEG, "jpeg")
            else -> Pair(Bitmap.CompressFormat.JPEG, "jpg")
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()

        var bestSize = Long.MAX_VALUE
        var finalWidth = origWidth
        var finalHeight = origHeight
        val tempFilesCreated = mutableListOf<File>()

        try {
            val scales = floatArrayOf(1.0f, 0.85f, 0.70f, 0.55f, 0.40f, 0.25f)

            for (scale in scales) {
                val targetW = Math.max(10, (origWidth * scale).toInt())
                val targetH = Math.max(10, (origHeight * scale).toInt())

                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(origWidth, origHeight, targetW, targetH)
                }

                val decodedBitmap = BitmapFactory.decodeFile(inputPath, decodeOptions) ?: continue

                val scaledBitmap = if (decodedBitmap.width != targetW || decodedBitmap.height != targetH) {
                    val s = Bitmap.createScaledBitmap(decodedBitmap, targetW, targetH, true)
                    if (s != decodedBitmap) decodedBitmap.recycle()
                    s
                } else {
                    decodedBitmap
                }

                if (format == Bitmap.CompressFormat.PNG) {
                    val tempFile = File(outputFile.parentFile, "${outputFile.name}.png_scale_${(scale * 100).toInt()}.tmp")
                    tempFilesCreated.add(tempFile)

                    FileOutputStream(tempFile).use { fos ->
                        scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, fos)
                        fos.flush()
                    }

                    val tempSize = tempFile.length()
                    val shouldUse = if (tempSize <= targetBytes) {
                        bestSize > targetBytes || tempSize > bestSize
                    } else {
                        bestSize > targetBytes && Math.abs(bestSize - targetBytes) > Math.abs(tempSize - targetBytes)
                    }

                    if (shouldUse) {
                        bestSize = tempSize
                        finalWidth = targetW
                        finalHeight = targetH

                        if (outputFile.exists()) outputFile.delete()
                        tempFile.renameTo(outputFile)
                    }

                    scaledBitmap.recycle()

                    if (tempSize <= targetBytes) {
                        break
                    }
                } else {
                    var lowQ = 15
                    var highQ = 95

                    while (lowQ <= highQ) {
                        val midQ = (lowQ + highQ) / 2
                        val tempFile = File(outputFile.parentFile, "${outputFile.name}.q_${midQ}_s_${(scale * 100).toInt()}.tmp")
                        tempFilesCreated.add(tempFile)

                        FileOutputStream(tempFile).use { fos ->
                            scaledBitmap.compress(format, midQ, fos)
                            fos.flush()
                        }

                        val tempSize = tempFile.length()
                        val shouldUse = if (tempSize <= targetBytes) {
                            bestSize > targetBytes || tempSize > bestSize
                        } else {
                            bestSize > targetBytes && Math.abs(bestSize - targetBytes) > Math.abs(tempSize - targetBytes)
                        }

                        if (shouldUse) {
                            bestSize = tempSize
                            finalWidth = targetW
                            finalHeight = targetH

                            if (outputFile.exists()) outputFile.delete()
                            tempFile.renameTo(outputFile)
                        }

                        if (tempSize > targetBytes) {
                            highQ = midQ - 10
                        } else {
                            lowQ = midQ + 10
                        }
                    }

                    scaledBitmap.recycle()

                    if (bestSize <= targetBytes) {
                        break
                    }
                }
            }
        } finally {
            for (tf in tempFilesCreated) {
                if (tf.exists() && tf.absolutePath != outputFile.absolutePath) {
                    tf.delete()
                }
            }
        }

        val actualSize = if (outputFile.exists()) outputFile.length() else originalSize
        val isAchieved = actualSize <= targetBytes

        return mapOf(
            "originalPath" to inputPath,
            "outputPath" to outputFile.absolutePath,
            "originalSizeBytes" to originalSize,
            "targetSizeBytes" to targetBytes,
            "outputSizeBytes" to actualSize,
            "originalWidth" to origWidth,
            "originalHeight" to origHeight,
            "outputWidth" to finalWidth,
            "outputHeight" to finalHeight,
            "format" to actualExt.uppercase(),
            "isTargetAchieved" to isAchieved,
            "statusMessage" to if (isAchieved) "Target size achieved" else "Closest safe result without cropping"
        )
    }

    private fun calculateInSampleSize(width: Int, height: Int, reqWidth: Int, reqHeight: Int): Int {
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }
}
