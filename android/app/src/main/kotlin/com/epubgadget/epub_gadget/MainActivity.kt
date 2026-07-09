package com.epubgadget.epub_gadget

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import kotlin.concurrent.thread

// 继承 FlutterFragmentActivity 是 file_picker 在 Android 11+ 走 SAF 的必要条件
// FlutterActivity 无法承载 IntentSender 回调，会导致闪退
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.epub_gadget/file_helper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeToPublicDownload" -> {
                        val filename = call.argument<String>("filename")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (filename == null || bytes == null) {
                            result.error("INVALID_ARGS", "filename/bytes 必填", null)
                            return@setMethodCallHandler
                        }
                        thread(name = "epub-gadget-write-download") {
                            try {
                                val displayPath = writeToDownloads(filename, bytes)
                                runOnUiThread { result.success(displayPath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("WRITE_FAILED", e.message, null) }
                            }
                        }
                    }
                    "copyFileToPublicDownload" -> {
                        // 流式复制：避免 Dart 堆持有整个文件
                        val sourcePath = call.argument<String>("sourcePath")
                        val filename = call.argument<String>("filename")
                        if (sourcePath == null || filename == null) {
                            result.error("INVALID_ARGS", "sourcePath/filename 必填", null)
                            return@setMethodCallHandler
                        }
                        thread(name = "epub-gadget-copy-download") {
                            try {
                                val displayPath = copyFileToDownloads(sourcePath, filename)
                                runOnUiThread { result.success(displayPath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COPY_FAILED", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 通过 MediaStore.Downloads 写入公共 Download 目录。
     *
     * Android 10+（API 29+）禁止应用直接通过 File API 写入公共目录。
     * 必须通过 MediaStore ContentProvider 写入。
     *
     * 在 MediaStore.Downloads 下创建 books/ 子目录，存放 EPUB 文件。
     * 返回的 displayPath 形如 "/storage/emulated/0/Download/books/xxx.epub"，
     * 用于在日志中向用户展示。
     */
    private fun writeToDownloads(filename: String, bytes: ByteArray): String {
        val resolver = applicationContext.contentResolver

        // 1. 先确保 books/ 子目录存在（Android 10+ 需要逐级创建）
        // 写一个占位文件来触发子目录创建，然后删除
        ensureDownloadsSubdirectory(resolver, "books")

        // 2. 准备 ContentValues
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/epub+zip")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // RELATIVE_PATH 控制子目录（Android 10+ 支持）
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/books")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        // 3. 插入记录，获取 content:// URI
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Files.getContentUri("external")
        }
        val uri = resolver.insert(collection, values)
            ?: throw Exception("无法创建下载条目")

        // 4. 写入字节
        try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw Exception("无法打开输出流")
        } catch (e: Exception) {
            // 写入失败，回滚（删除刚插入的记录）
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            throw e
        }

        // 5. 取消 IS_PENDING，文件变为可见
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val update = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, update, null, null)
        }

        // 6. 构造用户可见的 display path（用于日志展示）
        return "/storage/emulated/0/${Environment.DIRECTORY_DOWNLOADS}/books/$filename"
    }

    /**
     * 确保 MediaStore.Downloads/books/ 子目录存在。
     *
     * Android 10+ 的 MediaStore 在子目录不存在时，
     * 第一次写入会自动创建 RELATIVE_PATH 中的子目录，
     * 但提前创建一个 .nomedia 占位文件能确保目录被 Files 应用识别。
     */
    private fun ensureDownloadsSubdirectory(resolver: android.content.ContentResolver, subdir: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Android 9 及以下：直接用 File API（仍允许）
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                subdir
            )
            if (!dir.exists()) dir.mkdirs()
            return
        }
        // Android 10+：MediaStore 会在首次写入时自动创建子目录，无需手动创建
    }

    /**
     * 流式复制：源文件通过 FileInputStream 读取，分块写入 MediaStore.OutputStream。
     *
     * 适用于大文件（>10MB）：避免 Dart 堆 + MethodChannel 序列化时持有整个文件
     * 副本导致 OOM。内存占用 = 1 个 8KB 缓冲区，与文件大小无关。
     *
     * 与 [writeToDownloads] 的区别：
     * - writeToDownloads: Dart 端把整个文件转成 ByteArray 传给原生，
     *   47MB 文件会占用 Dart 堆 47MB + MethodChannel 序列化 47MB = 94MB 峰值。
     * - copyFileToDownloads: Dart 端只传文件路径字符串，原生端从磁盘直接流式读写，
     *   Dart 堆几乎零开销。
     */
    private fun copyFileToDownloads(sourcePath: String, filename: String): String {
        val src = File(sourcePath)
        if (!src.exists()) {
            throw Exception("源文件不存在: $sourcePath")
        }

        val resolver = applicationContext.contentResolver
        ensureDownloadsSubdirectory(resolver, "books")

        val values = android.content.ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/epub+zip")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/books")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Files.getContentUri("external")
        }
        val uri = resolver.insert(collection, values)
            ?: throw Exception("无法创建下载条目")

        try {
            // 流式复制：8KB 缓冲区
            val buffer = ByteArray(8 * 1024)
            FileInputStream(src).use { input ->
                resolver.openOutputStream(uri)?.use { out ->
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } > 0) {
                        out.write(buffer, 0, bytesRead)
                    }
                    out.flush()
                } ?: throw Exception("无法打开输出流")
            }
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            throw e
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val update = android.content.ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, update, null, null)
        }

        return "/storage/emulated/0/${Environment.DIRECTORY_DOWNLOADS}/books/$filename"
    }
}
