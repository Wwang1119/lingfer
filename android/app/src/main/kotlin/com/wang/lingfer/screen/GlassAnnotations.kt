package com.wang.lingfer.screen

import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.*
import android.widget.TextView
import kotlin.math.*

/** Real text rectangles are obstacles; dense passages keep an interactive underline. */
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

/** Keep each OCR token separate: a phrase may span uneven glyphs or multiple lines. */
internal object AnnotationGeometry {
    fun boxes(page: OcrPage, hit: WordHit): List<RectF> {
        val start = hit.sourceStart ?: Regex(Regex.escape(hit.surface), RegexOption.IGNORE_CASE).find(page.text)?.range?.first ?: return emptyList()
        val end = hit.sourceEnd ?: start + hit.surface.length
        return page.words.filter { it.start < end && it.end > start && !it.box.isEmpty }
            .map { RectF(it.box) }
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
    private val labels = mutableListOf<TextView>()
    private var highlights: Highlights? = null
    @Volatile var regions: List<RectF> = emptyList(); private set
    private fun dp(v: Float) = v*density

    fun show(page: OcrPage, hits: List<WordHit>, snapshot: Bitmap?, avoid: List<RectF> = emptyList()) {
        clear()
        if (hits.isEmpty()) return
        val screen = context.resources.displayMetrics
        val sx = screen.widthPixels.toFloat()/page.width
        val sy = screen.heightPixels.toFloat()/page.height
        fun mapped(box: RectF) = RectF(box.left*sx, box.top*sy, box.right*sx, box.bottom*sy)
        val text = page.words.map { mapped(it.box) } + avoid
        val occupied = mutableListOf<RectF>()
        val anchors = mutableListOf<RectF>()
        val connections = mutableListOf<Pair<RectF,RectF>>()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(12f) }
        val safe = RectF(dp(8f), dp(32f), screen.widthPixels-dp(8f), screen.heightPixels-dp(48f))
        for (hit in hits.take(14)) {
            val wordBoxes = AnnotationGeometry.boxes(page,hit).map(::mapped).filter { box ->
                safe.intersects(box.left,box.top,box.right,box.bottom) && avoid.none {RectF.intersects(it,box)}
            }
            if(wordBoxes.isEmpty()) continue
            val anchor=wordBoxes.first()
            anchors.addAll(wordBoxes)
            val caption = (hit.annotation ?: MultilingualTranslator.compact(hit.translation)).take(28)
            val w = (paint.measureText(caption)+dp(16f)).coerceIn(dp(44f), dp(168f))
            val h = dp(25f)
            val candidate = AnnotationLayout.place(anchor, w, h, safe, text, occupied, dp(3f))
            if(candidate!=null) connections.add(anchor to candidate)
            val marker = candidate == null
            val rect = candidate ?: RectF(anchor).apply { inset(-dp(1f),-dp(2f)) }
            occupied.add(rect)
            val crop = if(marker) null else snapshot?.let { crop(it, RectF(rect.left/sx, rect.top/sy, rect.right/sx, rect.bottom/sy)) }
            val view = TextView(context).apply {
                this.text = if (marker) "" else caption
                textSize = if (marker) 8f else 12f
                includeFontPadding = false
                typeface = Typeface.create("sans-serif-medium",Typeface.NORMAL)
                gravity = Gravity.CENTER
                setTextColor(NativeReadingStyle.accent); setSingleLine(true)
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(if (marker) 0 else dp(7f).toInt(), 0, if (marker) 0 else dp(7f).toInt(), 0)
                background = if(marker) android.graphics.drawable.ColorDrawable(Color.TRANSPARENT) else GlassDrawable(crop,dp(12f))
                contentDescription = "${hit.surface}：$caption，点按查看详解"
                elevation = 0f
                setOnClickListener { onSelect(hit) }
            }
            val params = overlayParams(rect.width().roundToInt().coerceAtLeast(1), rect.height().roundToInt().coerceAtLeast(1)).apply {
                gravity = Gravity.TOP or Gravity.LEFT; x = rect.left.roundToInt(); y = rect.top.roundToInt()
            }
            try {
                windows.addView(view, params); labels.add(view)
                view.post {
                    if (view.isAttachedToWindow) {
                        val origin = IntArray(2); view.getLocationOnScreen(origin)
                        val dx = rect.left.roundToInt()-origin[0]; val dy = rect.top.roundToInt()-origin[1]
                        if (dx != 0 || dy != 0) { params.x += dx; params.y += dy; try { windows.updateViewLayout(view, params) } catch (_: Exception) {} }
                    }
                }
            } catch (_: Exception) { (view.background as? GlassDrawable)?.release() }
        }
        val drawing = Highlights(context, anchors,connections)
        val params = overlayParams(-1, -1).apply { flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE }
        try { windows.addView(drawing, params); highlights = drawing } catch (_: Exception) {}
        regions = occupied.toList() + anchors.map { RectF(it).apply {inset(-dp(2f),-dp(2f))} }
    }

