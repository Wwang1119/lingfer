package com.wang.lingfer.screen

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Only the narrow column margins and the open note own input windows. */
internal class ParagraphAnnotations(
    private val context: Context,
    private val windows: WindowManager,
    private val onRegionsChanged: () -> Unit,
    private val onRecovery: () -> Unit,
    private val onWindowChange: (Boolean) -> Unit = {},
) {
    private data class Anchor(val part: PageParagraph, val box: RectF)
    private data class Stop(val anchor: Anchor, val top: Int, val bottom: Int)
    private data class Rail(val bounds: RectF, val right: Boolean, val stops: List<Stop>)
    private data class Note(val translation: String?, val message: String?, val recovery: String?)

    private val rails = linkedMapOf<View, Rail>()
    private var page: OcrPage? = null
    private var viewport = Rect()
    private var safe = RectF()
    private var avoid: List<RectF> = emptyList()
    private var parts: Map<String, PageParagraph> = emptyMap()
    private var loading = false
    private var error: String? = null
    private var pinned: Anchor? = null
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
        val note = anchor?.let { current ->
            val original = incoming[current.part.id]?.takeIf { it.source == current.part.source }
            when {
                original != null -> noteFor(original)
                displayed?.translation != null -> displayed
                else -> Note(null, "已离开原段，轻点当前页边可查看其他段落。", null)
            }
        }
        val redraw = anchor != null && note != null && (note != displayed || viewportChanged)
        if (!rebuild && !redraw) return
        mutate {
            if (rebuild) {
                removeRails()
                if (safe.width() >= dp(42) && safe.height() > dp(20)) addRails(page)
            }
            if (redraw && anchor != null && note != null) showCard(anchor, note, persistentRegion)
        }
    }

    private fun addRails(page: OcrPage) {
        val map = AnnotationCoordinates(page.width, page.height, viewport)
        val boxes = mutableMapOf<String, RectF>()
        for (line in page.lines) {
            if (line.paragraphId !in parts) continue
            val box = map.toScreen(line.box)
            if (box.intersect(safe)) {
                val previous = boxes[line.paragraphId]
                if (previous == null) boxes[line.paragraphId] = box else previous.union(box)
            }
        }
        val anchors = page.paragraphs.mapNotNull { p ->
            boxes[p.id]?.takeIf { parts[p.id]?.source == p.source }?.let { Anchor(p, it) }
        }
        if (anchors.isEmpty()) return
        val middle = safe.centerX()
        val slop = safe.width() * .025f
        val left = anchors.filter { it.box.right <= middle + slop && it.box.centerX() < middle - slop }
        val right = anchors.filter { it.box.left >= middle - slop && it.box.centerX() > middle + slop }
        val columns = left.isNotEmpty() && right.isNotEmpty() &&
            max(left.minOf { it.box.top }, right.minOf { it.box.top }) <= min(left.maxOf { it.box.bottom }, right.maxOf { it.box.bottom })
        addRail(if (columns) anchors - right.toSet() else anchors, right = false)
        if (columns) addRail(right, right = true)
    }

    private fun addRail(anchors: List<Anchor>, right: Boolean) {
        val ordered = anchors.sortedBy { it.box.centerY() }
        val width = dp(20)
        val gap = dp(2)
        // Keep the rail near the paper, with a free strip at the physical display edge when possible.
        val x = if (right) {
            (ordered.maxOf { it.box.right } + gap).coerceIn(safe.right - width - safe.width() * .08f, safe.right - width)
        } else {
            (ordered.minOf { it.box.left } - width - gap).coerceIn(safe.left, safe.left + safe.width() * .08f)
        }
        val top = max(safe.top, ordered.minOf { it.box.top } - dp(9)).roundToInt()
        val bottom = min(safe.bottom, ordered.maxOf { it.box.bottom } + dp(9)).roundToInt()
        if (bottom <= top) return
        var start = top
        val stops = ordered.mapIndexedNotNull { i, anchor ->
            val next = ordered.getOrNull(i + 1)
            val end = if (next == null) bottom else {
                val midpoint = if (anchor.box.bottom <= next.box.top) (anchor.box.bottom + next.box.top) / 2
                    else (anchor.box.centerY() + next.box.centerY()) / 2
                midpoint.roundToInt().coerceIn(start, bottom)
            }
            val stop = if (end > start) Stop(anchor, start - top, end - top) else null
            start = end
            stop
        }
        val bounds = RectF(x.roundToInt().toFloat(), top.toFloat(), x.roundToInt() + width.toFloat(), bottom.toFloat())
        val rail = Rail(bounds, right, stops)
        val view = MarginRail(context, drawLabel = !right)
        for (stop in stops) {
            // Individual accessibility targets share one narrow native window. The PDF owns all other points.
            val target = View(context).apply {
                contentDescription = "翻译此段：${stop.anchor.part.source.take(64)}"
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                setOnClickListener { select(stop.anchor, rail) }
            }
            view.addView(target, FrameLayout.LayoutParams(-1, stop.bottom - stop.top).apply { topMargin = stop.top })
        }
        if (attach(view, bounds)) rails[view] = rail
    }

    private class MarginRail(context: Context, private val drawLabel: Boolean) : FrameLayout(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val density = resources.displayMetrics.density
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var dragging = false
        init { setWillNotDraw(false) }

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!dragging && (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop)) {
                        dragging = true
                        val cancel = MotionEvent.obtain(event)
                        cancel.action = MotionEvent.ACTION_CANCEL
                        super.dispatchTouchEvent(cancel)
                        cancel.recycle()
                    }
                }
            }
            return dragging || super.dispatchTouchEvent(event)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val x = width / 2f
            var top = 2 * density
            if (drawLabel) {
                paint.typeface = NativeReadingStyle.heading(context)
                paint.textSize = 11 * density
                paint.textAlign = Paint.Align.CENTER
                paint.color = Color.rgb(78, 109, 97)
                canvas.drawText("译", x, top - paint.ascent(), paint)
                top += 17 * density
            }
            paint.color = Color.argb(100, 102, 133, 117)
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeWidth = max(1f, .8f * density)
            if (top < height - density) canvas.drawLine(x, top, x, height - density, paint)
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

    private fun select(anchor: Anchor, rail: Rail) {
        if (rail !in rails.values) return
        val part = parts[anchor.part.id]?.takeIf { it.source == anchor.part.source } ?: return
        if (pinned?.part == anchor.part && card != null) return
        mutate { showCard(anchor, noteFor(part), null) }
    }

    private fun showCard(anchor: Anchor, note: Note, previous: RectF?) {
        if (safe.isEmpty) return
        val gap = dp(4).toFloat()
        val inner = RectF(safe)
        rails.values.forEach {
            if (it.right) inner.right = min(inner.right, it.bounds.left - gap)
            else inner.left = max(inner.left, it.bounds.right + gap)
        }
        if (inner.width() < dp(96)) inner.set(safe)
        val width = minOf(dp(320).toFloat(), safe.width() * .86f, inner.width()).roundToInt().coerceAtLeast(1)
        val fraction = if (safe.width() < dp(520)) .30f else .35f
        val maxHeight = min(dp(270), (safe.height() * fraction).roundToInt()).coerceAtLeast(1)
        val view = makeCard(anchor, note)
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(maxHeight, View.MeasureSpec.AT_MOST))
        val height = view.measuredHeight.toFloat()
        val box = if (previous != null) {
            ParagraphPlacement.fit(previous.left, previous.top, width.toFloat(), height, inner)
        } else {
            val rail = rails.values.firstOrNull { r -> r.stops.any { it.anchor == anchor } }
            val x = rail?.bounds?.centerX() ?: anchor.box.left
            val point = RectF(x, anchor.box.top, x + 1, anchor.box.top + 1)
            ParagraphPlacement.card(anchor.box, point, width.toFloat(), height, inner, avoid, gap)
        }
        if (attach(view, box)) {
            card?.let(::detach)
            pinned = anchor
            displayed = note
            card = view
            persistentRegion = box
        }
    }

    private fun makeCard(anchor: Anchor, note: Note): View {
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(3), dp(8), dp(8))
            background = NativeReadingStyle.surface(context, 15f, Color.rgb(250, 249, 244))
            clipToOutline = true
            // Touches within the note belong to it; the PDF still owns the rest of the screen.
            isClickable = true
        }
        val header = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        val source = TextView(context).apply {
            text = "原文 · ${anchor.part.source}"
            contentDescription = "原文节选：${anchor.part.source.take(96)}"
            textSize = 13f
            typeface = Typeface.SERIF
            setTextColor(NativeReadingStyle.muted)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
        header.addView(source, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(TextView(context).apply {
            text = "收起"
            textSize = 14f
            contentDescription = "收起本段译文"
            gravity = Gravity.CENTER
            setTextColor(NativeReadingStyle.accent)
            background = NativeReadingStyle.control(context)
            minHeight = dp(44)
            minWidth = dp(44)
            setOnClickListener { mutate { removeCard() } }
        })
        panel.addView(header)
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, dp(5), dp(3))
        }
        body.addView(TextView(context).apply {
            text = note.translation ?: note.message
            textSize = if (note.translation != null) 16f else 14f
            setLineSpacing(dp(3).toFloat(), 1f)
            setTextColor(if (note.translation != null) NativeReadingStyle.ink else NativeReadingStyle.muted)
        })
        note.recovery?.let { label ->
            body.addView(TextView(context).apply {
                text = label
                textSize = 14f
                minHeight = dp(44)
                gravity = Gravity.CENTER_VERTICAL
                setTextColor(NativeReadingStyle.accent)
                background = NativeReadingStyle.control(context)
                setOnClickListener { onRecovery() }
            })
        }
        panel.addView(ScrollView(context).apply {
            contentDescription = "本段译文"
            addView(body)
        }, LinearLayout.LayoutParams(-1, -2))
        return panel
    }

    private fun attach(view: View, bounds: RectF): Boolean {
        val x = bounds.left.roundToInt()
        val y = bounds.top.roundToInt()
        val params = GlassAnnotations.overlayParams(bounds.width().roundToInt().coerceAtLeast(1), bounds.height().roundToInt().coerceAtLeast(1)).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            this.x = x
            this.y = y
        }
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
        displayed = null
        persistentRegion = null
    }

    private fun removeRails() {
        rails.keys.forEach(::detach)
        rails.clear()
    }

    private inline fun mutate(change: () -> Unit) {
        onWindowChange(true)
        try {
            change()
            val next = rails.values.map { it.bounds } + listOfNotNull(persistentRegion)
            if (regions != next) {
                regions = next
                onRegionsChanged()
            }
        } finally {
            onWindowChange(false)
        }
    }

    fun hide() {
        page = null
        if (rails.isNotEmpty()) mutate { removeRails() }
    }

    fun clear() {
        page = null
        parts = emptyMap()
        if (rails.isNotEmpty() || card != null) mutate {
            removeRails()
            removeCard()
        }
    }
}

