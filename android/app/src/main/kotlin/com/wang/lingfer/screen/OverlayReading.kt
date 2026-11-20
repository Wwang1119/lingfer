package com.wang.lingfer.screen

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Decisions for the live reading overlay that do not need a window or a bitmap.
 * The view and OCR code call these so a scroll, a card, and a mask stay one behavior.
 */
internal const val OVERLAY_FLAG_SLIPPERY = 0x20000000

internal data class ReadingBox(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val centerX: Float get() = (left + right) / 2f
    val centerY: Float get() = (top + bottom) / 2f
    val isEmpty: Boolean get() = width <= 0f || height <= 0f

    fun contains(x: Float, y: Float) = x >= left && x < right && y >= top && y < bottom

    fun intersects(other: ReadingBox): Boolean =
        left < other.right && right > other.left && top < other.bottom && bottom > other.top

    fun intersectionArea(other: ReadingBox): Float {
        val w = min(right, other.right) - max(left, other.left)
        val h = min(bottom, other.bottom) - max(top, other.top)
        return if (w <= 0f || h <= 0f) 0f else w * h
    }

    fun inflate(pad: Float) = ReadingBox(left - pad, top - pad, right + pad, bottom + pad)

    fun coerceInside(bounds: ReadingBox): ReadingBox {
        val w = width
        val h = height
        val x = left.coerceIn(bounds.left, max(bounds.left, bounds.right - w))
        val y = top.coerceIn(bounds.top, max(bounds.top, bounds.bottom - h))
        return ReadingBox(x, y, x + w, y + h)
    }
}

internal object OverlayGesture {
    /** A paragraph or word opens only when the finger settles. Past the slop, the reader keeps the scroll. */
    fun isTap(dx: Float, dy: Float, slop: Float) = abs(dx) <= slop && abs(dy) <= slop
}

/**
 * Invisible hit beside the first line only. Nothing is drawn here.
 * A long paragraph does not get a handle at its vertical centre.
 * Returns null when the hit would cover the text or sit on the bezel.
 */
internal fun firstLineTarget(
    text: ReadingBox,
    safe: ReadingBox,
    right: Boolean,
    width: Float,
    lineHeight: Float,
    edgeInset: Float,
    gap: Float,
): ReadingBox? {
    val height = lineHeight.coerceAtMost(28f)
    if (width <= 0f || height < 8f || safe.width < width + edgeInset * 2) return null
    val top = text.top.coerceIn(safe.top, (safe.bottom - height).coerceAtLeast(safe.top))
    if (top > text.top + 1f) return null
    val x = if (right) {
        val minX = text.right + gap
        val maxX = safe.right - edgeInset - width
        if (minX > maxX + 0.5f) return null
        minX
    } else {
        val maxX = text.left - gap - width
        val minX = safe.left + edgeInset
        if (maxX + 0.5f < minX) return null
        maxX
    }
    val box = ReadingBox(x, top, x + width, top + height)
    if (box.intersects(text)) return null
    if (box.left < safe.left + edgeInset - 0.5f || box.right > safe.right - edgeInset + 0.5f) return null
    return box
}

/** Shorter hits, with a gap, so a dense margin never becomes one solid touch column. */
internal fun firstLineHeights(tops: List<Float>, desired: Float, gap: Float, minimum: Float): List<Float> {
    if (tops.isEmpty()) return emptyList()
    val order = tops.indices.sortedBy { tops[it] }
    val heights = FloatArray(tops.size)
    for (position in order.indices) {
        val index = order[position]
        val next = order.getOrNull(position + 1)?.let { tops[order[it]] }
        val room = if (next == null) desired else next - tops[index] - gap
        val height = min(desired, room)
        heights[index] = if (height < minimum) 0f else height
    }
    return heights.toList()
}

/** The captured page went away, so the overlay must not stay on top of something else. */
internal fun clearOverlayWhenCaptureHidden(captureVisible: Boolean) = !captureVisible

/** Keep a card beside the paragraph when that paragraph only shifts. */
internal fun followCard(card: ReadingBox, from: ReadingBox, to: ReadingBox, safe: ReadingBox): ReadingBox {
    val dx = to.centerX - from.centerX
    val dy = to.centerY - from.centerY
    return ReadingBox(card.left + dx, card.top + dy, card.right + dx, card.bottom + dy).coerceInside(safe)
}

