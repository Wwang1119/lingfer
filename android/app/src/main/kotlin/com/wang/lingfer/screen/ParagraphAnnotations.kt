package com.wang.lingfer.screen

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Invisible first-line hits, and the open note. The resting page has nothing drawn on it. */
internal class ParagraphAnnotations(
    private val context: Context,
    private val windows: WindowManager,
    private val onRegionsChanged: () -> Unit,
    private val onRecovery: () -> Unit,
    private val onWindowChange: (Boolean) -> Unit = {},
) {
    private data class Anchor(val part: PageParagraph, val box: RectF, val lines: List<RectF>)
    private data class Mark(val anchor: Anchor, val bounds: RectF, val right: Boolean)
    private data class Note(val translation: String?, val message: String?, val recovery: String?, val cue: String? = null)

    private val marks = linkedMapOf<View, Mark>()
    private var wash: SourceWash? = null
    private var washRects: List<RectF> = emptyList()
    private var page: OcrPage? = null
    private var viewport = Rect()
    private var safe = RectF()
    private var avoid: List<RectF> = emptyList()
    private var parts: Map<String, PageParagraph> = emptyMap()
    private var knownSources: Set<String> = emptySet()
    private var loading = false
    private var error: String? = null
    private var pinned: Anchor? = null
    private var pinnedBox: RectF? = null
    private var displayed: Note? = null
    private var card: View? = null
    var persistentRegion: RectF? = null
        private set
    var regions: List<RectF> = emptyList()
        private set

    private fun dp(value: Int) = (context.resources.displayMetrics.density * value).roundToInt()

    fun show(page: OcrPage, parts: List<PageParagraph>, loading: Boolean, error: String?, screenArea: Rect, avoid: List<RectF>) {
        if (screenArea.isEmpty || page.width <= 0 || page.height <= 0) {
            hide()
            return
        }
        val incoming = parts.associateBy { it.id }
        val previousSources = knownSources
        knownSources = incoming.values.map { it.source }.filter { it.isNotBlank() }.toSet()
        val viewportChanged = viewport != screenArea
        val rebuild = this.page != page || viewportChanged || this.parts.keys != incoming.keys
        this.parts = incoming
        this.loading = loading
        this.error = error
        this.avoid = avoid.map(::RectF)
        this.page = page
        viewport = Rect(screenArea)
        safe = RectF(screenArea).apply {
            inset(dp(4).toFloat(), 0f)
            top += dp(25)
            bottom -= dp(27)
        }
        val anchor = pinned
        val located = anchor?.let { current -> locate(page, incoming, current) }
        val samePage = sharesPage(previousSources, knownSources)
        val motion = if (anchor == null) "none" else cardMotion(
            sourceVisible = located != null,
            shownTranslation = displayed?.translation,
            shownExists = displayed != null,
            matchedTranslation = located?.part?.translation,
            samePage = samePage,
        )
        val note = when (motion) {
            "update", "live" -> noteFor(located!!.part)
            "follow" -> (if (!displayed?.translation.isNullOrBlank()) displayed else noteFor(located!!.part))?.copy(cue = null)
            "keep-covered" -> displayed?.copy(cue = STILL)
            "departed" -> Note(null, DEPARTED, null)
            else -> null
        }
        val boxMoved = located != null && pinnedBox?.let { moved(it, located.box) } == true
        // A small move follows the paragraph. If the paragraph is still the one on
        // screen but its box cannot be seen, the card may stay and must say so.
        // A page turn drops the translation instead of pairing it with new text.
        val redraw = when (motion) {
            "none" -> false
            "keep-covered" -> displayed?.cue != STILL
            "departed" -> displayed?.message != DEPARTED
            else -> note != displayed || viewportChanged || boxMoved
        }
        if (!rebuild && !redraw) return
        val subject = if (motion == "departed" || motion == "keep-covered") anchor else located ?: anchor
        val mode = when {
            motion == "departed" -> "margin"
            motion == "keep-covered" -> "hold"
            boxMoved -> "follow"
            persistentRegion != null -> "hold"
            else -> "fresh"
        }
        mutate {
            if (rebuild) {
                removeMarks()
                if (safe.width() >= dp(42) && safe.height() > dp(20)) addMarks(page)
            }
            if (redraw && subject != null && note != null) showCard(subject, note, mode)
        }
    }

    private fun locate(page: OcrPage, incoming: Map<String, PageParagraph>, current: Anchor): Anchor? {
        val part = incoming[current.part.id]?.takeIf { it.source == current.part.source }
            ?: incoming.values.firstOrNull { sourceRelated(it.source, current.part.source) }
            ?: return null
        val lines = lineBoxes(page, part.id)
        if (lines.isEmpty()) return null
        val box = RectF(lines.first()).apply { lines.drop(1).forEach { union(it) } }
        return Anchor(part, box, lines)
    }

    private fun lineBoxes(page: OcrPage, id: String): List<RectF> {
        val map = AnnotationCoordinates(page.width, page.height, viewport)
        return page.lines.mapNotNull { line ->
            if (line.paragraphId != id) return@mapNotNull null
            val screen = map.toScreen(line.box)
            val visible = RectF(screen)
            if (!visible.intersect(safe) || visible.isEmpty) null else visible
        }
    }

    private fun anchorsFor(page: OcrPage): List<Anchor> {
        val map = AnnotationCoordinates(page.width, page.height, viewport)
        val boxes = mutableMapOf<String, RectF>()
        val lines = mutableMapOf<String, MutableList<RectF>>()
        for (line in page.lines) {
            if (line.paragraphId !in parts) continue
            val screen = map.toScreen(line.box)
            val visible = RectF(screen)
            if (!visible.intersect(safe) || visible.isEmpty) continue
            val previous = boxes[line.paragraphId]
            if (previous == null) boxes[line.paragraphId] = RectF(visible) else previous.union(visible)
            lines.getOrPut(line.paragraphId) { mutableListOf() }.add(visible)
        }
        return page.paragraphs.mapNotNull { paragraph ->
            boxes[paragraph.id]?.takeIf { parts[paragraph.id]?.source == paragraph.source }?.let { box ->
                Anchor(paragraph, box, lines[paragraph.id].orEmpty())
            }
        }
    }

    private fun addMarks(page: OcrPage) {
        val anchors = anchorsFor(page)
        if (anchors.isEmpty()) return
        val middle = safe.centerX()
        val slop = safe.width() * .025f
        val left = anchors.filter { it.box.right <= middle + slop && it.box.centerX() < middle - slop }
        val right = anchors.filter { it.box.left >= middle - slop && it.box.centerX() > middle + slop }
        val columns = left.isNotEmpty() && right.isNotEmpty() &&
            max(left.minOf { it.box.top }, right.minOf { it.box.top }) <= min(left.maxOf { it.box.bottom }, right.maxOf { it.box.bottom })
        val groups = if (columns) listOf((anchors - right.toSet()) to false, right to true) else listOf(anchors to false)
        val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        val safeBox = ReadingBox(safe.left, safe.top, safe.right, safe.bottom)
        val desired = dp(18).toFloat()
        val gap = dp(8).toFloat()
        for ((group, onRight) in groups) {
            val ordered = group.sortedBy { it.box.top }
            val heights = firstLineHeights(ordered.map { it.box.top }, desired, gap, dp(10).toFloat())
            for ((anchor, height) in ordered.zip(heights)) {
                if (height <= 0f) continue
                val place = firstLineTarget(
                    ReadingBox(anchor.box.left, anchor.box.top, anchor.box.right, anchor.box.bottom),
                    safeBox,
                    onRight,
                    dp(8).toFloat(),
                    height,
                    dp(2).toFloat(),
                    dp(4).toFloat(),
                ) ?: continue
                val bounds = RectF(place.left, place.top, place.right, place.bottom)
                val view = MarginHit(context).apply {
                    contentDescription = "翻译此段：${anchor.part.source.take(64)}"
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                    setOnClickListener { select(anchor) }
                }
                if (!attach(view, bounds, OVERLAY_FLAG_SLIPPERY)) continue
                bindOverlayTap(
                    view,
                    view.layoutParams as WindowManager.LayoutParams,
                    windows,
                    touchSlop,
                    onArm = { arm(view) },
                    onRelease = { disarm(view) },
                ) { view.performClick() }
                marks[view] = Mark(anchor, bounds, onRight)
            }
        }
    }

    private fun arm(view: MarginHit) {
        marks.keys.filterIsInstance<MarginHit>().forEach { if (it != view) it.armed = false }
        view.armed = true
    }

    private fun disarm(view: MarginHit) {
        view.armed = false
    }

    /**
     * A flat tint, not a material. The source lines get a trace of paper;
     * the rest of the page is only slightly quieter. No blur, stroke, or shadow.
     */
    private class SourceWash(context: Context) : View(context) {
        private var lines = emptyList<RectF>()
        private var originX = 0f
        private var originY = 0f
        private val dim = Paint().apply { color = Color.argb(14, 34, 40, 40) }
        private val paper = Paint().apply { color = Color.argb(24, 250, 249, 244) }
        init {
            setWillNotDraw(false)
            background = null
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            contentDescription = "原文范围"
        }
        fun update(rects: List<RectF>, bounds: RectF) {
            originX = bounds.left
            originY = bounds.top
            lines = rects
            invalidate()
        }
        override fun onDraw(canvas: Canvas) {
            if (lines.isEmpty() || width <= 0 || height <= 0) return
            val local = lines.map { RectF(it.left - originX, it.top - originY, it.right - originX, it.bottom - originY) }
            canvas.save()
            val path = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
                local.forEach { addRect(it, Path.Direction.CW) }
            }
            canvas.clipPath(path)
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dim)
            canvas.restore()
            local.forEach { canvas.drawRect(it, paper) }
        }
    }

    /** Nothing at rest. While the finger is down, one hairline beside that first line. */
    private class MarginHit(context: Context) : View(context) {
        var armed = false
            set(value) {
                if (field == value) return
                field = value
                invalidate()
            }
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(70, 54, 95, 112)
            strokeCap = Paint.Cap.ROUND
            style = Paint.Style.STROKE
        }
        private val density = resources.displayMetrics.density
        init {
            setWillNotDraw(false)
            background = null
        }

        override fun onDraw(canvas: Canvas) {
            if (!armed) return
            paint.strokeWidth = max(1f, .8f * density)
            val y = height / 2f
            canvas.drawLine(width * .2f, y, width * .8f, y, paint)
        }
    }

    private fun noteFor(part: PageParagraph): Note = when {
        !part.translation.isNullOrBlank() -> Note(part.translation, null, null)
        error == NativeAiConsent.prompt -> Note(null, error, "回语渡设置")
        error?.contains("相同语言") == true -> Note(null, error, "切换译文语言")
        error != null -> Note(null, error, "重试翻译")
        loading -> Note(null, "正在翻译此段…", null)
        else -> Note(null, "此段暂未译出。", "重试翻译")
    }

    private fun select(anchor: Anchor) {
        val live = marks.values.firstOrNull {
            it.anchor.part.id == anchor.part.id && it.anchor.part.source == anchor.part.source
        }?.anchor ?: return
        val part = parts[live.part.id]?.takeIf { it.source == live.part.source } ?: return
        if (pinned?.part?.id == live.part.id && pinned?.part?.source == live.part.source && card != null && displayed?.message != DEPARTED) return
        mutate { showCard(Anchor(part, live.box, live.lines), noteFor(part), "fresh") }
    }

    private fun showCard(anchor: Anchor, note: Note, mode: String) {
        if (safe.isEmpty) return
        val gap = dp(8).toFloat()
        val inner = RectF(safe)
        val wide = safe.width() >= dp(600)
        val widthCap = if (wide) safe.width() * .40f else safe.width() * .46f
        val maxWidth = minOf(dp(280).toFloat(), widthCap, inner.width())
        val maxHeight = min(dp(420), (safe.height() * .46f).roundToInt())
            .coerceAtLeast(min(dp(148), safe.height().roundToInt().coerceAtLeast(1)))
            .coerceAtMost(safe.height().roundToInt().coerceAtLeast(1))
        val slot = if (mode == "margin" || note.message == DEPARTED || note.cue == STILL) null else clearSheet(
            ReadingBox(anchor.box.left, anchor.box.top, anchor.box.right, anchor.box.bottom),
            ReadingBox(inner.left, inner.top, inner.right, inner.bottom),
            maxWidth,
            maxHeight.toFloat(),
            min(dp(148).toFloat(), maxWidth),
            min(dp(112).toFloat(), maxHeight.toFloat()),
            gap,
        )
        val width = (slot?.width ?: maxWidth).roundToInt().coerceAtLeast(1)
        val heightLimit = (slot?.height ?: maxHeight.toFloat()).roundToInt().coerceIn(1, maxHeight)
        val view = makeCard(anchor, note, width, heightLimit)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightLimit, View.MeasureSpec.AT_MOST),
        )
        val height = view.measuredHeight.toFloat()
        val box = if (slot != null && mode != "hold" && mode != "margin") {
            RectF(slot.left, slot.top, slot.left + width, (slot.top + height).coerceAtMost(slot.bottom))
        } else when (mode) {
            "margin" -> ParagraphPlacement.fit(inner.left + gap, inner.bottom - height - gap, width.toFloat(), height, inner)
            "follow" -> followedBox(anchor.box, width.toFloat(), height, inner) ?: freshBox(anchor, width.toFloat(), height, inner, gap)
            "hold" -> persistentRegion?.let { ParagraphPlacement.fit(it.left, it.top, width.toFloat(), height, inner) }
                ?: freshBox(anchor, width.toFloat(), height, inner, gap)
            else -> freshBox(anchor, width.toFloat(), height, inner, gap)
        }
        if (note.message == DEPARTED || note.cue == STILL || anchor.lines.isEmpty()) removeWash()
        else showWash(anchor.lines)
        if (attach(view, box)) {
            card?.let(::detach)
            pinned = anchor
            pinnedBox = RectF(anchor.box)
            displayed = note
            card = view
            persistentRegion = box
        }
    }

    private fun showWash(lines: List<RectF>) {
        val rects = sourceWash(
            lines.map { ReadingBox(it.left, it.top, it.right, it.bottom) },
            dp(2).toFloat(),
            dp(1).toFloat(),
        ).map { RectF(it.left, it.top, it.right, it.bottom) }
        if (rects.isEmpty()) {
            removeWash()
            return
        }
        val bounds = RectF(viewport)
        val existing = wash?.layoutParams as? WindowManager.LayoutParams
        val sameWindow = existing != null && existing.x == bounds.left.roundToInt() &&
            existing.y == bounds.top.roundToInt() && existing.width == bounds.width().roundToInt() &&
            existing.height == bounds.height().roundToInt()
        if (!sameWindow) {
            removeWash()
            val view = SourceWash(context)
            if (!attach(view, bounds, WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)) return
            wash = view
        }
        washRects = rects
        wash?.update(rects, bounds)
    }

    private fun removeWash() {
        wash?.let(::detach)
        wash = null
        washRects = emptyList()
    }

    private fun followedBox(next: RectF, width: Float, height: Float, inner: RectF): RectF? {
        val from = pinnedBox ?: return null
        val previous = persistentRegion ?: return null
        val shifted = followCard(
            ReadingBox(previous.left, previous.top, previous.right, previous.bottom),
            ReadingBox(from.left, from.top, from.right, from.bottom),
            ReadingBox(next.left, next.top, next.right, next.bottom),
            ReadingBox(inner.left, inner.top, inner.right, inner.bottom),
        )
        val fitted = ParagraphPlacement.fit(shifted.left, shifted.top, width, height, inner)
        val column = ReadingBox(next.left, next.top, next.right, next.bottom)
        val placed = ReadingBox(fitted.left, fitted.top, fitted.right, fitted.bottom)
        if (placed.intersects(column)) return null
        return fitted
    }

    private fun freshBox(anchor: Anchor, width: Float, height: Float, inner: RectF, gap: Float): RectF {
        val mark = marks.values.minByOrNull { abs(it.bounds.centerX() - anchor.box.centerX()) }
        val x = mark?.bounds?.centerX() ?: anchor.box.left
        val obstacles = avoid + marks.values.map { it.bounds }
        val placed = ReadingPlacement.card(
            ReadingBox(anchor.box.left, anchor.box.top, anchor.box.right, anchor.box.bottom),
            ReadingBox(x, anchor.box.top, x + 1f, anchor.box.top + 1f),
            width,
            height,
            ReadingBox(inner.left, inner.top, inner.right, inner.bottom),
            obstacles.map { ReadingBox(it.left, it.top, it.right, it.bottom) },
            gap,
        )
        return RectF(placed.left, placed.top, placed.right, placed.bottom)
    }

    private fun makeCard(anchor: Anchor, note: Note, width: Int, maxHeight: Int): View {
        val face = Typeface.SERIF
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(16), dp(10))
            background = GradientDrawable().apply {
                setColor(NativeReadingStyle.readingPaper)
                cornerRadius = dp(18).toFloat()
                setStroke(1, Color.rgb(228, 226, 220))
            }
            clipToOutline = true
            elevation = 0f
            isClickable = true
        }
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }
        body.addView(TextView(context).apply {
            text = note.translation ?: note.message
            textSize = if (note.translation != null) 17.5f else 15.5f
            typeface = face
            setLineSpacing(dp(7).toFloat(), 1.12f)
            setTextColor(if (note.translation != null) NativeReadingStyle.ink else NativeReadingStyle.muted)
        })
        note.cue?.let { cue ->
            body.addView(TextView(context).apply {
                text = cue
                textSize = 13f
                typeface = face
                setTextColor(NativeReadingStyle.muted)
                setPadding(0, dp(8), 0, 0)
            })
        }
        note.recovery?.let { label ->
            body.addView(TextView(context).apply {
                text = label
                textSize = 14f
                typeface = face
                setTextColor(NativeReadingStyle.accent)
                background = null
                setPadding(0, dp(8), 0, 0)
                setOnClickListener { onRecovery() }
            })
        }
        body.measure(
            View.MeasureSpec.makeMeasureSpec((width - dp(34)).coerceAtLeast(1), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val scroll = ScrollView(context).apply {
            contentDescription = "本段译文"
            isFillViewport = false
            addView(body)
        }
        val reserved = dp(52)
        val room = (maxHeight - reserved).coerceAtLeast(dp(96))
        val bodyHeight = if (body.measuredHeight > room) room else LinearLayout.LayoutParams.WRAP_CONTENT
        panel.addView(scroll, LinearLayout.LayoutParams(-1, bodyHeight))
        val footer = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, 0)
        }
        footer.addView(TextView(context).apply {
            text = anchor.part.source
            contentDescription = "原文节选：${anchor.part.source.take(96)}"
            textSize = 13f
            typeface = face
            setTextColor(NativeReadingStyle.muted)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, -2, 1f))
        footer.addView(TextView(context).apply {
            text = "收起"
            textSize = 13f
            typeface = face
            contentDescription = "收起本段译文"
            setTextColor(NativeReadingStyle.muted)
            background = null
            setPadding(dp(10), dp(2), 0, dp(2))
            setOnClickListener { mutate { removeCard() } }
        })
        panel.addView(footer)
        return panel
    }

    private fun attach(view: View, bounds: RectF, extraFlags: Int = 0): Boolean {
        val x = bounds.left.roundToInt()
        val y = bounds.top.roundToInt()
        val params = GlassAnnotations.overlayParams(
            bounds.width().roundToInt().coerceAtLeast(1),
            bounds.height().roundToInt().coerceAtLeast(1),
        ).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            this.x = x
            this.y = y
            if (extraFlags != 0) flags = flags or extraFlags
        }
        view.layoutParams = params
        try { windows.addView(view, params) } catch (_: RuntimeException) { return false }
        view.post {
            if (!view.isAttachedToWindow) return@post
            val location = IntArray(2)
            view.getLocationOnScreen(location)
            if (location[0] != x || location[1] != y) {
                params.x += x - location[0]
                params.y += y - location[1]
                mutate {
                    try { windows.updateViewLayout(view, params) } catch (_: RuntimeException) {}
                }
            }
        }
        return true
    }

    private fun detach(view: View) {
        try { windows.removeView(view) } catch (_: IllegalArgumentException) {}
    }

    private fun removeCard() {
        card?.let(::detach)
        card = null
        pinned = null
        pinnedBox = null
        displayed = null
        persistentRegion = null
        removeWash()
    }

    private fun removeMarks() {
        marks.keys.forEach(::detach)
        marks.clear()
    }

    private inline fun mutate(change: () -> Unit) {
        onWindowChange(true)
        try {
            change()
            val next = marks.values.map { it.bounds } + washRects + listOfNotNull(persistentRegion)
            if (regions != next) {
                regions = next
                onRegionsChanged()
            }
        } finally {
            onWindowChange(false)
        }
    }

    /** Drops the invisible hits so a clean frame can be read. The open card stays. */
    fun hide() {
        page = null
        if (marks.isNotEmpty() || wash != null) mutate {
            removeMarks()
            removeWash()
        }
    }

    fun clear() {
        page = null
        parts = emptyMap()
        knownSources = emptySet()
        if (marks.isNotEmpty() || card != null || wash != null) mutate {
            removeMarks()
            removeCard()
        }
    }

    private fun moved(a: RectF, b: RectF) = abs(a.centerX() - b.centerX()) > 2f || abs(a.centerY() - b.centerY()) > 2f

    companion object {
        const val DEPARTED = "原段已离开这一页"
        const val STILL = "还停在原来的这一段"
    }
}

