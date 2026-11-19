package com.wang.lingfer.screen

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import kotlin.math.min

/** TextView-compatible presentation: the session keeps its existing state strings and gestures. */
internal class NativeFloatingOrb(context: Context) : TextView(context) {
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG)
    init {
        background = null
        includeFontPadding = false
        setPadding(0, 0, 0, 0)
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }
    override fun onDraw(canvas: Canvas) {
        val size = min(width, height).toFloat()
        val cx = width / 2f; val cy = height / 2f
        val radius = size * .445f
        ink.style = Paint.Style.FILL
        ink.color = Color.WHITE
        ink.setShadowLayer(size * .045f, 0f, size * .035f, 0x23334A53)
        ink.shader = LinearGradient(cx-radius, cy-radius, cx+radius, cy+radius,
            intArrayOf(0xFFFFFFFF.toInt(), 0xF0F5F7F5.toInt(), 0xF9EBF0EF.toInt()), null, Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, radius, ink)
        ink.clearShadowLayer(); ink.shader = null
        ink.style = Paint.Style.STROKE; ink.strokeWidth = size * .018f; ink.color = Color.WHITE
        canvas.drawCircle(cx, cy, radius-size*.01f, ink)
        ink.strokeWidth = size*.009f; ink.color = 0x22365F70
        canvas.drawCircle(cx, cy, radius-size*.034f, ink)
        val state = text.toString()
        val symbol = if (state == "Ⅱ") "pause" else "book"
        NativeReadingIcon.draw(canvas, symbol, RectF(cx-size*.235f, cy-size*.235f, cx+size*.235f, cy+size*.235f), NativeReadingStyle.accent)
        if (state == "…") {
            ink.style = Paint.Style.STROKE; ink.strokeCap = Paint.Cap.ROUND
            ink.strokeWidth = size*.035f; ink.color = NativeReadingStyle.accent
            canvas.drawArc(RectF(cx-radius+size*.06f,cy-radius+size*.06f,cx+radius-size*.06f,cy+radius-size*.06f),-80f,100f,false,ink)
        } else if (state in listOf("!", "重试", "语言")) {
            ink.style=Paint.Style.FILL; ink.color=Color.WHITE
            canvas.drawCircle(cx+size*.24f,cy-size*.24f,size*.075f,ink)
            ink.color=NativeReadingStyle.warning
            canvas.drawCircle(cx+size*.24f,cy-size*.24f,size*.045f,ink)
        }
    }
    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        val state=when(text.toString()) {"…"->"正在识别";"Ⅱ"->"已暂停";"重试","!"->"翻译待重试";"语言"->"请检查翻译语言";else->"正在随屏阅读"}
        info.className="android.widget.Button";info.text=null
        info.contentDescription="语渡，$state。点按打开阅读菜单，长按停止"
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            isPressed=true
            if (android.os.Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled()) animate().scaleX(.94f).scaleY(.94f).setDuration(100).start()
        } else if (event.actionMasked in listOf(MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL)) {
            isPressed=false
            if (android.os.Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled()) animate().scaleX(1f).scaleY(1f).setDuration(140).start()
            else {scaleX=1f;scaleY=1f}
        }
        return super.dispatchTouchEvent(event)
    }
}

/** Small geometric symbols share a single optical centre; no font-dependent baseline. */
internal class NativeReadingIcon(private val name: String, private val color: Int) : Drawable() {
    override fun draw(canvas: Canvas) = draw(canvas, name, RectF(bounds), color)
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(filter: ColorFilter?) {}
    @Deprecated("Drawable compatibility") override fun getOpacity() = PixelFormat.TRANSLUCENT
    companion object {
        fun draw(canvas: Canvas, name: String, box: RectF, color: Int) {
            val p=Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color=color; style=Paint.Style.STROKE;strokeWidth=1.65f;strokeCap=Paint.Cap.ROUND;strokeJoin=Paint.Join.ROUND }
            canvas.save();canvas.translate(box.left,box.top);canvas.scale(box.width()/24f,box.height()/24f)
            val path=Path()
            when(name) {
                "pause" -> {canvas.drawLine(9f,6f,9f,18f,p);canvas.drawLine(15f,6f,15f,18f,p)}
                "stop" -> canvas.drawRoundRect(6f,6f,18f,18f,3f,3f,p)
                "close" -> {canvas.drawLine(7f,7f,17f,17f,p);canvas.drawLine(17f,7f,7f,17f,p)}
                "more" -> {p.style=Paint.Style.FILL;for(x in listOf(5f,12f,19f))canvas.drawCircle(x,12f,1.25f,p)}
                "settings" -> for((y,x) in listOf(6f to 9f,12f to 16f,18f to 7f)) {canvas.drawLine(4f,y,x-2.3f,y,p);canvas.drawLine(x+2.3f,y,20f,y,p);canvas.drawCircle(x,y,2.3f,p)}
                "refresh" -> {canvas.drawArc(5f,5f,19f,19f,35f,285f,false,p);path.moveTo(19f,4.5f);path.lineTo(19f,9.5f);path.lineTo(14f,9.5f);canvas.drawPath(path,p)}
                "back" -> {path.moveTo(14f,5f);path.lineTo(7f,12f);path.lineTo(14f,19f);canvas.drawPath(path,p)}
                else -> {
                    path.moveTo(12f,6.4f);path.cubicTo(9f,4.3f,5.8f,4.3f,3.5f,5.3f);path.lineTo(3.5f,18.4f)
                    path.cubicTo(6f,17.4f,9.1f,17.5f,12f,19.4f);path.cubicTo(14.9f,17.5f,18f,17.4f,20.5f,18.4f)
                    path.lineTo(20.5f,5.3f);path.cubicTo(18.2f,4.3f,15f,4.3f,12f,6.4f);path.lineTo(12f,19.4f)
                    canvas.drawPath(path,p)
                }
            }
            canvas.restore()
        }
    }
}
