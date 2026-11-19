package com.wang.lingfer.screen

import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.*
import android.widget.TextView
import kotlin.math.*

/** Keep the gloss immediately beside its source word or omit it when that space is occupied. */
object AnnotationLayout {
    fun place(anchor: RectF, width: Float, height: Float, bounds: RectF, text: List<RectF>, occupied: List<RectF>, gap: Float): RectF? {
        val candidates = listOf(
            RectF(anchor.centerX()-width/2, anchor.top-gap-height, anchor.centerX()+width/2, anchor.top-gap),
            RectF(anchor.centerX()-width/2, anchor.bottom+gap, anchor.centerX()+width/2, anchor.bottom+gap+height),
            RectF(anchor.right+gap, anchor.centerY()-height/2, anchor.right+gap+width, anchor.centerY()+height/2),
            RectF(anchor.left-gap-width, anchor.centerY()-height/2, anchor.left-gap, anchor.centerY()+height/2))
        return candidates.firstOrNull { candidate ->
            bounds.contains(candidate) && text.none { RectF(it).apply { inset(-gap/2, -gap/2) }.let { RectF.intersects(it, candidate) } } &&
                occupied.none { RectF(it).apply { inset(-gap, -gap) }.let { RectF.intersects(it, candidate) } }
        }
    }
}

/** One mapping for OCR bounds on screen and our own overlay masks in the next captured frame. */
internal class AnnotationCoordinates(captureWidth: Int, captureHeight: Int, private val screenArea: Rect) {
    private val sx = screenArea.width().toFloat() / captureWidth
    private val sy = screenArea.height().toFloat() / captureHeight

    fun toScreen(box: RectF) = RectF(
        screenArea.left + box.left * sx, screenArea.top + box.top * sy,
        screenArea.left + box.right * sx, screenArea.top + box.bottom * sy,
    )

    fun toCapture(box: RectF) = RectF(
        (box.left - screenArea.left) / sx, (box.top - screenArea.top) / sy,
        (box.right - screenArea.left) / sx, (box.bottom - screenArea.top) / sy,
    )
}

/** Keep each OCR token separate: a phrase may span uneven glyphs or multiple lines. */
internal object AnnotationGeometry {
    @Suppress("DEPRECATION")
    fun displayBounds(windows: WindowManager, fallback: Rect): Rect = try {
        if (Build.VERSION.SDK_INT >= 30) {
            windows.maximumWindowMetrics.bounds
        } else {
            val size = Point()
            windows.defaultDisplay.getRealSize(size)
            Rect(0, 0, size.x, size.y)
        }
    } catch (_: RuntimeException) {
        fallback
    }

    /** Resize callbacks report source pixels. Width and height alone do not locate an arbitrary freeform task. */
    fun viewport(captureWidth: Int, captureHeight: Int, candidates: List<Rect>): Rect? {
        val matching = candidates.filter { it.width() == captureWidth && it.height() == captureHeight }.distinct()
        return matching.singleOrNull()
    }

    fun viewport(windows: WindowManager, width: Int, height: Int, available: Rect, display: Rect): Rect? {
        if (display.width() == width && display.height() == height) return display
        val candidates = mutableListOf<Rect>()
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val insets = windows.maximumWindowMetrics.windowInsets
                for (types in listOf(WindowInsets.Type.navigationBars(), WindowInsets.Type.statusBars(), WindowInsets.Type.systemBars())) {
                    val inset = insets.getInsetsIgnoringVisibility(types or WindowInsets.Type.displayCutout())
                    candidates.add(Rect(display.left + inset.left, display.top + inset.top,
                        display.right - inset.right, display.bottom - inset.bottom))
                }
            } catch (_: RuntimeException) {
                // Some service/display contexts only expose the normal app resource bounds.
            }
        }
        val matches = candidates.filter { it.width() == width && it.height() == height }
        return if (matches.isEmpty()) viewport(width, height, listOf(available)) else viewport(width, height, matches)
    }

    fun wordRuns(page: OcrPage, hit: WordHit, coordinates: AnnotationCoordinates, gap: Float): List<RectF> {
        val text = page.text
        if (hit.surface.isEmpty()) return emptyList()
        // Legacy hits without offsets can be positioned only if the match is unambiguous.
        val start = hit.sourceStart ?: text.indexOf(hit.surface, ignoreCase = true).takeIf {
            it >= 0 && it == text.lastIndexOf(hit.surface, ignoreCase = true)
        } ?: return emptyList()
        val end = hit.sourceEnd ?: start + hit.surface.length
        if (start < 0 || end > text.length || end - start != hit.surface.length ||
            !text.regionMatches(start, hit.surface, 0, hit.surface.length, ignoreCase = true)) return emptyList()

        return page.lines.flatMap { line ->
            val boxes = line.words.filter { it.start < end && it.end > start && !it.box.isEmpty }
                .map { coordinates.toScreen(it.box) }
            val runs = runs(boxes, gap)
            val lineBottom = coordinates.toScreen(line.box).bottom
            for (run in runs) {
                // Align ordinary letters with adjacent descenders, while allowing
                // a raised footnote or smaller type to keep its own baseline.
                if (lineBottom >= run.bottom && lineBottom - run.bottom <= run.height() * .20f) {
                    run.bottom = lineBottom
                }
            }
            runs
        }
    }

    /** One touch target per contiguous run. A wrapped phrase must leave the space between lines free. */
    private fun runs(boxes: List<RectF>, gap: Float): List<RectF> {
        val runs = mutableListOf<RectF>()
        for (box in boxes) {
            val previous = runs.lastOrNull()
            val overlap = if (previous == null) 0f else min(box.bottom, previous.bottom) - max(box.top, previous.top)
            if (previous != null && overlap >= min(box.height(), previous.height()) * .6f &&
                box.left <= previous.right + gap && box.right >= previous.left - gap
            ) {
                previous.union(box)
            } else {
                runs.add(RectF(box))
            }
        }
        return runs
    }
}