internal object ParagraphPlacement {
    fun fit(x: Float, y: Float, w: Float, h: Float, bounds: RectF): RectF {
        val left = x.coerceIn(bounds.left, max(bounds.left, bounds.right - w))
        val top = y.coerceIn(bounds.top, max(bounds.top, bounds.bottom - h))
        return RectF(left, top, left + w, top + h)
    }

    fun card(column: RectF, marker: RectF, width: Float, height: Float, safe: RectF, avoid: List<RectF>, gap: Float): RectF {
        val placed = ReadingPlacement.card(
            ReadingBox(column.left, column.top, column.right, column.bottom),
            ReadingBox(marker.left, marker.top, marker.right, marker.bottom),
            width,
            height,
            ReadingBox(safe.left, safe.top, safe.right, safe.bottom),
            avoid.map { ReadingBox(it.left, it.top, it.right, it.bottom) },
            gap,
        )
        return RectF(placed.left, placed.top, placed.right, placed.bottom)
    }
}

internal class OverlayTap(private val slop: Float) {
    private var downX = 0f
    private var downY = 0f
    var scrolling = false
        private set

    /** True only for a finger that lifts without leaving the slop. */
    fun onTouch(action: Int, x: Float, y: Float): Boolean {
        when (action) {
            MotionEvent.ACTION_DOWN -> {
                downX = x
                downY = y
                scrolling = false
            }
            MotionEvent.ACTION_MOVE -> if (!scrolling && !OverlayGesture.isTap(x - downX, y - downY, slop)) scrolling = true
            MotionEvent.ACTION_UP -> return !scrolling
            MotionEvent.ACTION_CANCEL -> scrolling = true
        }
        return false
    }
}