    fun hide() { labels.forEach { it.visibility = View.INVISIBLE }; highlights?.visibility = View.INVISIBLE }
    fun clear() {
        labels.forEach { view -> try { windows.removeView(view) } catch (_: Exception) {}; (view.background as? GlassDrawable)?.release() }
        labels.clear(); highlights?.let { try { windows.removeView(it) } catch (_: Exception) {} }; highlights = null
        regions = emptyList()
    }

    private fun crop(bitmap: Bitmap, box: RectF): Bitmap? = try {
        val left = box.left.toInt().coerceIn(0, bitmap.width-1); val top = box.top.toInt().coerceIn(0, bitmap.height-1)
        val width = box.width().toInt().coerceIn(1, bitmap.width-left); val height = box.height().toInt().coerceIn(1, bitmap.height-top)
        val region = Bitmap.createBitmap(bitmap, left, top, width, height)
        val small = Bitmap.createScaledBitmap(region, min(96, width), min(40, height), true)
        val output = small.copy(Bitmap.Config.ARGB_8888, true)
        if (small !== region) small.recycle()
        if (region !== bitmap) region.recycle()
        // A small two-pass blur keeps the actual sampled background, including
        // dark pages, while the unblurred foreground text stays legible.
        val pixels = IntArray(output.width*output.height); output.getPixels(pixels, 0, output.width, 0, 0, output.width, output.height)
        repeat(2) {
            val input = pixels.clone()
            for (y in 0 until output.height) for (x in 0 until output.width) {
                var r=0; var g=0; var b=0; var count=0
                for (dy in -1..1) for (dx in -2..2) {
                    val color = input[(y+dy).coerceIn(0, output.height-1)*output.width+(x+dx).coerceIn(0, output.width-1)]
                    r+=Color.red(color); g+=Color.green(color); b+=Color.blue(color); count++
                }
                pixels[y*output.width+x] = Color.rgb(r/count, g/count, b/count)
            }
        }
        output.setPixels(pixels, 0, output.width, 0, 0, output.width, output.height); output
    } catch (_: Exception) { null }

    companion object {
        @Suppress("DEPRECATION") fun overlayParams(width: Int, height: Int) = WindowManager.LayoutParams(width, height,
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT).apply { if (Build.VERSION.SDK_INT >= 30) layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS }
    }

    private class Highlights(context: Context, val anchors: List<RectF>,val connections:List<Pair<RectF,RectF>>) : View(context) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val origin = IntArray(2); getLocationOnScreen(origin)
            canvas.save(); canvas.translate(-origin[0].toFloat(), -origin[1].toFloat())
            val density=context.resources.displayMetrics.density
            paint.style=Paint.Style.STROKE;paint.strokeCap=Paint.Cap.ROUND
            paint.strokeWidth=density*.65f;paint.color=0x66365F70
            connections.forEach {(word,label) ->
                when {
                    label.bottom<=word.top -> canvas.drawLine(label.centerX(),label.bottom,word.centerX(),word.top,paint)
                    label.top>=word.bottom -> canvas.drawLine(word.centerX(),word.bottom,label.centerX(),label.top,paint)
                    label.left>=word.right -> canvas.drawLine(word.right,word.centerY(),label.left,label.centerY(),paint)
                    else -> canvas.drawLine(label.right,label.centerY(),word.left,word.centerY(),paint)
                }
            }
            paint.strokeWidth=density*1.2f;paint.color=0xB3365F70.toInt()
            anchors.forEach {box -> canvas.drawLine(box.left,box.bottom+density,box.right,box.bottom+density,paint)}
            canvas.restore()
        }
    }
}
