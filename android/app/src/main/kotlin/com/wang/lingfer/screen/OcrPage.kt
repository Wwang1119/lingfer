package com.wang.lingfer.screen

import android.graphics.RectF
import com.google.mlkit.vision.text.Text

/** Offsets use UTF-16 on Android, Dart and iOS. Geometry comes from OCR, never the LLM. */
data class OcrWord(val text: String, val box: RectF, val start: Int, val end: Int)
data class OcrLine(val id: String, val text: String, val box: RectF, val start: Int, val words: List<OcrWord>, val paragraphId: String = id)
data class OcrPage(val lines: List<OcrLine>, val width: Int, val height: Int, val language: String = "en") {
    val text get() = lines.joinToString("\n") { it.text }
    val words get() = lines.flatMap { it.words }
    val paragraphs: List<PageParagraph> get() = lines.groupBy { it.paragraphId }.map { (id, lines) ->
        val original = buildString {
            for (line in lines) {
                val value = line.text.trim()
                if (value.isEmpty()) continue
                val before = lastOrNull()
                val cjkWrap = (language == "zh" || language == "ja") && before != null && (before.code > 255 || value.first().code > 255)
                if (before != null && before != '-' && !cjkWrap) append(' ')
                append(value)
            }
        }
        PageParagraph(id, original)
    }

    val readingParagraphs: List<PageParagraph>
        get() {
            val readable = paragraphs.filter { isReadingParagraph(it.source) }
            val rows = lines.groupBy { it.paragraphId }
            val prose = lines.filter { it.box.width() >= width * .24f && it.text.count(Char::isLetter) >= 24 }
            if (prose.size < 3) return readable
            val shortLabels = readable.filter { readingWords.findAll(it.source).take(5).count() <= 4 && it.source.length < 33 }
                .mapNotNull { part -> rows[part.id]?.firstOrNull()?.let { part.id to it.box } }.toMap()
            return readable.filter { part ->
                val box = shortLabels[part.id] ?: return@filter true
                val tolerance = maxOf(box.height(), width * .018f)
                // Section headings align with the prose column. Short, differently
                // aligned labels crowded into a diagram are not page paragraphs.
                prose.count { kotlin.math.abs(it.box.left - box.left) <= tolerance } >= 2 ||
                    shortLabels.values.count { kotlin.math.abs(it.centerY() - box.centerY()) < box.height() * 4 } < 3
            }
        }

    fun paragraphFor(hit: WordHit): PageParagraph? {
        val start = hit.sourceStart ?: return null
        val end = hit.sourceEnd ?: return null
        if (start < 0 || end <= start || end > text.length || !text.substring(start, end).equals(hit.surface, ignoreCase = true)) return null
        val selected = lines.filter { start < it.start + it.text.length && end > it.start }
        val id = selected.firstOrNull()?.paragraphId ?: return null
        return if (selected.all { it.paragraphId == id }) paragraphs.first { it.id == id } else null
    }
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
        private val readingWords = Regex("""\p{L}[\p{L}\p{M}'’–-]*""")
        internal fun isReadingParagraph(source: String): Boolean {
            val words = readingWords.findAll(source).map { it.value }.toList()
            if (words.isEmpty()) return false
            val letters = source.count(Char::isLetter)
            // Short CJK headings are meaningful; a lone diagram glyph or margin
            // icon is not a paragraph. Ignore formula variables and bare page numbers.
            if (source.any { Character.UnicodeScript.of(it.code) in cjkScripts }) return letters >= 2
            if (words.size == 1) return letters >= 5
            return letters >= 5 && words.any { it.count(Char::isLetter) >= 2 }
        }

        private val cjkScripts = setOf(Character.UnicodeScript.HAN, Character.UnicodeScript.HIRAGANA,
            Character.UnicodeScript.KATAKANA, Character.UnicodeScript.HANGUL)

        fun geometry(box: RectF): Map<String, Any> = mapOf("left" to box.left.toDouble(), "top" to box.top.toDouble(), "width" to box.width().toDouble(), "height" to box.height().toDouble())
        internal fun groupParagraphs(lines: List<OcrLine>): List<OcrLine> {
            val rowSteps = ArrayDeque<Float>()
            var paragraphId = ""
            var rightEdge = 0f
            return lines.mapIndexed { index, line ->
                val previous = lines.getOrNull(index - 1)
                if (previous == null || !continuesParagraph(previous, line, rowSteps, rightEdge)) {
                    paragraphId = line.id
                    rightEdge = line.box.right
                    rowSteps.clear()
                } else {
                    rightEdge = maxOf(rightEdge, line.box.right)
                    rowSteps.addLast(line.box.centerY() - previous.box.centerY())
                    if (rowSteps.size > 3) rowSteps.removeFirst()
                }
                line.copy(paragraphId = paragraphId)
            }
        }