internal enum class AnnotationPalette(val paper: Int, val ink: Int, val marker: Int) {
    LIGHT(Color.rgb(250, 239, 215), Color.rgb(83, 54, 28), Color.rgb(142, 103, 54)),
    DARK(Color.rgb(65, 51, 37), Color.rgb(255, 229, 187), Color.rgb(226, 186, 128));

    companion object {
        /** A few pixels from the existing local clean frame are enough to choose the paper color. */
        fun at(bitmap: Bitmap?, area: RectF): AnnotationPalette {
            if (bitmap == null || bitmap.isRecycled) return LIGHT
            if (Build.VERSION.SDK_INT >= 26 && bitmap.config == Bitmap.Config.HARDWARE) return LIGHT
            var dark = 0
            for (row in 0..2) for (column in 0..2) {
                val x = (area.left + area.width() * (column + .5f) / 3).toInt().coerceIn(0, bitmap.width - 1)
                val y = (area.top + area.height() * (row + .5f) / 3).toInt().coerceIn(0, bitmap.height - 1)
                val color = bitmap.getPixel(x, y)
                if (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114 < 134000) dark++
            }
            return if (dark >= 5) DARK else LIGHT
        }
    }
}

/** The transparent tap area covers the word; only its lower edge carries ink. */
internal class AnnotationWordUnderline(context: Context, color: Int, private val stroke: Int) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
    override fun onDraw(canvas: Canvas) {
        val radius = stroke / 2f
        canvas.drawRoundRect(0f, (height - stroke).toFloat(), width.toFloat(), height.toFloat(), radius, radius, paint)
    }
}

class GlassDrawable(private val snapshot: Bitmap? = null, private val radius: Float = 28f) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var drawingAlpha=255
    override fun draw(canvas: Canvas) {
        paint.shader=null;paint.style=Paint.Style.FILL;paint.alpha=drawingAlpha
        val rect = RectF(bounds).apply { inset(1f, 1f) }
        canvas.save()
        canvas.clipPath(Path().apply { addRoundRect(rect, radius, radius, Path.Direction.CW) })
        snapshot?.takeUnless { it.isRecycled }?.let { canvas.drawBitmap(it, null, rect, paint) }
        val material=if(snapshot==null) intArrayOf(0xFFFFFFFF.toInt(),0xFCF7F9F7.toInt(),0xFEFFFFFF.toInt())
            else intArrayOf(0xF5FFFFFF.toInt(),0xE8F4F7F5.toInt(),0xF5FFFFFF.toInt())
        paint.shader = LinearGradient(rect.left, rect.top, rect.right, rect.bottom,
            material, null, Shader.TileMode.CLAMP)
        canvas.drawRoundRect(rect, radius, radius, paint)
        paint.shader = null
        canvas.restore()
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.7f; paint.color = 0xEFFFFFFF.toInt();paint.alpha=239*drawingAlpha/255
        canvas.drawRoundRect(rect, radius, radius, paint)
        paint.strokeWidth = .8f; paint.color = 0x404A6B82;paint.alpha=64*drawingAlpha/255
        canvas.drawRoundRect(RectF(rect).apply { inset(1.2f, 1.2f) }, radius, radius, paint)
        paint.style = Paint.Style.FILL
    }
    override fun getOutline(outline: Outline) { outline.setRoundRect(bounds, radius) }
    override fun setAlpha(alpha: Int) { drawingAlpha = alpha; invalidateSelf() }
    override fun setColorFilter(filter: ColorFilter?) { paint.colorFilter = filter }
    @Deprecated("Android Drawable compatibility") override fun getOpacity() = PixelFormat.TRANSLUCENT
    fun release() { snapshot?.takeUnless { it.isRecycled }?.recycle() }
}

