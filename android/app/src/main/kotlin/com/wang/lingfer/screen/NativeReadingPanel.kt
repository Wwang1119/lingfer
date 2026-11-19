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
    val ink = Color.rgb(34, 40, 40)
    val muted = Color.rgb(102, 112, 115)
    val accent = Color.rgb(54, 95, 112)
    val tint = Color.rgb(234, 240, 241)
    val line = Color.rgb(229, 229, 234)
    val warning = Color.rgb(155, 69, 37)
    fun dp(context: Context, value: Float) = (context.resources.displayMetrics.density * value).toInt()
    private var displayFont: Typeface? = null
    fun heading(context: Context): Typeface = displayFont ?: run {
        val font = try { Typeface.createFromAsset(context.assets,"flutter_assets/assets/fonts/lingfer-display-semibold.ttf") }
            catch (_: Exception) { Typeface.create("serif", Typeface.NORMAL) }
        displayFont=font; font
    }
    fun glass(context: Context, backdrop: Bitmap? = null) = GlassDrawable(backdrop,dp(context,28f).toFloat())
    fun control(context: Context, filled: Boolean = false): Drawable {
        val shape=GradientDrawable().apply {cornerRadius=dp(context,16f).toFloat();setColor(if(filled) tint else 0xA6FFFFFF.toInt())}
        return android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x17365F70),shape,null)
    }
    fun animateIn(view: View) {
        if(android.os.Build.VERSION.SDK_INT>=26 && !android.animation.ValueAnimator.areAnimatorsEnabled()) return
        view.alpha=0f;view.translationY=dp(view.context,8f).toFloat()
        view.animate().alpha(1f).translationY(0f).setDuration(180).start()
    }

    fun surface(context: Context, radius: Float = 24f, topOnly: Boolean = false) = GradientDrawable().apply {
        setColor(paper); setStroke(dp(context, 1f).coerceAtLeast(1), line)
        val r = dp(context, radius).toFloat()
        if (topOnly) cornerRadii = floatArrayOf(r,r,r,r,0f,0f,0f,0f) else cornerRadius = r
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
    private val content = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(16),dp(16),dp(16),dp(16)) }
    private val range = action("$scopeName · ${choices.firstOrNull { it.first == scope }?.second ?: scope}  ⌄") { showChoices(scope, scopeName) }.apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL }
    private val countLabel = action("本页 ${words.size} 个词 · 查看全部") { showWords() }.apply { gravity=Gravity.START or Gravity.CENTER_VERTICAL; textSize=12f; setTextColor(NativeReadingStyle.muted) }

    init {
        orientation = VERTICAL; background = NativeReadingStyle.glass(context)
        elevation = 0f; clipToOutline = true
        val compact = context.resources.configuration.screenHeightDp in 1..479 || context.resources.configuration.fontScale > 1.3f
        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(18),dp(8),dp(8),dp(4)) }
        heading.addView(label(if(compact) "词卡 ${words.size}" else "本页词卡", 22f).apply { typeface=NativeReadingStyle.heading(context); if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true; if(compact) { minimumHeight=dp(48);gravity=Gravity.CENTER_VERTICAL;setOnClickListener { showWords() } } }, LayoutParams(0, -2, 1f))
        if(compact) heading.addView(range.apply { text="${choices.firstOrNull { it.first==scope }?.second ?: scope} ⌄";contentDescription="$scopeName，点按调整" })
        heading.addView(action("关闭", onClose).apply { contentDescription = "关闭面板" })
        addView(heading)
        val summary = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(10),0,dp(18),dp(10)) }
        if(!compact) { summary.addView(range); summary.addView(countLabel); addView(summary) }
        addView(rule())
        scroll.addView(content); addView(scroll, LayoutParams(-1, 0, 1f))
        val card = LinearLayout(context).apply { orientation = VERTICAL; background = NativeReadingStyle.surface(context); setPadding(dp(16),dp(12),dp(16),dp(16)) }
        val wordHeader = LinearLayout(context).apply { gravity = Gravity.TOP }
        wordHeader.addView(label(hit.surface, 27f).apply { typeface = Typeface.create("serif", Typeface.NORMAL); setLineSpacing(dp(3).toFloat(),1f) }, LayoutParams(0,-2,1f))
        bookmark.apply {
            minimumWidth = dp(48); minimumHeight = dp(48); setPadding(dp(12),dp(12),dp(12),dp(12))
            background = android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
            setOnClickListener { onSave(); saved = true; updateBookmark() }
        }
        updateBookmark(); wordHeader.addView(bookmark, LayoutParams(dp(48), dp(48))); card.addView(wordHeader)
        card.addView(label(hit.translation, 16f).apply { setPadding(0,dp(10),0,dp(16)); setLineSpacing(dp(5).toFloat(),1.15f) })
        val sentence = LinearLayout(context).apply { orientation = HORIZONTAL }
        sentence.addView(View(context).apply { setBackgroundColor(NativeReadingStyle.line) }, LayoutParams(dp(2), -1))
        val sentenceBody = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(12),0,0,0) }
        sentenceBody.addView(label("原句",12f,NativeReadingStyle.muted))
        sentenceBody.addView(label("",16f).apply {
            text = emphasize(hit.context, hit.surface); typeface = Typeface.create("serif",Typeface.NORMAL)
            setTextIsSelectable(true); setPadding(0,dp(6),0,dp(4)); setLineSpacing(dp(6).toFloat(),1.15f)
        })
        sentence.addView(sentenceBody, LayoutParams(0,-2,1f)); card.addView(sentence)
        card.addView(action("标为熟词",onKnown).apply { setTextColor(NativeReadingStyle.muted); contentDescription = "标为熟词：${hit.surface}" })
        card.addView(rule())
        card.addView(label("语境讲解",14f,NativeReadingStyle.accent).apply { setTypeface(typeface,Typeface.BOLD); setPadding(0,dp(16),0,dp(8)) })
        card.addView(progress, LayoutParams(dp(24),dp(24)).apply { bottomMargin=dp(8) })
        card.addView(answer)
        card.addView(retry)
        content.addView(card)
        content.addView(label("关闭面板后继续随屏阅读；停止阅读将结束捕获会话。",12f,NativeReadingStyle.muted).apply { setPadding(0,dp(14),0,0) })
        addView(rule())
        val footer = LinearLayout(context).apply {
            orientation = if (context.resources.configuration.fontScale > 1.3f && !compact) VERTICAL else HORIZONTAL
            gravity = Gravity.END; setPadding(dp(10),dp(6),dp(10),dp(8))
        }
        footer.addView(action("重新识别",onRefresh))
        footer.addView(action("停止阅读",onStop).apply { contentDescription = "停止阅读并结束捕获" })
        addView(footer)
    }

    fun showLoading() {
        progress.visibility = VISIBLE; answer.text = "正在结合原文讲解…"
        answer.setTextColor(NativeReadingStyle.muted); retry.isEnabled = false
        retry.text = "正在讲解"
    }
    fun showAnswer(value: String) {
        progress.visibility = GONE; answer.text = value
        answer.setTextColor(if (value == "详解暂未响应，原词译义和收藏仍可使用。") NativeReadingStyle.warning else NativeReadingStyle.ink)
        retry.isEnabled = true; retry.text = "重新请求讲解"
    }
    private fun updateBookmark() {
        bookmark.setImageDrawable(BookmarkDrawable(saved,NativeReadingStyle.accent))
        bookmark.contentDescription = if (saved) "已收藏：${hit.surface}" else "收藏生词：${hit.surface}"
    }
    private fun showWords() {
        val list=LinearLayout(context).apply { orientation=VERTICAL;setPadding(dp(8),dp(8),dp(8),dp(8)) }
        list.addView(label("本页词卡",18f).apply { setTypeface(typeface,Typeface.BOLD);setPadding(dp(8),dp(8),dp(8),dp(12)) })
        if(words.isEmpty()) list.addView(label("当前页没有可用词卡，请重新识别。",14f,NativeReadingStyle.muted))
        words.forEach { word ->
            list.addView(action("${word.surface} · ${word.annotation ?: MultilingualTranslator.compact(word.translation)}") { onWord(word) }.apply {
                gravity=Gravity.START or Gravity.CENTER_VERTICAL; contentDescription="查看词卡：${word.surface}"
            })
            list.addView(rule())
        }
        scroll.removeAllViews();scroll.addView(list)
    }
    private fun showChoices(selected: String, title: String) {
        val list = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(8),dp(8),dp(8),dp(8)) }
        list.addView(label("选择$title",18f).apply { setTypeface(typeface,Typeface.BOLD); setPadding(dp(8),dp(8),dp(8),dp(12)); if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading=true })
        choices.forEach { (key,name) ->
            list.addView(action(if (key==selected) "$name   ✓" else name) { onScope(key) }.apply {
                gravity=Gravity.START or Gravity.CENTER_VERTICAL; isSelected=key==selected; contentDescription="$name${if(key==selected) "，当前范围" else ""}"
            })
            list.addView(rule())
        }
        scroll.removeAllViews(); scroll.addView(list)
        range.isEnabled=false
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
    private fun rule() = View(context).apply { setBackgroundColor(NativeReadingStyle.line); layoutParams=LayoutParams(-1,dp(1).coerceAtLeast(1)) }
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
