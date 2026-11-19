package com.wang.lingfer.screen

import android.content.Context
import android.graphics.Rect
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ScrollView
import android.widget.TextView

/** The fake window manager retains real Android views and their exact input rectangles. */
internal fun verifyParagraphAnnotations(context: Context) {
    val system = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    val views = linkedMapOf<View, WindowManager.LayoutParams>()
    val windows = object : WindowManager by system {
        override fun addView(view: View, params: ViewGroup.LayoutParams) {
            views[view] = params as WindowManager.LayoutParams
        }
        override fun removeView(view: View) { check(views.remove(view) != null) }
    }
    fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    fun named(label: String) = views.keys.flatMap(::descendants).single { it.contentDescription == label }
    fun target(source: String) = named("翻译此段：$source")
    fun card() = views.keys.single { root -> descendants(root).any { it is ScrollView } }
    fun texts(root: View) = descendants(root).filterIsInstance<TextView>().map { it.text.toString() }
    fun row(id: String, value: String, x: Float, y: Float, width: Int = 215) =
        OcrLine(id, value, RectF(x, y, x + width, y + 18), 0, emptyList(), id)

    val page = OcrPage(listOf(row("a", "First paragraph.", 40f, 100f), row("b", "Second paragraph.", 40f, 270f)), 320, 540)
    val area = Rect(0, 0, 1080, 1800)
    val originals = page.paragraphs
    val longTranslation = "每行文字可以向上滑动，继续阅读下面的译文。".repeat(160)
    val ready = originals.map { it.copy(translation = if (it.id == "b") longTranslation else "译文 a") }
    var changing = false
    var recoveries = 0
    var regionChanges = 0
    val annotations = ParagraphAnnotations(context, windows, { check(changing); regionChanges++ }, { recoveries++ }) {
        check(changing != it)
        changing = it
    }
    annotations.show(page, originals, true, null, area, emptyList())
    check(!changing && views.size == 1)
    val rail = annotations.regions.single()
    check(rail.width() < area.width() * .12 && rail.right < area.centerX())
    check(!rail.contains(area.exactCenterX(), rail.centerY()))
    val first = target("First paragraph.")
    val second = target("Second paragraph.")
    val firstParams = first.layoutParams as android.widget.FrameLayout.LayoutParams
    val secondParams = second.layoutParams as android.widget.FrameLayout.LayoutParams
    check(first.parent === second.parent && firstParams.topMargin + firstParams.height == secondParams.topMargin)
    first.performClick()
    check(texts(card()).contains("正在翻译此段…") && annotations.regions.size == 2)
    annotations.show(page, ready, false, null, area, emptyList())
    check("译文 a" in texts(card()))
    val firstCard = card()
    first.performClick()
    check(card() === firstCard) // The open translation stays open until explicitly dismissed or another is selected.
    second.performClick()
    val selectedCard = card()
    val selectedBounds = RectF(annotations.persistentRegion!!)
    check(longTranslation in texts(selectedCard) && "译文 a" !in texts(selectedCard))
    check(RectF(area).contains(selectedBounds) && !RectF.intersects(rail, selectedBounds))
    check(selectedBounds.height() <= area.height() * .35f && selectedBounds.width() <= area.width() * .86f)
    val scroll = named("本段译文") as ScrollView
    selectedCard.layout(0, 0, selectedCard.measuredWidth, selectedCard.measuredHeight)
    check(scroll.canScrollVertically(1))
    check(scroll.height < scroll.getChildAt(0).height)
    annotations.show(page, ready, false, null, area, emptyList())
    check(card() === selectedCard && annotations.persistentRegion == selectedBounds)

    annotations.hide()
    check(views.keys.single() === selectedCard && annotations.regions.single() == selectedBounds)
    // Paragraph ids restart on a different page. A pinned source cannot silently change beneath its translation.
    val next = OcrPage(listOf(row("b", "Recycled id.", 45f, 90f), row("z", "x", 100f, 160f)), 320, 540)
    val visible = next.paragraphs.take(1)
    annotations.show(next, visible, true, null, area, emptyList())
    check(card() === selectedCard && named("原文节选：Second paragraph.").visibility == View.VISIBLE)
    check(views.keys.flatMap(::descendants).none { it.contentDescription == "翻译此段：x" })
    val newTarget = target("Recycled id.")
    newTarget.performClick()
    check("正在翻译此段…" in texts(card()) && longTranslation !in texts(card()))
    annotations.show(next, visible, false, NativeAiConsent.prompt, area, emptyList())
    fun recover(label: String) = descendants(card()).filterIsInstance<TextView>().single { it.text == label }.performClick()
    check(recover("回语渡设置") && recoveries == 1)
    annotations.show(next, visible, false, "原文和译文设为相同语言。", area, emptyList())
    check(recover("切换译文语言") && recoveries == 2)
    annotations.show(next, visible, false, "连接中断", area, emptyList())
    check(recover("重试翻译") && recoveries == 3)
    check(named("收起本段译文").performClick() && views.size == 1 && annotations.persistentRegion == null)

    val columns = OcrPage(listOf(row("l", "Left text.", 20f, 96f, 121), row("r", "Right text.", 175f, 96f, 121)), 320, 540)
    annotations.show(columns, columns.paragraphs.map { it.copy(translation = it.source + " translated") }, false, null, area, emptyList())
    val left = annotations.regions.single { it.centerX() < area.centerX() }
    val right = annotations.regions.single { it.centerX() > area.centerX() }
    check(views.size == 2 && left.right < right.left)
    target("Right text.").performClick()
    check("Right text. translated" in texts(card()))
    check(!RectF.intersects(annotations.persistentRegion!!, right) && !RectF.intersects(annotations.persistentRegion!!, left))
    target("Left text.").performClick()
    check("Left text. translated" in texts(card()) && "Right text. translated" !in texts(card()))
    annotations.clear()
    check(views.isEmpty() && annotations.regions.isEmpty() && !changing && regionChanges > 5)
}