        private fun continuesParagraph(previous: OcrLine, next: OcrLine, rowSteps: Collection<Float>, rightEdge: Float): Boolean {
            val a = previous.box
            val b = next.box
            val height = maxOf(a.height(), b.height())
            val step = b.centerY() - a.centerY()
            val overlap = minOf(a.right, b.right) - maxOf(a.left, b.left)
            if (step < height * .45f || step > height * 3.4f || overlap < minOf(a.width(), b.width()) * .5f) return false
            if (minOf(a.height(), b.height()) < height * .65f || b.left - a.left > height * .75f) return false

            val ending = previous.text.trimEnd().trimEnd('"', '\'', '”', '’', '」', '』', ')', '）').lastOrNull()
            val sentenceEnded = ending != null && ending in ".!?。！？:："
            val firstLetter = next.text.firstOrNull { it.isLetterOrDigit() }
            val continuation = firstLetter?.let { it.isLetter() && !it.isUpperCase() } == true
            val sameBlock = previous.paragraphId == next.paragraphId
            val normalStep = rowSteps.takeIf { it.isNotEmpty() }?.average()?.toFloat()
            // A new paragraph can add only a small margin to very generous line
            // spacing. Compare to this paragraph's rhythm, not a fixed glyph gap.
            val margin = if (sentenceEnded || !continuation) .10f else .23f
            if (normalStep != null && step > normalStep + maxOf(height * .2f, normalStep * margin)) return false
            if (sentenceEnded) {
                if (!sameBlock) return normalStep != null && rightEdge - a.right < height * .7f &&
                    kotlin.math.abs(step - normalStep) <= maxOf(height * .12f, normalStep * .04f)
                return normalStep != null || b.top - a.bottom <= height * .55f
            }
            // Some readers place every wrapped line in a separate ML Kit block.
            // An unfinished sentence, matching column and comparable type can
            // still continue across that boundary, without swallowing a heading.
            if (previous.text.any { it.isLetter() } && previous.text.none { it.isLowerCase() } &&
                previous.text.any { it.isUpperCase() }) return false
            if (a.height() > b.height() * 1.35f && !continuation) return false
            return continuation || (sameBlock && b.top - a.bottom <= height * .85f) || normalStep != null
        }

        fun from(result: Text, width: Int, height: Int, excluded: List<RectF> = emptyList(), screenChrome: Boolean = false): OcrPage {
            val masks = excluded.map { ReadingBox(it.left, it.top, it.right, it.bottom).inflate(4f) }
            var offset = 0
            val lines = mutableListOf<OcrLine>()
            for ((blockIndex, block) in result.textBlocks.withIndex()) for (line in block.lines) {
                val box = line.boundingBox?.let { RectF(it) } ?: continue
                if (excluded.any { it.contains(box) }) continue
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
                        if (OcrNoise.wordBlocked(ReadingBox(wordBox.left, wordBox.top, wordBox.right, wordBox.bottom), surface.count(Char::isLetter), masks)) {
                            for (index in local until minOf(local+surface.length, cleanText.size)) cleanText[index] = ' '
                            continue
                        }
                        words.add(OcrWord(surface, wordBox, start+local, start+local+surface.length))
                    }
                }
                val value = String(cleanText)
                if (value.isBlank()) continue
                lines.add(OcrLine("s${lines.size}", value, box, start, words, "b$blockIndex"))
                offset = start+value.length
            }
            return OcrPage(groupParagraphs(suppressOverlayNoise(lines, width, height, excluded, screenChrome)), width, height)
        }

        /**
         * Drop overlay words, status-bar crumbs, and short pieces glued to a mask.
         * A real paragraph that only touches the mask keeps its remaining words.
         * [screenChrome] stays off for in-app photo OCR, which has no status band.
         */
        internal fun suppressOverlayNoise(
            lines: List<OcrLine>,
            width: Int,
            height: Int,
            excluded: List<RectF>,
            screenChrome: Boolean,
        ): List<OcrLine> {
            val masks = excluded.map { ReadingBox(it.left, it.top, it.right, it.bottom).inflate(4f) }
            val kept = mutableListOf<OcrLine>()
            for (line in lines) {
                val words = line.words.filter { word ->
                    !OcrNoise.wordBlocked(
                        ReadingBox(word.box.left, word.box.top, word.box.right, word.box.bottom),
                        word.text.count(Char::isLetter),
                        masks,
                    )
                }
                val chars = line.text.toCharArray()
                for (word in line.words) {
                    if (word in words) continue
                    val localStart = word.start - line.start
                    val localEnd = word.end - line.start
                    for (index in localStart until localEnd) if (index in chars.indices) chars[index] = ' '
                }
                val text = String(chars)
                val box = ReadingBox(line.box.left, line.box.top, line.box.right, line.box.bottom)
                if (text.isBlank()) continue
                if (screenChrome && isOverlayLine(text)) continue
                if (screenChrome && OcrNoise.chromeCrumb(text, box, height, ::isReadingParagraph)) continue
                if (OcrNoise.gluedFragment(text, box, masks, ::isReadingParagraph)) continue
                kept.add(if (text == line.text && words == line.words) line else line.copy(text = text, words = words))
            }
            return kept
        }
    }
}