/**
 * A settled tap opens the note. Past the slop this view does not click.
 * NOT_TOUCHABLE and SLIPPERY are requested afterwards. Nothing here shows that
 * the reader received the rest of the swipe.
 */
internal fun bindOverlayTap(
    view: View,
    params: WindowManager.LayoutParams,
    windows: WindowManager,
    slop: Int,
    onArm: () -> Unit = {},
    onRelease: () -> Unit = {},
    onTap: () -> Unit,
) {
    val tap = OverlayTap(slop.toFloat())
    view.setOnTouchListener { _, event ->
        val fire = tap.onTouch(event.actionMasked, event.x, event.y)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) onArm()
        if (tap.scrolling) {
            onRelease()
            view.isPressed = false
            view.isClickable = false
            if (params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE == 0) {
                params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or OVERLAY_FLAG_SLIPPERY
                try { windows.updateViewLayout(view, params) } catch (_: RuntimeException) {}
                view.postDelayed({
                    view.isClickable = true
                    params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
                    try { if (view.isAttachedToWindow) windows.updateViewLayout(view, params) } catch (_: RuntimeException) {}
                }, 520)
            }
        }
        if (fire) {
            onRelease()
            onTap()
        }
        if (event.actionMasked == MotionEvent.ACTION_CANCEL) onRelease()
        true
    }
}