internal object ParagraphPlacement {
    fun fit(x: Float, y: Float, w: Float, h: Float, bounds: RectF): RectF {
        val left = x.coerceIn(bounds.left, max(bounds.left, bounds.right - w))
        val top = y.coerceIn(bounds.top, max(bounds.top, bounds.bottom - h))
        return RectF(left, top, left + w, top + h)
    }

    private fun overlap(a: RectF, b: RectF) =
        max(0f, min(a.right, b.right) - max(a.left, b.left)) * max(0f, min(a.bottom, b.bottom) - max(a.top, b.top))

    fun card(column: RectF, marker: RectF, width: Float, height: Float, safe: RectF, avoid: List<RectF>, gap: Float): RectF {
        val nearX = if (marker.centerX() <= column.centerX()) column.left else column.right - width
        val candidates = listOf(
            fit(column.right + gap, marker.top, width, height, safe),
            fit(column.left - width - gap, marker.top, width, height, safe),
            fit(nearX, column.bottom + gap, width, height, safe),
            fit(nearX, column.top - height - gap, width, height, safe),
            fit(nearX, marker.bottom + gap, width, height, safe),
            fit(nearX, marker.top - height - gap, width, height, safe),
        )
        // Keep the selected original visible where possible, then use the closest available space.
        val permitted = candidates.filter { box -> avoid.none { RectF.intersects(it, box) } && !RectF.intersects(marker, box) }
        return (permitted.ifEmpty { candidates }).minBy { box ->
            val covered = overlap(box, column) + overlap(box, marker) + avoid.sumOf { overlap(box, it).toDouble() }
            val dx = max(0f, abs(marker.centerX() - box.centerX()) - width / 2)
            val dy = max(0f, abs(marker.centerY() - box.centerY()) - height / 2)
            covered * 2 + dx + dy
        }
    }
}