internal fun sourceRelated(a: String, b: String): Boolean {
    val left = a.trim()
    val right = b.trim()
    if (left.isEmpty() || right.isEmpty()) return false
    if (left == right) return true
    val sample = 24
    if (left.length >= sample && right.contains(left.take(sample))) return true
    if (right.length >= sample && left.contains(right.take(sample))) return true
    return false
}

/** True when this OCR page is still the page the card was opened on. */
internal fun sharesPage(previous: Set<String>, incoming: Collection<String>): Boolean {
    if (previous.isEmpty() || incoming.isEmpty()) return false
    val hits = previous.count { prev -> incoming.any { sourceRelated(prev, it) } }
    return hits * 2 >= previous.size
}

internal object ReadingPlacement {
    /**
     * Put the note beside the paragraph when the margin can hold it, otherwise above or below.
     * Covering the selected paragraph is only the last resort, when the page has no open space.
     */
    fun card(
        column: ReadingBox,
        marker: ReadingBox,
        width: Float,
        height: Float,
        safe: ReadingBox,
        avoid: List<ReadingBox>,
        gap: Float,
    ): ReadingBox {
        val clear = mutableListOf<ReadingBox>()
        fun offer(raw: ReadingBox) {
            val box = raw.coerceInside(safe)
            if (box.width + 0.5f < width || box.height + 0.5f < height) return
            if (box.intersects(column) || box.intersects(marker)) return
            if (avoid.any { box.intersects(it) }) return
            clear.add(box)
        }
        if (safe.right - column.right - gap >= width) {
            offer(ReadingBox(column.right + gap, marker.top, column.right + gap + width, marker.top + height))
        }
        if (column.left - safe.left - gap >= width) {
            offer(ReadingBox(column.left - gap - width, marker.top, column.left - gap, marker.top + height))
        }
        offer(ReadingBox(column.left, column.bottom + gap, column.left + width, column.bottom + gap + height))
        offer(ReadingBox(column.left, column.top - gap - height, column.left + width, column.top - gap))
        if (clear.isNotEmpty()) {
            return clear.minBy { box ->
                val dx = max(0f, abs(marker.centerX - box.centerX) - box.width / 2f)
                val dy = max(0f, abs(marker.centerY - box.centerY) - box.height / 2f)
                val beside = box.left >= column.right - 1f || box.right <= column.left + 1f
                // An open margin keeps this paragraph and the next one readable.
                dx + dy + if (beside) -720f else 0f
            }
        }
        fun fallback(x: Float, y: Float) = ReadingBox(x, y, x + width, y + height).coerceInside(safe)
        val crowded = listOf(
            fallback(column.right + gap, marker.top),
            fallback(column.left - width - gap, marker.top),
            fallback(column.left, column.bottom + gap),
            fallback(column.left, column.top - height - gap),
            fallback(column.left, marker.bottom + gap),
            fallback(column.left, marker.top - height - gap),
        )
        return crowded.minBy { box ->
            val covered = box.intersectionArea(column) + box.intersectionArea(marker) +
                avoid.sumOf { box.intersectionArea(it).toDouble() }
            val dx = max(0f, abs(marker.centerX - box.centerX) - box.width / 2f)
            val dy = max(0f, abs(marker.centerY - box.centerY) - box.height / 2f)
            covered * 4 + dx + dy
        }
    }
}

internal object OcrNoise {
    fun luminance(rgb: Int): Int {
        val r = (rgb shr 16) and 0xFF
        val g = (rgb shr 8) and 0xFF
        val b = rgb and 0xFF
        return (r * 299 + g * 587 + b * 114) / 1000
    }

    /** Nearby paper wins. Ink is never used as a fill, or the mask itself becomes a glyph. */
    fun paperColor(samples: List<Int>, fallback: Int = 0xFFFFFFFF.toInt()): Int {
        val paper = samples.filter { luminance(it) >= 186 }
        if (paper.isEmpty()) return fallback
        return paper.maxBy { luminance(it) }
    }

