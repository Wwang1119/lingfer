package com.wang.lingfer.screen

import android.graphics.RectF
import com.google.mlkit.vision.text.Text

/** Offsets use UTF-16 on Android, Dart and iOS. Geometry comes from OCR, never the LLM. */
data class OcrWord(val text: String, val box: RectF, val start: Int, val end: Int)
data class OcrLine(val id: String, val text: String, val box: RectF, val start: Int, val words: List<OcrWord>)
data class OcrPage(val lines: List<OcrLine>, val width: Int, val height: Int, val language: String = "en") {
    val text get() = lines.joinToString("\n") { it.text }
    val words get() = lines.flatMap { it.words }
    fun json(): Map<String, Any> = mapOf("text" to text, "imageWidth" to width, "imageHeight" to height,
        "detectedLanguage" to language, "lines" to lines.map { line ->
            geometry(line.box) + mapOf("id" to line.id, "text" to line.text, "words" to line.words.map { word ->
                geometry(word.box) + mapOf("text" to word.text, "start" to word.start-line.start, "end" to word.end-line.start)
            })
        })

    fun anchor(hit: WordHit): RectF? {
        var start = hit.sourceStart
        var end = hit.sourceEnd
        if (start == null || end == null) {
            val match = Regex(Regex.escape(hit.surface), RegexOption.IGNORE_CASE).find(text) ?: return null
            start = match.range.first; end = match.range.last+1
        }
        val selected = words.filter { it.start < end && it.end > start }
        if (selected.isEmpty()) return null
        return RectF(selected.first().box).apply { selected.drop(1).forEach { union(it.box) } }
    }

    companion object {
        fun geometry(box: RectF): Map<String, Any> = mapOf("left" to box.left.toDouble(), "top" to box.top.toDouble(), "width" to box.width().toDouble(), "height" to box.height().toDouble())
        fun from(result: Text, width: Int, height: Int, excluded: List<RectF> = emptyList()): OcrPage {
            var offset = 0
            val lines = mutableListOf<OcrLine>()
            for (line in result.textBlocks.flatMap { it.lines }) {
                val box = line.boundingBox?.let { RectF(it) } ?: continue
                if (excluded.any { it.contains(box.centerX(), box.centerY()) }) continue
                val start = offset + if (lines.isNotEmpty()) 1 else 0
                val cleanText = line.text.toCharArray()
                var cursor = 0
                val words = mutableListOf<OcrWord>()
                for (element in line.elements) {
                    val parts = if (Regex("[\\p{IsHan}\\p{IsHiragana}\\p{IsKatakana}\\p{IsHangul}]").containsMatchIn(element.text) && element.symbols.isNotEmpty())
                        element.symbols.mapNotNull { symbol -> symbol.boundingBox?.let { symbol.text to RectF(it) } }
                    else listOfNotNull(element.boundingBox?.let { element.text to RectF(it) })
                    for ((surface, wordBox) in parts) {
                        val local = line.text.indexOf(surface, cursor).takeIf { it >= 0 } ?: line.text.indexOf(surface)
                        if (local < 0) continue
                        cursor = local+surface.length
                        if (excluded.any { it.contains(wordBox.centerX(), wordBox.centerY()) }) {
                            for (index in local until minOf(local+surface.length, cleanText.size)) cleanText[index] = ' '
                            continue
                        }
                        words.add(OcrWord(surface, wordBox, start+local, start+local+surface.length))
                    }
                }
                val value = String(cleanText)
                if (value.isBlank()) continue
                lines.add(OcrLine("s${lines.size}", value, box, start, words))
                offset = start+value.length
            }
            return OcrPage(lines, width, height)
        }
    }
}
