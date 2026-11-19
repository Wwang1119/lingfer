package com.wang.lingfer.screen

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Reading controls anchored to the floating button. */
internal class NativeReadingMenu(
    context: Context,
    options: ReadingOptions,
    paused: Boolean,
    words: List<WordHit>,
    onClose: () -> Unit,
    onPause: () -> Unit,
    onRefresh: () -> Unit,
    onStop: () -> Unit,
    onScope: (String) -> Unit,
    onLanguage: (String, String) -> Unit,
    onWord: (WordHit) -> Unit,
    onApp: () -> Unit,
    onMode: (String) -> Unit = {},
    onPage: () -> Unit = {},
    paragraphs: List<PageParagraph> = emptyList(),
    onParagraph: (PageParagraph) -> Unit = {},
    error: String? = null,
    detectedLanguage: String? = null,
    scope: LearningScope = options.learningScope(detectedLanguage),
) : LinearLayout(context) {
    private fun dp(value: Int) = NativeReadingStyle.dp(context, value.toFloat())

    init {
        orientation = VERTICAL
        background = NativeReadingStyle.glass(context)
        clipToOutline = true
        setPadding(dp(12), dp(10), dp(12), dp(6))

        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        val back = action("返回") {}.apply { visibility = GONE }
        val title = TextView(context).apply {
            textSize = 22f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            typeface = NativeReadingStyle.heading(context)
            setTextColor(NativeReadingStyle.ink)
            setPadding(dp(6), 0, 0, 0)
            if (android.os.Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        }
        heading.addView(back, LayoutParams(-2, -2))
        heading.addView(title, LayoutParams(0, -2, 1f))
        heading.addView(action("关闭", callback = onClose), LayoutParams(-2, -2))
        addView(heading)

        val content = LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(dp(2), dp(4), dp(2), dp(4))
        }
        val scroll = ScrollView(context).apply { addView(content) }
        addView(scroll, LayoutParams(-1, 0, 1f))

        fun screen(name: String, parent: (() -> Unit)? = null) {
            title.text = name
            content.removeAllViews()
            scroll.scrollTo(0, 0)
            back.visibility = if (parent == null) GONE else VISIBLE
            back.setOnClickListener { parent?.invoke() }
        }

        fun note(value: String, color: Int = NativeReadingStyle.muted) {
            content.addView(TextView(context).apply {
                text = value
                textSize = 13f
                setTextColor(color)
                setPadding(dp(6), dp(4), dp(6), dp(12))
            })
        }

        fun option(label: String, selected: Boolean, callback: () -> Unit) {
            val mark = if (selected) "check" else null
            content.addView(action(label, trailing = mark, callback = callback).apply {
                isSelected = selected
                if (selected) background = NativeReadingStyle.control(context, NativeReadingStyle.tint)
            })
        }

        lateinit var root: () -> Unit
        lateinit var settings: () -> Unit
        lateinit var languages: () -> Unit

        fun languageChoice(key: String, label: String, selected: String, allowAuto: Boolean) {
            screen(label, languages)
            ReadingOptions.languages.filter { allowAuto || it.key != "auto" }.forEach { (code, name) ->
                option(name, code == selected) { onLanguage(key, code) }
            }
        }

        val sourceName = ReadingOptions.languages[options.source]
        val targetName = ReadingOptions.languages[options.target]
        val languagePair = "$sourceName → $targetName"
        val isTranslation = options.mode == "translation"
        val modeName = if (isTranslation) "整页对照" else "学习辅助"
        languages = {
            screen("翻译语言", settings)
            content.addView(action("原文 · $sourceName", trailing = "next") {
                languageChoice("sourceLanguage", "原文语言", options.source, true)
            })
            content.addView(action("译文 · $targetName", trailing = "next") {
                languageChoice("targetLanguage", "译文语言", options.target, false)
            })
        }
        settings = {
            screen("阅读设置", root)
            content.addView(action("阅读方式 · $modeName", trailing = "next") {
                screen("阅读方式", settings)
                option("学习辅助 · 按难度筛词", options.mode == "learning") { onMode("learning") }
                option("整页对照 · 完整译文，需联网", isTranslation) { onMode("translation") }
            })
            if (options.mode == "learning") {
                content.addView(action("${scope.title} · ${scope.label}", trailing = "next") {
                    screen(scope.title, settings)
                    scope.choices.forEach { (key, label) ->
                        option(label, key == scope.value) { onScope(key) }
                    }
                })
            }
            content.addView(action("翻译语言 · $languagePair", trailing = "next", callback = languages))
        }
        root = {
            screen("阅读菜单")
            val summary = if (isTranslation) modeName else "$modeName · ${scope.label}"
            note("$summary · $languagePair")
            if (error == NativeAiConsent.prompt) {
                note(error)
            } else if (error != null) {
                note(error, NativeReadingStyle.warning)
                val source = if (options.source == "auto") detectedLanguage else options.source
                if (isTranslation && source == options.target) {
                    val target = if (source == "zh") "en" else "zh"
                    content.addView(action("改译成${ReadingOptions.languages[target]}") {
                        onLanguage("targetLanguage", target)
                    })
                } else {
                    content.addView(action("重试当前页", "refresh", callback = onRefresh))
                }
            }

            val readPage = action("整页对照", "book", "next", primary = isTranslation, callback = onPage)
            if (isTranslation) content.addView(readPage) else {
                content.addView(action("选段翻译", "book", "next", primary = true) {
                    screen("选段翻译", root)
                    if (paragraphs.isEmpty()) {
                        note("当前页还没有识别到段落。")
                        content.addView(action("收起并重新识别", "refresh", callback = onRefresh))
                    }
                    for (paragraph in paragraphs) {
                        content.addView(action(paragraph.source, trailing = "next") { onParagraph(paragraph) }.apply {
                            maxLines = 3
                            ellipsize = android.text.TextUtils.TruncateAt.END
                        })
                        content.addView(NativeReadingStyle.divider(context))
                    }
                })
                content.addView(readPage)
                val label = if (words.isEmpty()) "本页词卡" else "本页词卡 · ${words.size} 个"
                content.addView(action(label, "book", "next") {
                    screen("本页词卡", root)
                    if (words.isEmpty()) {
                        if (error == NativeAiConsent.prompt) {
                            note(error)
                        } else {
                            note("还没有词卡。页面停稳后可以重新识别，也可以在阅读设置调整范围。")
                            content.addView(action("收起并重新识别", "refresh", callback = onRefresh))
                        }
                    }
                    words.forEach { word ->
                        val meaning = word.annotation ?: MultilingualTranslator.compact(word.translation)
                        content.addView(action("${word.surface} · $meaning") { onWord(word) })
                    }
                })
            }
            val pauseLabel = if (paused) "继续识别" else "暂停识别"
            val pauseIcon = if (paused) "play" else "pause"
            content.addView(action(pauseLabel, pauseIcon, callback = onPause))
            content.addView(action("阅读设置", "settings", "next", callback = settings))
            content.addView(action("更多", "more", "next") {
                screen("更多", root)
                content.addView(action("重新识别当前页", "refresh", callback = onRefresh))
                content.addView(action("回到语渡 · 生词本与设置", trailing = "next", callback = onApp))
            })
        }
        root()
        addView(NativeReadingStyle.divider(context))
        addView(action("停止阅读", "stop", callback = onStop).apply {
            setTextColor(NativeReadingStyle.warning)
        })
    }

    private fun action(
        title: String,
        leading: String? = null,
        trailing: String? = null,
        primary: Boolean = false,
        callback: () -> Unit,
    ): Button {
        val iconColor = if (primary) Color.WHITE else NativeReadingStyle.accent
        fun icon(name: String, size: Int) = NativeReadingIcon(name, iconColor).apply {
            setBounds(0, 0, dp(size), dp(size))
        }

        return Button(context).apply {
            text = title
            textSize = 15f
            isAllCaps = false
            includeFontPadding = false
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setTextColor(if (primary) Color.WHITE else NativeReadingStyle.ink)
            val fill = if (primary) NativeReadingStyle.deepAccent else Color.TRANSPARENT
            background = NativeReadingStyle.control(context, fill)
            stateListAnimator = null
            minHeight = dp(if (primary) 56 else 48)
            minimumHeight = minHeight
            minWidth = dp(48)
            minimumWidth = minWidth
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setCompoundDrawablesRelative(leading?.let { icon(it, 20) }, null, trailing?.let { icon(it, 16) }, null)
            compoundDrawablePadding = dp(12)
            setOnClickListener { callback() }
        }
    }
}
