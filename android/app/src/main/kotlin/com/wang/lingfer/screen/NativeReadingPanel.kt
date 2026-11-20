package com.wang.lingfer.screen

import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.widget.*
import org.json.JSONArray

/** Presentation-only counterparts of LingferColors and the Flutter word card. */
internal object NativeReadingStyle {
    val background = Color.rgb(246, 246, 243)
    val paper = Color.WHITE
    /** Warm sheet used by the in-app reader and the live translation card. */
    val readingPaper = Color.rgb(250, 249, 244)
    val ink = Color.rgb(34, 40, 40)
    val muted = Color.rgb(102, 112, 115)
    val accent = Color.rgb(54, 95, 112)
    val deepAccent = Color.rgb(41, 75, 87)
    val tint = Color.rgb(234, 240, 241)
    val line = Color.rgb(219, 225, 223)
    val warning = Color.rgb(155, 69, 37)
    fun dp(context: Context, value: Float) = (context.resources.displayMetrics.density * value).toInt()
    private var displayFont: Typeface? = null
    fun heading(context: Context): Typeface = displayFont ?: run {
        val font = try { Typeface.createFromAsset(context.assets,"flutter_assets/assets/fonts/lingfer-display-semibold.ttf") }
            catch (_: Exception) { Typeface.create("serif", Typeface.NORMAL) }
        displayFont=font; font
    }
    fun glass(context: Context, backdrop: Bitmap? = null) = GlassDrawable(backdrop,dp(context,28f).toFloat())
    fun control(context: Context, fill: Int = Color.TRANSPARENT): Drawable {
        val radius = dp(context, 16f).toFloat()
        fun shape(color: Int) = GradientDrawable().apply {
            cornerRadius = radius
            setColor(color)
        }
        val rippleColor = if (fill == deepAccent) 0x32FFFFFF else 0x22365F70
        return android.graphics.drawable.RippleDrawable(
            android.content.res.ColorStateList.valueOf(rippleColor),
            shape(fill),
            shape(Color.WHITE),
        )
    }
    fun divider(context: Context) = View(context).apply {
        setBackgroundColor(line)
        layoutParams = LinearLayout.LayoutParams(-1, 1)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    fun animateIn(view: View) {
        if(android.os.Build.VERSION.SDK_INT>=26 && !android.animation.ValueAnimator.areAnimatorsEnabled()) return
        view.alpha=0f;view.translationY=dp(view.context,8f).toFloat()
        view.animate().alpha(1f).translationY(0f).setDuration(180).start()
    }

    fun surface(context: Context, radius: Float = 24f, fill: Int = paper) = GradientDrawable().apply {
        setColor(fill)
        setStroke(1, line)
        cornerRadius = dp(context, radius).toFloat()
    }
}

/** All mutations and requests are supplied by the existing service callbacks. */
internal class NativeReadingPanel(
    context: Context,
    private val hit: WordHit,
    scope: String,
    scopeName: String,
    private val choices: List<Pair<String, String>>,
    private val words: List<WordHit>,
    savedPayload: String,
    private val onSave: () -> Unit,
    onKnown: () -> Unit,
    onExplain: () -> Unit,
    onClose: () -> Unit,
    onRefresh: () -> Unit,
    onStop: () -> Unit,
    private val onScope: (String) -> Unit,
    private val onWord: (WordHit) -> Unit,
    onParagraph: (() -> Unit)? = null,
) : LinearLayout(context) {
    private fun dp(value: Int) = NativeReadingStyle.dp(context, value.toFloat())
    private var saved = try {
        val entries = JSONArray(savedPayload)
        (0 until entries.length()).any { entries.getJSONObject(it).optString("studyKey", entries.getJSONObject(it).optString("word")) == hit.key }
    } catch (_: Exception) { false }
    private val bookmark = ImageButton(context)
    private val progress = ProgressBar(context).apply { isIndeterminate = true; indeterminateTintList = android.content.res.ColorStateList.valueOf(NativeReadingStyle.accent) }
    private val answer = label("", 16f).apply { setTextIsSelectable(true); setLineSpacing(dp(6).toFloat(), 1.15f) }
    private val retry = action("语境讲解", onExplain)
    private val scroll = ScrollView(context).apply { isFillViewport = true; clipToPadding = false; setBackgroundColor(NativeReadingStyle.background) }
    private val content = LinearLayout(context).apply {
        orientation = VERTICAL
        setPadding(dp(12), dp(6), dp(12), dp(12))
    }
    private val range = action("$scopeName · ${choices.firstOrNull { it.first == scope }?.second ?: scope}  ⌄") {
        showChoices(scope, scopeName)
    }.apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL }
    private val countLabel = action("全部词卡 · ${words.size}") { showWords() }.apply {
        gravity = Gravity.START or Gravity.CENTER_VERTICAL
        textSize = 12f
        setTextColor(NativeReadingStyle.muted)
    }