    /** Status and navigation bands. Capped so a short capture is not painted away. */
    fun chromeHeight(viewHeight: Int, minPx: Float, fraction: Float, capFraction: Float): Float {
        if (viewHeight <= 0) return 0f
        return max(minPx, viewHeight * fraction).coerceAtMost(viewHeight * capFraction)
    }

    fun wordBlocked(word: ReadingBox, letters: Int, masks: List<ReadingBox>): Boolean {
        if (word.isEmpty || masks.isEmpty()) return false
        val area = (word.width * word.height).coerceAtLeast(1f)
        return masks.any { mask ->
            val overlap = word.intersectionArea(mask)
            overlap > 0f && (mask.contains(word.centerX, word.centerY) || overlap / area >= 0.22f || letters <= 2)
        }
    }

    /** A short token that sits entirely in the status or navigation band. */
    fun chromeCrumb(text: String, box: ReadingBox, height: Int, isReading: (String) -> Boolean): Boolean {
        if (height <= 0) return false
        val topBand = height * 0.05f
        val bottomBand = height * 0.04f
        val inChrome = box.bottom <= topBand + 0.5f || box.top >= height - bottomBand - 0.5f
        if (!inChrome) return false
        val value = text.trim()
        return value.isEmpty() || !isReading(value)
    }

    /** A remnant stuck to an overlay edge, such as a cut syllable or a missed 译. */
    fun gluedFragment(text: String, box: ReadingBox, masks: List<ReadingBox>, isReading: (String) -> Boolean): Boolean {
        if (masks.isEmpty()) return false
        val value = text.trim()
        if (value.isEmpty()) return masks.any { box.intersects(it) }
        if (isReading(value) || value.count { it.isLetter() } >= 5) return false
        return masks.any { box.intersects(it.inflate(2f)) }
    }
}

/**
 * follow: the same paragraph is still on the page. Keep its translation and move with its box.
 * update: a new translation arrived for that same paragraph.
 * live: the paragraph is visible but the note is still loading or explaining an error.
 * keep-covered: this page is unchanged and the card itself is likely hiding the paragraph. Do not call it a page turn.
 * departed: a large scroll or another page. Do not keep the old translation over new text.
 */
internal fun cardMotion(
    sourceVisible: Boolean,
    shownTranslation: String?,
    shownExists: Boolean,
    matchedTranslation: String?,
    samePage: Boolean,
): String = when {
    sourceVisible && !matchedTranslation.isNullOrBlank() && matchedTranslation != shownTranslation -> "update"
    sourceVisible && !shownTranslation.isNullOrBlank() -> "follow"
    sourceVisible -> "live"
    shownExists && samePage -> "keep-covered"
    shownExists -> "departed"
    else -> "none"
}

/** Lines that are the overlay's own labels, not the book. */
internal val overlayLines = setOf(
    "译",
    "收起",
    "收起本段译文",
    "原文",
    "正在翻译此段…",
    "此段暂未译出。",
    "回语渡设置",
    "切换译文语言",
    "重试翻译",
    "原段已离开这一页",
    "还停在原来的这一段",
)

internal fun isOverlayLine(text: String) = text.trim().trimEnd('。') in overlayLines || text.trim() in overlayLines

