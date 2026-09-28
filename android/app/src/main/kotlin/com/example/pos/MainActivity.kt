package com.example.pos

import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pos/download_saver"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingFileName: String? = null
    private val PERMISSION_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    android.media.MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(path),
                        null,
                        null
                    )
                    result.success(true)
                } else {
                    result.success(false)
                }
                return@setMethodCallHandler
            }

            if (call.method == "saveToPublicDownloads") {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                if (bytes == null || fileName == null) {
                    result.error("INVALID_ARGS", "bytes and fileName are required", null)
                    return@setMethodCallHandler
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Android 10+ (API 29+): Use MediaStore to save directly to main public Download directory
                    try {
                        val contentValues = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                            put(MediaStore.Downloads.MIME_TYPE, mimeType)
                            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                        }

                        val resolver = applicationContext.contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                        if (uri != null) {
                            resolver.openOutputStream(uri)?.use { outputStream ->
                                outputStream.write(bytes)
                                outputStream.flush()
                            }
                            result.success("/storage/emulated/0/Download/$fileName")
                        } else {
                            result.error("URI_NULL", "Failed to create MediaStore entry", null)
                        }
                    } catch (e: Exception) {
                        result.error("IO_ERROR", e.message, null)
                    }
                } else {
                    // Android 9 and below (e.g. Android 8.1 / 9 on Oppo A5s):
                    if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
                        == PackageManager.PERMISSION_GRANTED) {
                        saveDirectlyToDownloads(bytes, fileName, result)
                    } else {
                        pendingResult = result
                        pendingBytes = bytes
                        pendingFileName = fileName
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE, android.Manifest.permission.READ_EXTERNAL_STORAGE),
                            PERMISSION_REQUEST_CODE
                        )
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveDirectlyToDownloads(bytes: ByteArray, fileName: String, result: MethodChannel.Result) {
        try {
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadDir.exists()) {
                downloadDir.mkdirs()
            }
            val targetFile = File(downloadDir, fileName)
            FileOutputStream(targetFile).use { fos ->
                fos.write(bytes)
                fos.flush()
            }
            // Notify Android system scanner so file shows immediately in Downloads tab
            android.media.MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(targetFile.absolutePath),
                null,
                null
            )
            result.success(targetFile.absolutePath)
        } catch (e: Exception) {
            result.error("IO_ERROR", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val result = pendingResult
            val bytes = pendingBytes
            val fileName = pendingFileName

            pendingResult = null
            pendingBytes = null
            pendingFileName = null

            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (bytes != null && fileName != null && result != null) {
                    saveDirectlyToDownloads(bytes, fileName, result)
                }
            } else {
                result?.error("PERMISSION_DENIED", "Storage permission was denied", null)
            }
        }
    }
}
