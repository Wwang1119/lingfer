package com.wang.lingfer.screen

import android.content.Context
import android.graphics.Rect
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.roundToInt

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
    check(!changing)
    val density = context.resources.displayMetrics.density
    fun px(dp: Int) = (density * dp).roundToInt()
    val marks = views.entries.filter { it.key.contentDescription?.startsWith("翻译此段：") == true }
    check(marks.size == 2)
    check(views.values.none { it.height > px(24) }) { "A full-height rail is still a toolbar" }
    check(marks.all {
        it.value.height <= px(22) && it.value.width <= px(10) &&
            it.value.x >= px(4) && it.value.x + it.value.width <= area.right - px(4) &&
            it.value.flags and OVERLAY_FLAG_SLIPPERY != 0
    }) { "Margin marks should be short, inset, and able to release a swipe" }
    val tops = marks.map { it.value.y }.sorted()
    check(tops[1] > tops[0] + px(8)) { "Touch targets must leave a gap the page can scroll through" }
    check(marks.all { it.value.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE == 0 })
    val first = target("First paragraph.")
    val second = target("Second paragraph.")
    fun gesture(view: View, action: Int, y: Float, time: Long) {
        val event = MotionEvent.obtain(0, time, action, 6f, y, 0)
        view.dispatchTouchEvent(event)
        event.recycle()
    }
    gesture(first, MotionEvent.ACTION_DOWN, 8f, 0)
    gesture(first, MotionEvent.ACTION_MOVE, 8f + px(48), 40)
    gesture(first, MotionEvent.ACTION_UP, 8f + px(48), 80)
    check(views.keys.none { root -> descendants(root).any { it is ScrollView } }) { "A swipe past the slop opened a paragraph" }
    check(views.getValue(first).flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0) {
        "The mark kept the gesture after it became a scroll"
    }
    gesture(first, MotionEvent.ACTION_DOWN, 8f, 200)
    gesture(first, MotionEvent.ACTION_UP, 10f, 260)
    check(texts(card()).contains("正在翻译此段…"))
    check(annotations.regions.count { it.height() > px(40) } == 1) { "Only the open card should be a tall window" }
    annotations.show(page, ready, false, null, area, emptyList())
    check("译文 a" in texts(card()))
    val firstCard = card()
    first.performClick()
    check(card() === firstCard) // The open translation stays open until explicitly dismissed or another is selected.
    second.performClick()
    val selectedCard = card()
    val selectedBounds = RectF(annotations.persistentRegion!!)
    check(longTranslation in texts(selectedCard) && "译文 a" !in texts(selectedCard))
    check(RectF(area).contains(selectedBounds))
    check(annotations.regions.filter { it.height() <= px(28) }.all { !RectF.intersects(it, selectedBounds) })
    check(selectedBounds.height() <= area.height() * .55f && selectedBounds.width() <= area.width() * .75f)
    val excerpt = named("原文节选：Second paragraph.") as TextView
    check(excerpt.textSize >= 15f * density && excerpt.maxLines >= 2) { "The source line is still a cramped caption" }
    val dismiss = named("收起本段译文") as TextView
    check(dismiss.background == null && dismiss.currentTextColor == com.wang.lingfer.screen.NativeReadingStyle.muted)
    val scroll = named("本段译文") as ScrollView
    selectedCard.layout(0, 0, selectedCard.measuredWidth, selectedCard.measuredHeight)
    check(scroll.canScrollVertically(1))
    check(scroll.height < scroll.getChildAt(0).height)
    check(scroll.height > excerpt.textSize * 3) { "A long translation shows only a line or two" }
    annotations.show(page, ready, false, null, area, emptyList())
    check(card() === selectedCard && annotations.persistentRegion == selectedBounds)

    val shifted = OcrPage(listOf(row("a", "First paragraph.", 40f, 112f), row("b", "Second paragraph.", 40f, 292f)), 320, 540)
    annotations.show(shifted, originals, true, null, area, emptyList())
    check(longTranslation in texts(card()) && "正在翻译" !in texts(card()).joinToString())
    check(named("原文节选：Second paragraph.").visibility == View.VISIBLE)
    check((annotations.persistentRegion!!.top - selectedBounds.top) > 8f) { "A small scroll left the card on the old line" }

    annotations.hide()
    check(views.keys.single() === card() && annotations.persistentRegion != null) { "Hiding ticks for a clean frame removed the card" }
    val keptAfterHide = annotations.persistentRegion
    // A new page must not keep the old translation as if it described the new paragraph.
    val next = OcrPage(listOf(row("b", "Recycled id.", 45f, 90f), row("z", "x", 100f, 160f)), 320, 540)
    val visible = next.paragraphs.take(1)
    annotations.show(next, visible, true, null, area, emptyList())
    check(named("原文节选：Second paragraph.").visibility == View.VISIBLE)
    check(ParagraphAnnotations.DEPARTED in texts(card()) && longTranslation !in texts(card()))
    check(texts(card()).none { it.contains("Recycled id.") })
    check(annotations.persistentRegion != keptAfterHide) { "The card stayed on coordinates from the previous page" }
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
    annotations.clear()
    check(views.isEmpty() && annotations.regions.isEmpty()) { "clear() left a card that hide() is supposed to keep" }

    val columns = OcrPage(listOf(row("l", "Left text.", 20f, 96f, 121), row("r", "Right text.", 175f, 96f, 121)), 320, 540)
    annotations.show(columns, columns.paragraphs.map { it.copy(translation = it.source + " translated") }, false, null, area, emptyList())
    val left = annotations.regions.single { it.centerX() < area.centerX() }
    val right = annotations.regions.single { it.centerX() > area.centerX() }
    check(views.size == 2 && left.right < right.left && left.height() <= px(22) && right.height() <= px(22))
    target("Right text.").performClick()
    check("Right text. translated" in texts(card()))
    check(!RectF.intersects(annotations.persistentRegion!!, right) && !RectF.intersects(annotations.persistentRegion!!, left))
    target("Left text.").performClick()
    check("Left text. translated" in texts(card()) && "Right text. translated" !in texts(card()))
    annotations.clear()
    check(views.isEmpty() && annotations.regions.isEmpty() && !changing && regionChanges > 5)
}