    init {
        orientation = VERTICAL
        background = NativeReadingStyle.glass(context)
        elevation = 0f
        clipToOutline = true
        val heading = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(5), dp(8), dp(2))
        }
        heading.addView(label("本页词卡", 22f).apply {
            typeface = NativeReadingStyle.heading(context)
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        }, LayoutParams(0, -2, 1f))
        heading.addView(action("关闭", onClose).apply { contentDescription = "关闭面板" })
        addView(heading)

        scroll.addView(content)
        addView(scroll, LayoutParams(-1, 0, 1f))
        val summary = LinearLayout(context).apply {
            orientation = if (context.resources.configuration.fontScale > 1.3f) VERTICAL else HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val inline = summary.orientation == HORIZONTAL
        summary.addView(range, if (inline) LayoutParams(0, -2, 1f) else LayoutParams(-1, -2))
        summary.addView(countLabel, LayoutParams(if (inline) -2 else -1, -2))
        content.addView(summary)

        val card = LinearLayout(context).apply {
            orientation = VERTICAL
            background = NativeReadingStyle.surface(context, 20f)
            setPadding(dp(16), dp(12), dp(16), dp(16))
        }
        val wordHeader = LinearLayout(context).apply { gravity = Gravity.TOP }
        wordHeader.addView(label(hit.surface, 30f).apply {
            typeface = Typeface.SERIF
            setLineSpacing(dp(3).toFloat(), 1f)
        }, LayoutParams(0, -2, 1f))
        bookmark.apply {
            minimumWidth = dp(48)
            minimumHeight = dp(48)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = NativeReadingStyle.control(context, NativeReadingStyle.tint)
            setOnClickListener {
                onSave()
                saved = true
                updateBookmark()
            }
        }
        updateBookmark()
        wordHeader.addView(bookmark, LayoutParams(dp(48), dp(48)))
        card.addView(wordHeader)
        card.addView(label(hit.translation, 16f).apply {
            setPadding(0, dp(10), 0, dp(16))
            setLineSpacing(dp(5).toFloat(), 1.15f)
        })
        if (onParagraph != null) {
            card.addView(action("翻译这段", onParagraph).apply {
                background = NativeReadingStyle.control(context, NativeReadingStyle.deepAccent)
                setTextColor(Color.WHITE)
            }, LayoutParams(-1, -2).apply { bottomMargin = dp(12) })
        }
        val sentence = LinearLayout(context).apply {
            orientation = VERTICAL
            background = NativeReadingStyle.surface(context, 14f, fill = NativeReadingStyle.tint)
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        sentence.addView(label("原句", 12f, NativeReadingStyle.muted))
        sentence.addView(label("", 16f).apply {
            text = emphasize(hit.context, hit.surface)
            typeface = Typeface.SERIF
            setTextIsSelectable(true)
            setPadding(0, dp(6), 0, 0)
            setLineSpacing(dp(5).toFloat(), 1.12f)
        })
        card.addView(sentence)
        card.addView(action("标为熟词", onKnown).apply {
            setTextColor(NativeReadingStyle.muted)
            contentDescription = "标为熟词：${hit.surface}"
        })
        card.addView(NativeReadingStyle.divider(context))
        card.addView(label("语境讲解", 14f, NativeReadingStyle.accent).apply {
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(16), 0, dp(8))
        })
        card.addView(progress, LayoutParams(dp(24), dp(24)).apply { bottomMargin = dp(8) })
        card.addView(answer)
        card.addView(retry)
        content.addView(card)

        addView(NativeReadingStyle.divider(context))
        val footer = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.END
            setPadding(dp(10), dp(6), dp(10), dp(8))
        }
        footer.addView(action("重新识别", onRefresh), LayoutParams(0, -2, 1f))
        footer.addView(action("停止阅读", onStop).apply {
            setTextColor(NativeReadingStyle.warning)
            contentDescription = "停止阅读并结束捕获"
        }, LayoutParams(0, -2, 1f))
        addView(footer)
    }

    fun showLoading() {
        progress.visibility = VISIBLE; answer.text = "正在结合原文讲解…"
        retry.visibility = VISIBLE
        answer.setTextColor(NativeReadingStyle.muted); retry.isEnabled = false
        retry.text = "正在讲解"
    }
    fun showAnswer(value: String) {
        progress.visibility = GONE; answer.text = value
        retry.visibility = VISIBLE
        answer.setTextColor(if (value == "详解暂未响应，原词译义和收藏仍可使用。") NativeReadingStyle.warning else NativeReadingStyle.ink)
        retry.isEnabled = true; retry.text = "重新请求讲解"
    }

    fun showOffline(savedAnswer: String?) {
        progress.visibility = GONE
        answer.text = if (savedAnswer == null) NativeAiConsent.prompt else "$savedAnswer\n\n${NativeAiConsent.prompt}"
        answer.setTextColor(NativeReadingStyle.muted)
        retry.isEnabled = false
        retry.visibility = GONE
    }

    fun enableExplanation(savedAnswer: String?) {
        if (retry.visibility != GONE) return
        if (savedAnswer != null) {
            showAnswer(savedAnswer)
            return
        }
        progress.visibility = GONE
        answer.text = "可结合当前原句请求讲解。"
        retry.text = "请求语境讲解"
        retry.visibility = VISIBLE
        retry.isEnabled = true
    }

    private fun updateBookmark() {
        bookmark.setImageDrawable(BookmarkDrawable(saved,NativeReadingStyle.accent))
        bookmark.contentDescription = if (saved) "已收藏：${hit.surface}" else "收藏生词：${hit.surface}"
    }
    private fun restoreCard() {
        scroll.removeAllViews()
        scroll.addView(content)
        scroll.scrollTo(0, 0)
    }
    private fun showWords() {
        val list = LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        list.addView(action("返回当前词卡", ::restoreCard))
        if (words.isEmpty()) {
            list.addView(label("当前页没有可用词卡，请重新识别。", 14f, NativeReadingStyle.muted))
        }
        words.forEach { word ->
            val meaning = word.annotation ?: MultilingualTranslator.compact(word.translation)
            list.addView(action("${word.surface} · $meaning") { onWord(word) }.apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                contentDescription = "查看词卡：${word.surface}"
            })
            list.addView(NativeReadingStyle.divider(context))
        }
        scroll.removeAllViews()
        scroll.addView(list)
        scroll.scrollTo(0, 0)
    }

    private fun showChoices(selected: String, title: String) {
        val list = LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        list.addView(action("返回当前词卡", ::restoreCard))
        list.addView(label("选择$title", 18f).apply {
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(8), dp(8), dp(8), dp(12))
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        })
        choices.forEach { (key, name) ->
            val current = key == selected
            list.addView(action(if (current) "$name   ✓" else name) { onScope(key) }.apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                isSelected = current
                contentDescription = if (current) "$name，当前范围" else name
            })
            list.addView(NativeReadingStyle.divider(context))
        }
        scroll.removeAllViews()
        scroll.addView(list)
        scroll.scrollTo(0, 0)
    }

    private fun label(value:String,size:Float,color:Int=NativeReadingStyle.ink) = TextView(context).apply {
        text=value; textSize=size; setTextColor(color); includeFontPadding=false
    }
    private fun action(value:String, callback:()->Unit) = Button(context).apply {
        text=value; textSize=14f; isAllCaps=false; includeFontPadding=false; gravity=Gravity.CENTER; setTextColor(NativeReadingStyle.accent)
        background=NativeReadingStyle.control(context); stateListAnimator=null
        minimumWidth=dp(48); minWidth=dp(48); minimumHeight=dp(48); minHeight=dp(48)
        setPadding(dp(10),dp(8),dp(10),dp(8)); setOnClickListener { callback() }
    }
    private fun emphasize(sentence:String,word:String):SpannableString = SpannableString(sentence).apply {
        if(word.isNotBlank()) Regex(Regex.escape(word),RegexOption.IGNORE_CASE).findAll(sentence).forEach { match ->
            setSpan(StyleSpan(Typeface.BOLD),match.range.first,match.range.last+1,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(ForegroundColorSpan(NativeReadingStyle.accent),match.range.first,match.range.last+1,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }
}

private class BookmarkDrawable(private val filled:Boolean,private val color:Int):Drawable() {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    override fun draw(canvas:Canvas) {
        val width=bounds.width().toFloat();val height=bounds.height().toFloat()
        val path=Path().apply {moveTo(width*.22f,height*.12f);lineTo(width*.78f,height*.12f);lineTo(width*.78f,height*.9f);lineTo(width*.5f,height*.72f);lineTo(width*.22f,height*.9f);close()}
        paint.color=color;paint.style=if(filled)Paint.Style.FILL else Paint.Style.STROKE;paint.strokeWidth=width*.08f;paint.strokeJoin=Paint.Join.ROUND
        canvas.save();canvas.translate(bounds.left.toFloat(),bounds.top.toFloat());canvas.drawPath(path,paint);canvas.restore()
    }
    override fun setAlpha(alpha:Int){paint.alpha=alpha;invalidateSelf()}
    override fun setColorFilter(filter:ColorFilter?){paint.colorFilter=filter;invalidateSelf()}
    @Deprecated("Android Drawable compatibility") override fun getOpacity()=PixelFormat.TRANSLUCENT
}
