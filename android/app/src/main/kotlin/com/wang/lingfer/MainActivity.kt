package com.wang.lingfer

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.wang.lingfer.screen.ScreenReaderService
import com.wang.lingfer.screen.ScreenReaderState
import com.wang.lingfer.screen.ImageOcrChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var projectionResult: MethodChannel.Result? = null
    private var imageOcr: ImageOcrChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imageOcr = ImageOcrChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lingfer/screen_reader")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(ScreenReaderState.status(this))
                    "configure" -> {
                        val prefs = getSharedPreferences("lingfer_screen", MODE_PRIVATE)
                        prefs.edit()
                            .putString("level", call.argument<String>("level") ?: "cet4")
                            .putStringSet("known", (call.argument<List<String>>("known") ?: emptyList()).toSet())
                            .putString("proxyUrl", call.argument<String>("proxyUrl") ?: "")
                            .putString("appSecret", call.argument<String>("appSecret") ?: "")
                            .putString("saved", call.argument<String>("saved") ?: "[]")
                            .putString("sourceLanguage", call.argument<String>("sourceLanguage") ?: "auto")
                            .putString("targetLanguage", call.argument<String>("targetLanguage") ?: "zh")
                            .putString("generalDifficulty", call.argument<String>("generalDifficulty") ?: "intermediate")
                            .putString("readingMode", call.argument<String>("readingMode") ?: "learning")
                            .putBoolean("automatic", call.argument<Boolean>("automatic") ?: true)
                            .apply()
                        result.success(null)
                    }
                    "requestOverlayPermission" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "start" -> {
                        if (ScreenReaderState.running) { result.success(true); return@setMethodCallHandler }
                        if (!Settings.canDrawOverlays(this)) {
                            result.error("OVERLAY_REQUIRED", "请先允许语渡显示悬浮窗。", null)
                        } else if (projectionResult != null) {
                            result.error("START_PENDING", "正在等待屏幕读取授权。", null)
                        } else {
                            projectionResult = result
                            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            startActivityForResult(manager.createScreenCaptureIntent(), 8134)
                        }
                    }
                    "pause" -> {
                        if (ScreenReaderState.running) startService(Intent(this, ScreenReaderService::class.java).setAction(ScreenReaderService.PAUSE).putExtra("paused", call.argument<Boolean>("paused") ?: true))
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, ScreenReaderService::class.java))
                        result.success(null)
                    }
                    "capture" -> {
                        if (ScreenReaderState.running) {
                            startService(Intent(this, ScreenReaderService::class.java).setAction(ScreenReaderService.CAPTURE))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lingfer/screen_reader_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { ScreenReaderState.sink = sink }
                override fun onCancel(arguments: Any?) { ScreenReaderState.sink = null }
            })
    }

    @Deprecated("Android compatibility callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 8134) return
        val callback = projectionResult
        projectionResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback?.success(false)
            return
        }
        try {
            val intent = Intent(this, ScreenReaderService::class.java)
                .setAction(ScreenReaderService.START)
                .putExtra("resultCode", resultCode)
                .putExtra("projectionData", data)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            callback?.success(true)
        } catch (_: Exception) {
            callback?.error("START_FAILED", "系统未能开启随屏阅读，请重试。", null)
        }
    }

    override fun onResume() {
        super.onResume()
        ScreenReaderState.hostActive = true
        if (ScreenReaderState.running) startService(Intent(this, ScreenReaderService::class.java).setAction(ScreenReaderService.HOST))
    }

    override fun onPause() {
        ScreenReaderState.hostActive = false
        if (ScreenReaderState.running) startService(Intent(this, ScreenReaderService::class.java).setAction(ScreenReaderService.HOST))
        super.onPause()
    }

    override fun onDestroy() {
        ScreenReaderState.sink = null
        imageOcr?.close()
        imageOcr = null
        projectionResult?.success(false)
        projectionResult = null
        super.onDestroy()
    }
}