class GlassAnnotations(private val context: Context, private val windows: WindowManager,
    private val onSelect: (WordHit) -> Unit) {
    private val density get() = context.resources.displayMetrics.density
    private val overlays = mutableListOf<View>()
    @Volatile var regions: List<RectF> = emptyList(); private set
    private fun dp(value: Float) = value * density

    fun show(page: OcrPage, hits: List<WordHit>, snapshot: Bitmap?, avoid: List<RectF> = emptyList(), screenArea: Rect? = null) {
        clear()
        if (hits.isEmpty() || screenArea?.isEmpty == true) return
        val screen = context.resources.displayMetrics
        val available = Rect(0, 0, screen.widthPixels, screen.heightPixels)
        val viewport = screenArea ?: available
        val coordinates = AnnotationCoordinates(page.width, page.height, viewport)
        fun palette(area: RectF) = AnnotationPalette.at(snapshot, coordinates.toCapture(area))
        val obstacles = page.words.map { coordinates.toScreen(it.box) } + avoid
        val occupied = mutableListOf<RectF>()
        val safe = RectF(viewport.left + dp(8f), viewport.top + dp(32f), viewport.right - dp(8f), viewport.bottom - dp(48f))
        for (hit in hits.take(14)) {
            // Keep the underline below the glyphs even at the bottom of the
            // viewport. Clamping its y would move it onto an unrelated baseline.
            val runs = AnnotationGeometry.wordRuns(page, hit, coordinates, dp(3f)).filter { box ->
                safe.contains(box) && box.bottom + dp(3f) <= safe.bottom && avoid.none { RectF.intersects(it, box) }
            }
            val anchor = runs.firstOrNull() ?: continue
            val caption = (hit.annotation ?: MultilingualTranslator.compact(hit.translation)).take(28)
            val description = "${hit.surface}：$caption，点按查看词卡"
            val gloss = TextView(context).apply {
                text = caption
                textSize = 13f
                includeFontPadding = false
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                gravity = Gravity.CENTER
                setSingleLine()
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(dp(6f).roundToInt(), dp(3f).roundToInt(), dp(6f).roundToInt(), dp(3f).roundToInt())
                contentDescription = description
            }
            // Use the actual scaled typeface and padding when testing for available space.
            val maxWidth = min(dp(168f), safe.width()).roundToInt().coerceAtLeast(1)
            gloss.measure(View.MeasureSpec.makeMeasureSpec(maxWidth, View.MeasureSpec.AT_MOST), View.MeasureSpec.UNSPECIFIED)
            val place = if (caption.isBlank()) null else AnnotationLayout.place(
                RectF(anchor).apply { bottom += dp(2f) }, gloss.measuredWidth.toFloat(), gloss.measuredHeight.toFloat(),
                safe, obstacles, occupied, dp(3f)
            )
            val hasGloss = if (place == null) false else {
                val colors = palette(place)
                gloss.setTextColor(colors.ink)
                gloss.background = GradientDrawable().apply {
                    setColor(colors.paper)
                    cornerRadius = dp(3f)
                }
                addOverlay(gloss, place, hit).also { if (it) occupied.add(place) }
            }
            runs.forEachIndexed { index, run ->
                val stroke = min(dp(1.1f), run.height() * .055f).roundToInt().coerceAtLeast(1)
                val clearance = min(dp(1.2f), run.height() * .07f).roundToInt().coerceAtLeast(1)
                val target = RectF(run).apply { bottom += clearance + stroke }
                val strip = RectF(target.left, target.bottom - stroke, target.right, target.bottom)
                val mark = AnnotationWordUnderline(context, palette(strip).marker, stroke).apply {
                    if (!hasGloss && index == 0) contentDescription = description
                    else importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }
                if (addOverlay(mark, target, hit)) occupied.add(target)
            }
        }
        regions = occupied.toList()
    }

    private fun addOverlay(view: View, rect: RectF, hit: WordHit): Boolean {
        val left = rect.left.roundToInt()
        val top = rect.top.roundToInt()
        val width = (rect.right.roundToInt() - left).coerceAtLeast(1)
        val height = (rect.bottom.roundToInt() - top).coerceAtLeast(1)
        val params = overlayParams(width, height).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            x = left
            y = top
        }
        view.setOnClickListener { onSelect(hit) }
        try {
            windows.addView(view, params)
        } catch (_: RuntimeException) {
            return false
        }
        overlays.add(view)
        view.post {
            if (view.isAttachedToWindow) {
                val origin = IntArray(2)
                view.getLocationOnScreen(origin)
                val dx = left - origin[0]
                val dy = top - origin[1]
                if (dx != 0 || dy != 0) {
                    params.x += dx
                    params.y += dy
                    try { windows.updateViewLayout(view, params) } catch (_: RuntimeException) {}
                }
            }
        }
        return true
    }

    fun hide() { overlays.forEach { it.visibility = View.INVISIBLE } }

    fun clear() {
        overlays.forEach { view ->
            try { windows.removeView(view) } catch (_: IllegalArgumentException) {}
        }
        overlays.clear()
        regions = emptyList()
    }

    companion object {
        @Suppress("DEPRECATION") fun overlayParams(width: Int, height: Int) = WindowManager.LayoutParams(width, height,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT).apply { if (Build.VERSION.SDK_INT >= 30) layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS }
    }
}