/** Host and instrumentation both call this. It does not need a device. */
internal fun verifyOverlayReadingRules() {
    val wide = ReadingBox(0f, 0f, 1200f, 1800f)
    val column = ReadingBox(80f, 240f, 460f, 360f)
    val beside = ReadingPlacement.card(column, ReadingBox(40f, 250f, 48f, 258f), 280f, 160f, wide, emptyList(), 8f)
    check(!beside.intersects(column) && beside.left >= column.right) { "The note covered the paragraph although the margin was open" }

    val phone = ReadingBox(0f, 40f, 400f, 800f)
    val full = ReadingBox(36f, 120f, 360f, 200f)
    val below = ReadingPlacement.card(full, ReadingBox(20f, 140f, 28f, 148f), 250f, 140f, phone, emptyList(), 8f)
    check(!below.intersects(full) && below.top >= full.bottom) { "A full-width paragraph should keep the note off its own lines" }

    val edge = firstLineTarget(column, wide, false, 18f, 20f, 16f, 6f)
    check(edge != null && edge.right <= column.left && edge.top == column.top && edge.height <= 28f && !edge.intersects(column))
    val tall = ReadingBox(80f, 100f, 460f, 520f)
    val atFirstLine = firstLineTarget(tall, wide, false, 18f, 22f, 16f, 6f)
    check(atFirstLine != null && atFirstLine.top == tall.top && atFirstLine.centerY < tall.centerY - 80f) {
        "A long paragraph got a handle at its middle"
    }
    val tight = firstLineTarget(ReadingBox(10f, 40f, 80f, 80f), ReadingBox(0f, 0f, 100f, 200f), false, 18f, 20f, 16f, 6f)
    check(tight == null) { "A hit area covered the text or the bezel" }
    val dense = firstLineHeights(List(12) { it * 16f }, desired = 22f, gap = 8f, minimum = 12f)
    check(dense.count { it > 0f } <= 2) { "Dense lines still produce a solid column of targets" }
    check(dense.zip(List(12) { it * 16f }).filter { it.first > 0f }.zipWithNext().all { (a, b) -> b.second >= a.second + a.first + 8f })
    check(clearOverlayWhenCaptureHidden(true).not() && clearOverlayWhenCaptureHidden(false))

    val followed = followCard(ReadingBox(500f, 200f, 780f, 360f), column, ReadingBox(column.left, column.top + 36f, column.right, column.bottom + 36f), wide)
    check(followed.top - 200f > 20f && !followed.intersects(ReadingBox(column.left, column.top + 36f, column.right, column.bottom + 36f)))

    check(cardMotion(true, "译文", true, null, true) == "follow")
    check(cardMotion(true, "译文", true, "新译文", true) == "update")
    check(cardMotion(true, null, true, null, true) == "live")
    check(cardMotion(false, "译文", true, null, true) == "keep-covered")
    check(cardMotion(false, "译文", true, null, false) == "departed")
    check(sourceRelated("Second paragraph.", "Second paragraph."))
    check(!sourceRelated("Second paragraph.", "Recycled id."))
    check(sharesPage(setOf("First paragraph.", "Second paragraph."), listOf("First paragraph.")))
    check(!sharesPage(setOf("First paragraph.", "Second paragraph."), listOf("Recycled id.")))

    check(OverlayGesture.isTap(2f, 3f, 8f) && !OverlayGesture.isTap(2f, 30f, 8f))
    check(isOverlayLine("译") && isOverlayLine("收起") && isOverlayLine("原段已离开这一页"))
    check(!isOverlayLine("Researchers maintain that consistent practice matters."))
    val mask = listOf(ReadingBox(0f, 0f, 40f, 20f))
    check(OcrNoise.wordBlocked(ReadingBox(30f, 8f, 70f, 24f), 1, mask))
    check(!OcrNoise.wordBlocked(ReadingBox(48f, 8f, 120f, 24f), 8, mask))
    check(OcrNoise.chromeCrumb("1X1à", ReadingBox(8f, 2f, 40f, 16f), 400) { false })
    check(!OcrNoise.chromeCrumb("Abstract", ReadingBox(8f, 2f, 80f, 16f), 400) { true })
    check(OcrNoise.gluedFragment("tion", ReadingBox(90f, 10f, 120f, 28f), listOf(ReadingBox(100f, 0f, 160f, 40f))) { false })
    check(!OcrNoise.gluedFragment("Researchers maintain that consistent practice matters.", ReadingBox(80f, 10f, 300f, 40f), listOf(ReadingBox(100f, 0f, 160f, 40f))) { true })
    check(OcrNoise.paperColor(listOf(0xFF111111.toInt(), 0xFFF7F4EA.toInt())) == 0xFFF7F4EA.toInt())
    check(OcrNoise.paperColor(listOf(0xFF101010.toInt())) == 0xFFFFFFFF.toInt())
    check(OcrNoise.chromeHeight(2400, 80f, 0.035f, 0.08f) in 80f..192f)
    check(OcrNoise.chromeHeight(400, 80f, 0.035f, 0.08f) <= 32f)
}
