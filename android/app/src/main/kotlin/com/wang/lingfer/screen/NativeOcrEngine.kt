package com.wang.lingfer.screen

import android.graphics.Bitmap
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

    fun recognize(bitmap: Bitmap, source: String, excluded: List<RectF> = emptyList(), callback: (OcrPage?, Exception?) -> Unit) {
        recognize(InputImage.fromBitmap(bitmap, 0), bitmap.width, bitmap.height, source, excluded, callback)
    }

    fun recognize(image: InputImage, width: Int, height: Int, source: String, excluded: List<RectF> = emptyList(), callback: (OcrPage?, Exception?) -> Unit) {
        if (closed) return
        recognizer(source).process(image).addOnSuccessListener { text ->
            if (closed) return@addOnSuccessListener
            val page = OcrPage.from(text, width, height, excluded)
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
