package com.wang.lingfer.screen

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ImageOcrChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "lingfer/image_ocr")
    private val ocr = NativeOcrEngine()
    @Volatile private var closed = false
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method !in listOf("recognizeText", "recognizeTextLayout")) { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank() || !File(path).isFile) { result.error("NO_IMAGE", "图片暂时无法读取。", null); return@setMethodCallHandler }
            try {
                val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
                val rotated = image.rotationDegrees == 90 || image.rotationDegrees == 270
                val source = call.argument<String>("language") ?: call.argument<String>("script") ?: "auto"
                ocr.recognize(image, if (rotated) image.height else image.width, if (rotated) image.width else image.height, source) { page, error ->
                    if (!closed) {
                        if (page != null) result.success(if (call.method == "recognizeText") page.text else page.json())
                        else result.error("OCR_FAILED", "识别没有完成，请换一张清晰图片。", error?.javaClass?.simpleName)
                    }
                }
            } catch (_: Exception) { result.error("OCR_FAILED", "图片暂时无法识别。", null) }
        }
    }
    fun close() { closed = true; channel.setMethodCallHandler(null); ocr.close() }
}
