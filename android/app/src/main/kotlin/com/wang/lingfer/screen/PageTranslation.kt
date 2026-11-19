package com.wang.lingfer.screen

import android.content.Context
import android.view.Gravity
import android.widget.*
import org.json.JSONObject

data class PageParagraph(val id:String,val source:String,val translation:String?=null) {
    fun nativeMap():Map<String,Any?> = mapOf("id" to id,"source" to source,"translation" to translation)
    fun json()=JSONObject().put("id",id).put("source",source).put("translation",translation ?: JSONObject.NULL)
}

internal class NativePageTranslationPanel(
    context: Context,
    private val onClose: () -> Unit,
    private val onRetry: () -> Unit,
    private val onStop: () -> Unit,
    private val onSettings: () -> Unit = {},
    title: String = "整页对照",
    private val maxPanelHeight: Int? = null,
) : LinearLayout(context) {
    private val content = LinearLayout(context).apply { orientation = VERTICAL }
    private fun dp(value: Int) = NativeReadingStyle.dp(context, value.toFloat())

    init {
        orientation = VERTICAL
        background = NativeReadingStyle.glass(context)
        clipToOutline = true
        val heading = LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(5), dp(8), dp(2))
        }
        heading.addView(TextView(context).apply {
            text = title
            textSize = 22f
            typeface = NativeReadingStyle.heading(context)
            setTextColor(NativeReadingStyle.ink)
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        }, LayoutParams(0, -2, 1f))
        heading.addView(action("关闭面板", onClose))
        addView(heading)
        addView(ScrollView(context).apply { addView(content) }, LayoutParams(-1, 0, 1f))
        addView(NativeReadingStyle.divider(context))
        addView(action("停止阅读", onStop).apply { setTextColor(NativeReadingStyle.warning) })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val limit = maxPanelHeight ?: return super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val available = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) limit
            else minOf(limit, MeasureSpec.getSize(heightMeasureSpec))
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST))
    }

    fun show(parts: List<PageParagraph>, loading: Boolean, error: String?) {
        content.removeAllViews()
        content.setPadding(dp(16), dp(2), dp(16), dp(12))
        val translated = parts.count { it.translation != null }
        val status = if (loading) "正在翻译" else "已翻译"
        content.addView(label("$status $translated / ${parts.size} 段", 13f, true))
        if (loading) {
            val progress = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
                isIndeterminate = translated == 0
                max = parts.size.coerceAtLeast(1)
                this.progress = translated
                val accent = android.content.res.ColorStateList.valueOf(NativeReadingStyle.accent)
                indeterminateTintList = accent
                progressTintList = accent
                progressBackgroundTintList = android.content.res.ColorStateList.valueOf(NativeReadingStyle.tint)
            }
            content.addView(progress, LayoutParams(-1, dp(4)).apply { bottomMargin = dp(10) })
        }
        if (error == NativeAiConsent.prompt) {
            content.addView(label(error, 15f, true))
        } else if (error != null) {
            content.addView(label(error, 15f, false).apply { setTextColor(NativeReadingStyle.warning) })
            val recovery = if (error.contains("相同语言")) {
                action("更改语言或阅读方式", onSettings)
            } else {
                action("重试未完成段落", onRetry)
            }
            content.addView(recovery)
        }
        if (parts.isEmpty() && !loading && error == null) {
            content.addView(label("当前页没有文字，请关闭面板后停稳页面。", 16f, true))
            content.addView(action("收起并重新识别", onRetry))
        }
        parts.forEach { part ->
            val pair = LinearLayout(context).apply {
                orientation = VERTICAL
                background = NativeReadingStyle.surface(context, 16f)
                setPadding(dp(14), dp(4), dp(14), dp(6))
            }
            pair.addView(label(part.source, 16f, false).apply { typeface = android.graphics.Typeface.SERIF })
            pair.addView(NativeReadingStyle.divider(context))
            pair.addView(label(part.translation ?: "尚未翻译", 17f, true).apply {
                if (part.translation != null) setTextColor(NativeReadingStyle.accent)
            })
            content.addView(pair, LayoutParams(-1, -2).apply { bottomMargin = dp(8) })
        }
    }

    private fun label(value: String, size: Float, muted: Boolean) = TextView(context).apply {
        text = value
        textSize = size
        setTextColor(if (muted) NativeReadingStyle.muted else NativeReadingStyle.ink)
        setLineSpacing(dp(5).toFloat(), 1f)
        setPadding(0, dp(8), 0, dp(8))
        setTextIsSelectable(true)
    }

    private fun action(value: String, callback: () -> Unit) = Button(context).apply {
        text = value
        textSize = 14f
        isAllCaps = false
        includeFontPadding = false
        gravity = Gravity.CENTER
        minimumHeight = dp(48)
        minHeight = dp(48)
        minWidth = dp(48)
        stateListAnimator = null
        setTextColor(NativeReadingStyle.accent)
        background = NativeReadingStyle.control(context)
        setOnClickListener { callback() }
    }
}
