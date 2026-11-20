package com.wang.lingfer.screen

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

class NativeOcrEngine {
    private val recognizers = mutableMapOf<String, TextRecognizer>()
    private val identifier = LanguageIdentification.getClient()
    @Volatile private var closed = false
    @Synchronized private fun recognizer(language: String) = recognizers.getOrPut(language) {
        when (language) {
            "zh", "auto", "chinese" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
            "ja", "japanese" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
            "ko", "korean" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
            "hi", "devanagari" -> TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
            else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        }
    }

    fun recognize(bitmap: Bitmap, source: String, excluded: List<RectF> = emptyList(), screenChrome: Boolean = false, callback: (OcrPage?, Exception?) -> Unit) {
        recognize(InputImage.fromBitmap(bitmap, 0), bitmap.width, bitmap.height, source, excluded, screenChrome, callback)
    }

    fun recognize(image: InputImage, width: Int, height: Int, source: String, excluded: List<RectF> = emptyList(), screenChrome: Boolean = false, callback: (OcrPage?, Exception?) -> Unit) {
        if (closed) return
        recognizer(source).process(image).addOnSuccessListener { text ->
            if (closed) return@addOnSuccessListener
            val page = OcrPage.from(text, width, height, excluded, screenChrome)
            identifier.identifyLanguage(languageSample(page.text).take(3000)).addOnCompleteListener { task ->
                if (!closed) {
                    val detected = if (source !in listOf("auto", "chinese", "latin", "japanese", "korean", "devanagari")) source
                        else ((if (task.isSuccessful) task.result else null)?.substringBefore('-')?.takeIf { it != "und" } ?: if (Regex("[\\p{IsHan}]").containsMatchIn(page.text)) "zh" else "en")
                    callback(page.copy(language = detected), null)
                }
            }
        }.addOnFailureListener { if (!closed) callback(null, it) }
    }
    companion object {
        // Mask pixels before ML Kit groups them into words or identifies a script.
        // Post-recognition box tests alone cannot split mixed document/overlay words.
        // The fill follows nearby paper and extends past the window, so a hard white
        // edge or a leftover stroke is not read as a short fragment.
        internal fun maskOverlayPixels(frame: Bitmap, excluded: List<RectF>, expandPx: Float = 10f): Bitmap {
            if (excluded.isEmpty() || frame.width <= 0 || frame.height <= 0) return frame
            val result = if (frame.isMutable && frame.config != Bitmap.Config.HARDWARE) frame
                else frame.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = Canvas(result)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val bounds = RectF(0f, 0f, result.width.toFloat(), result.height.toFloat())
            for (box in excluded) {
                val cover = RectF(box).apply { inset(-expandPx, -expandPx) }
                if (!cover.intersect(bounds)) continue
                paint.color = samplePaper(result, cover)
                canvas.drawRect(cover, paint)
            }
            return result
        }

        private fun samplePaper(bitmap: Bitmap, cover: RectF): Int {
            val samples = ArrayList<Int>(8)
            val xs = floatArrayOf(cover.left - 2f, cover.centerX(), cover.right + 2f)
            val ys = floatArrayOf(cover.top - 2f, cover.centerY(), cover.bottom + 2f)
            for (y in ys) for (x in xs) {
                if (cover.contains(x, y)) continue
                val px = x.toInt()
                val py = y.toInt()
                if (px < 0 || py < 0 || px >= bitmap.width || py >= bitmap.height) continue
                samples.add(bitmap.getPixel(px, py))
            }
            return OcrNoise.paperColor(samples)
        }


        // Browser chrome can contain a short Chinese tooltip over a long Latin
        // article. Remove minority-script letters only from the language sample,
        // never from OCR text, positions or the actual translation request.
        internal fun languageSample(text:String):String {
            val latin=Regex("[\\p{IsLatin}]").findAll(text).count()
            val letters=text.count{it.isLetter()}
            if(latin>=60 && latin>=(letters-latin)*3) {
                return text.map{if(it.isLetter() && Character.UnicodeScript.of(it.code)!=Character.UnicodeScript.LATIN) ' ' else it}.joinToString("")
            }
            return text
        }
    }
    @Synchronized fun close() { closed = true; recognizers.values.forEach { it.close() }; identifier.close() }
}
