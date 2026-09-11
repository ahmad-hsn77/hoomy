package com.idea.hoomy.hoomy

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var soundPool: SoundPool? = null
    private var messageChimeSoundId = 0
    private var messageReceiveSoundId = 0
    private var currentUpdateDownloadId: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
        prepareMessageChime()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playMessageChime" -> {
                    playMessageChime()
                    result.success(null)
                }
                "playMessageReceiveChime" -> {
                    playMessageReceiveChime()
                    result.success(null)
                }
                "clearChatNotifications" -> {
                    clearChatNotifications()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadApk" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("missing_url", "APK URL is required.", null)
                        return@setMethodCallHandler
                    }
                    downloadApk(url, result)
                }
                "cancelUpdateDownload" -> {
                    cancelUpdateDownload()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("missing_path", "APK path is required.", null)
                        return@setMethodCallHandler
                    }
                    installApk(path, result)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("missing_image", "Image data is empty.", null)
                        return@setMethodCallHandler
                    }
                    saveImageToGallery(bytes, fileName, mimeType, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        val emergencySound =
            Uri.parse("android.resource://$packageName/${R.raw.emergency_ring}")
        val reminderSound =
            Uri.parse("android.resource://$packageName/${R.raw.reminder_ring}")
        val messageSound =
            Uri.parse("android.resource://$packageName/${R.raw.message_chime}")
        val alarmAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val messageAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val emergencyChannel = NotificationChannel(
            EMERGENCY_CHANNEL_ID,
            "Emergency alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Urgent house needs with a long ringtone."
            setSound(emergencySound, alarmAttributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 900, 250, 900, 250, 900)
            enableLights(true)
        }

        val needChannel = NotificationChannel(
            NEED_CHANNEL_ID,
            "Need alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "House needs shared by family members."
        }

        val reminderChannel = NotificationChannel(
            REMINDER_CHANNEL_ID,
            "Family reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Important family reminders with a gentle ringtone."
            setSound(reminderSound, alarmAttributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 450, 180, 450)
            enableLights(true)
        }

        val chatChannel = NotificationChannel(
            CHAT_CHANNEL_ID,
            "Family chat",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "New messages in your family chat."
            setSound(messageSound, messageAttributes)
        }

        manager.createNotificationChannel(emergencyChannel)
        manager.createNotificationChannel(needChannel)
        manager.createNotificationChannel(reminderChannel)
        manager.createNotificationChannel(chatChannel)
    }

    private fun prepareMessageChime() {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        soundPool = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(attributes)
            .build()
        messageChimeSoundId = soundPool?.load(this, R.raw.message_chime, 1) ?: 0
        messageReceiveSoundId = soundPool?.load(this, R.raw.message_receive, 1) ?: 0
    }

    private fun playMessageChime() {
        val pool = soundPool ?: return
        if (messageChimeSoundId == 0) return
        pool.play(messageChimeSoundId, 0.34f, 0.34f, 1, 0, 1.0f)
    }

    private fun playMessageReceiveChime() {
        val pool = soundPool ?: return
        if (messageReceiveSoundId == 0) return
        pool.play(messageReceiveSoundId, 0.38f, 0.38f, 1, 0, 1.0f)
    }

    private fun downloadApk(url: String, result: MethodChannel.Result) {
        try {
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val directory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: cacheDir
            if (!directory.exists()) directory.mkdirs()
            val apk = File(directory, "hoomy_update.apk")
            if (apk.exists()) apk.delete()

            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("Hoomy update")
                .setDescription("Downloading Hoomy update")
                .setMimeType("application/vnd.android.package-archive")
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setDestinationUri(Uri.fromFile(apk))

            val downloadId = manager.enqueue(request)
            currentUpdateDownloadId = downloadId
            Thread {
                val timeoutAt = System.currentTimeMillis() + 5 * 60 * 1000
                while (System.currentTimeMillis() < timeoutAt) {
                    val query = DownloadManager.Query().setFilterById(downloadId)
                    manager.query(query)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val status = cursor.getInt(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                            )
                            when (status) {
                                DownloadManager.STATUS_SUCCESSFUL -> {
                                    currentUpdateDownloadId = null
                                    if (!apk.exists()) {
                                        runOnUiThread {
                                            result.error(
                                                "missing_apk",
                                                "Downloaded APK was not found.",
                                                null
                                            )
                                        }
                                        return@Thread
                                    }
                                    runOnUiThread { result.success(apk.absolutePath) }
                                    return@Thread
                                }
                                DownloadManager.STATUS_FAILED -> {
                                    currentUpdateDownloadId = null
                                    val reason = cursor.getInt(
                                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
                                    )
                                    manager.remove(downloadId)
                                    runOnUiThread {
                                        result.error(
                                            "download_failed",
                                            "Android download failed: $reason",
                                            null
                                        )
                                    }
                                    return@Thread
                                }
                            }
                        }
                    }
                    Thread.sleep(500)
                }
                currentUpdateDownloadId = null
                manager.remove(downloadId)
                runOnUiThread {
                    result.error(
                        "download_timeout",
                        "Android download timed out.",
                        null
                    )
                }
            }.start()
        } catch (error: Exception) {
            result.error("download_failed", error.message, null)
        }
    }

    private fun cancelUpdateDownload() {
        val downloadId = currentUpdateDownloadId ?: return
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        manager.remove(downloadId)
        currentUpdateDownloadId = null
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        val apk = File(path)
        if (!apk.exists()) {
            result.error("missing_apk", "Downloaded APK was not found.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
            result.error(
                "install_permission_required",
                "Allow Hoomy to install unknown apps, then try the update again.",
                null
            )
            return
        }

        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(installIntent)
        result.success(null)
    }

    private fun clearChatNotifications() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.activeNotifications
                .filter { it.tag == CHAT_NOTIFICATION_TAG }
                .forEach { manager.cancel(it.tag, it.id) }
        }
    }

    private fun saveImageToGallery(
        bytes: ByteArray,
        fileName: String?,
        mimeType: String,
        result: MethodChannel.Result
    ) {
        val safeFileName = fileName
            ?.takeIf { it.isNotBlank() }
            ?: "hoomy_${System.currentTimeMillis()}.jpg"

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, safeFileName)
                    put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        "${Environment.DIRECTORY_PICTURES}/Hoomy"
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri = resolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values
                ) ?: throw IllegalStateException("Could not create gallery image.")

                resolver.openOutputStream(uri)?.use { output ->
                    output.write(bytes)
                } ?: throw IllegalStateException("Could not open gallery image.")

                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                result.success(uri.toString())
                return
            }

            val pictures = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_PICTURES
            )
            val directory = File(pictures, "Hoomy")
            if (!directory.exists()) directory.mkdirs()
            val image = File(directory, safeFileName)
            image.writeBytes(bytes)
            sendBroadcast(
                Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(image))
            )
            result.success(Uri.fromFile(image).toString())
        } catch (error: Exception) {
            result.error("save_image_failed", error.message, null)
        }
    }

    override fun onDestroy() {
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }

    companion object {
        private const val AUDIO_CHANNEL = "hoomy/audio"
        private const val UPDATER_CHANNEL = "hoomy/updater"
        private const val MEDIA_CHANNEL = "hoomy/media"
        private const val EMERGENCY_CHANNEL_ID = "hoomy_emergency_alerts_alarm_v2"
        private const val NEED_CHANNEL_ID = "hoomy_need_alerts"
        private const val REMINDER_CHANNEL_ID = "hoomy_reminders_alarm_v1"
        private const val CHAT_CHANNEL_ID = "hoomy_chat_messages_chime_v2"
        private const val CHAT_NOTIFICATION_TAG = "hoomy-family-chat"
    }
}
