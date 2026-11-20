package com.wang.lingfer.screen

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.widget.ScrollView
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import java.io.File

/** Runs the real native component with fixed display states; no service or store changes. */
class NativePanelUiInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val output=Bundle()
        try {
            val mixed="打开多个标签页即可同时访问不同网页\nThe evidence reveals a subtle distinction. Consider the essential argument before reaching a conclusion. A reliable method can improve your understanding."
            check(!NativeOcrEngine.languageSample(mixed).contains("打开")) {"Browser chrome dominated the article language sample"}
            check(NativeOcrEngine.languageSample("这是一篇中文小说，人物正在讨论下一步计划。").contains("中文小说"))
            verifyOverlayReadingRules()
            verifyOcrOverlayIsolation()
            verifyAnnotationGeometry()
            verifyWordAnnotations()
            runOnMainSync { verifyParagraphAnnotations(targetContext) }
            verifyTranslationReuse()
            verifyFullPageTranslation()
            verifySelectedParagraph()
            verifyAiConsent()
            verifyMenuNavigation()
            startActivitySync(Intent().setClassName(targetContext.packageName,"com.wang.lingfer.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val cases=listOf(Triple(320,568,1f),Triple(320,568,1.8f),Triple(829,320,1f))
            cases.forEachIndexed { index, case -> runCase(index,case.first,case.second,case.third) }
            output.putString("stream","\nNative panel: 3 viewport/font cases passed; source retention, loading/error/retry, bookmark and scope callbacks verified.\n")
            finish(Activity.RESULT_OK,output)
        } catch(error:Throwable) {
            output.putString("stream","\nNative panel test failed: ${error.stackTraceToString()}\n")
            finish(Activity.RESULT_CANCELED,output)
        }
    }
    private fun verifyOcrOverlayIsolation() {
        val source = Bitmap.createBitmap(240, 120, Bitmap.Config.ARGB_8888)
        source.eraseColor(android.graphics.Color.BLACK)
        val card = android.graphics.RectF(80f, 20f, 220f, 100f)
        val rail = android.graphics.RectF(0f, 30f, 12f, 44f)
        val masked = NativeOcrEngine.maskOverlayPixels(source, listOf(card, rail))
        check(masked.getPixel(81, 21) == android.graphics.Color.WHITE &&
            masked.getPixel(219, 99) == android.graphics.Color.WHITE &&
            masked.getPixel(3, 32) == android.graphics.Color.WHITE &&
            masked.getPixel(50, 55) == android.graphics.Color.BLACK) { "OCR input includes an owned window or removed visible paper" }
        masked.recycle()
        val cream = android.graphics.Color.rgb(250, 249, 244)
        val paper = Bitmap.createBitmap(80, 60, Bitmap.Config.ARGB_8888)
        paper.eraseColor(cream)
        paper.setPixel(20, 20, android.graphics.Color.BLACK)
        paper.setPixel(12, 20, android.graphics.Color.BLACK)
        val painted = NativeOcrEngine.maskOverlayPixels(paper, listOf(android.graphics.RectF(16f, 16f, 28f, 28f)), 6f)
        check(painted.getPixel(20, 20) == cream && painted.getPixel(12, 20) == cream) {
            "Overlay ink or a glyph glued to the card edge survived the mask"
        }
        check(painted.getPixel(70, 50) == cream)
        painted.recycle()
        val crumb = OcrLine("c", "1X1à", android.graphics.RectF(8f, 2f, 42f, 16f), 0,
            listOf(OcrWord("1X1à", android.graphics.RectF(8f, 2f, 42f, 16f), 0, 4)))
        val button = OcrLine("d", "收起", android.graphics.RectF(40f, 80f, 70f, 98f), 5, emptyList())
        val mark = OcrLine("m", "译", android.graphics.RectF(4f, 120f, 18f, 140f), 8, emptyList())
        val glued = OcrLine("g", "tion", android.graphics.RectF(90f, 40f, 130f, 58f), 10,
            listOf(OcrWord("tion", android.graphics.RectF(90f, 40f, 130f, 58f), 10, 14)))
        val prose = "Researchers maintain that consistent practice matters."
        val body = OcrLine("p", prose, android.graphics.RectF(40f, 180f, 300f, 210f), 20, emptyList())
        val practiceAt = prose.indexOf("practice")
        val crossed = OcrLine("x", prose, android.graphics.RectF(80f, 36f, 300f, 64f), 80,
            listOf(OcrWord("practice", android.graphics.RectF(96f, 36f, 150f, 64f), 80 + practiceAt, 80 + practiceAt + "practice".length)))
        val cleaned = OcrPage.suppressOverlayNoise(
            listOf(crumb, button, mark, glued, body, crossed), 320, 400,
            listOf(android.graphics.RectF(100f, 30f, 160f, 70f)), screenChrome = true,
        )
        check(cleaned.map { it.id } == listOf("p", "x")) { "Overlay text or a status crumb stayed in the page: ${cleaned.map { it.text }}" }
        check(!cleaned.single { it.id == "x" }.text.contains("practice"))
        listOf("K", "Lib", "4/15", "4", "译", "x = 3").forEach { check(!OcrPage.isReadingParagraph(it)) }
        listOf("Abstract", "3 Model Architecture", "注意力机制", "In practice, we compute the attention function").forEach {
            check(OcrPage.isReadingParagraph(it))
        }
        val body = "In practice, we compute the attention function on a set of queries."
        val rows = listOf("Introduction" to 20f, "Linear" to 200f, "SoftMax" to 240f, "MatMul" to 290f,
            body to 20f, body to 20f, body to 20f).mapIndexed { i, (text, left) ->
            val y = if (i in 1..3) 40f else i * 32f
            OcrLine("l$i", text, android.graphics.RectF(left, y, if (i >= 4) 390f else left + 55, y + 16),
                0, emptyList(), "b$i")
        }
        val paragraphs = OcrPage(rows, 400, 400).readingParagraphs
        check(paragraphs.map { it.source } == listOf("Introduction", body, body, body)) { "Diagram labels entered paragraph translation" }
    }

    private fun verifyAnnotationGeometry() {
        val first=OcrWord("坚",android.graphics.RectF(40f,100f,62f,130f),0,1)
        val second=OcrWord("持",android.graphics.RectF(64f,94f,86f,128f),1,2)
        val wrapped=OcrWord("阅",android.graphics.RectF(40f,150f,62f,180f),3,4)
        val page=OcrPage(listOf(OcrLine("s0","坚持",android.graphics.RectF(40f,94f,86f,130f),0,listOf(first,second)),OcrLine("s1","阅",wrapped.box,3,listOf(wrapped))),300,500,"zh")
        val hit=WordHit("read","坚持\n阅","read",emptySet(),"坚持阅读",sourceStart=0,sourceEnd=4)
        val coordinates = AnnotationCoordinates(300, 500, Rect(0, 0, 300, 500))
        val runs = AnnotationGeometry.wordRuns(page, hit, coordinates, 3f)
        check(runs == listOf(android.graphics.RectF(40f, 94f, 86f, 130f), wrapped.box)) {
            "A wrapped phrase must have independent underlines on its two lines"
        }
        check(AnnotationGeometry.wordRuns(page, hit.copy(sourceStart = 1), coordinates, 3f).isEmpty()) {
            "An outdated OCR offset must not underline different text"
        }
        check(AnnotationLayout.place(android.graphics.RectF(100f,100f,150f,130f),44f,25f,android.graphics.RectF(0f,0f,1000f,1000f),listOf(android.graphics.RectF(45f,60f,210f,165f)),emptyList(),3f)==null) {"A meaning label drifted away to a page edge"}
        val background=Bitmap.createBitmap(100,100,Bitmap.Config.ARGB_8888).apply {eraseColor(android.graphics.Color.WHITE)}
        val plate=GlassDrawable(NativeGlassBackdrop.sample(background,android.graphics.RectF(0f,0f,100f,100f)),12f).apply {setBounds(0,0,100,100)}
        val firstFrame=Bitmap.createBitmap(100,100,Bitmap.Config.ARGB_8888)
        val secondFrame=Bitmap.createBitmap(100,100,Bitmap.Config.ARGB_8888)
        plate.draw(android.graphics.Canvas(firstFrame));plate.draw(android.graphics.Canvas(secondFrame))
        check(firstFrame.getPixel(50,50)==secondFrame.getPixel(50,50) && android.graphics.Color.alpha(secondFrame.getPixel(50,50))==255) {"Glass material changed opacity after a redraw"}
        plate.release();background.recycle();firstFrame.recycle();secondFrame.recycle()
        runOnMainSync {
            val orb=NativeFloatingOrb(targetContext)
            val size=NativeReadingStyle.dp(targetContext,48f)
            orb.layout(0,0,size,size)
            listOf("渡","…","Ⅱ","重试").forEach { state ->
                orb.text=state
                val bitmap=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888)
                orb.draw(android.graphics.Canvas(bitmap))
                check(android.graphics.Color.alpha(bitmap.getPixel(0,0))==0) {"Orb corners are not transparent"}
                check(android.graphics.Color.alpha(bitmap.getPixel(size/2,size/2))>0) {"Orb centre was not drawn"}
                bitmap.recycle()
            }
        }
    }
    private fun verifyWordAnnotations() {
        runOnMainSync {
            val display = Rect(0, 0, 1080, 2400)
            val available = Rect(0, 0, 1080, 2280)
            val candidates = listOf(display, available, Rect(0, 72, 1080, 2280))
            check(AnnotationGeometry.viewport(1080, 2400, candidates) == display)
            check(AnnotationGeometry.viewport(1080, 2280, candidates) == available)
            check(AnnotationGeometry.viewport(1080, 2208, candidates)?.top == 72)
            check(AnnotationGeometry.viewport(540, 1200, candidates) == null)
            val coordinates = AnnotationCoordinates(540, 1104, candidates.last())
            val ocr = android.graphics.RectF(28f, 884f, 68f, 914f)
            val overlay = coordinates.toScreen(ocr)
            check(overlay == android.graphics.RectF(56f, 1840f, 136f, 1900f) && coordinates.toCapture(overlay) == ocr)
            val context = targetContext
            val system = context.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
            val added = mutableMapOf<View, WindowManager.LayoutParams>()
            val windows = object : WindowManager by system {
                override fun addView(view: View, params: ViewGroup.LayoutParams) {
                    added[view] = params as WindowManager.LayoutParams
                }
                override fun removeView(view: View) { added.remove(view) }
            }
            val selected = mutableListOf<WordHit>()
            val annotations = GlassAnnotations(context, windows, selected::add)
            val box = android.graphics.RectF(160f, 240f, 252f, 267f)
            val first = OcrWord("maintain", box, 0, 8)
            val hit = WordHit("maintain", "maintain", "维持", emptySet(), "We maintain a habit.", sourceStart = 0, sourceEnd = 8)
            val adjacent = OcrWord("other", android.graphics.RectF(5f, 5f, 395f, 595f), 9, 14)
            val row = android.graphics.RectF(155f, 239f, 350f, 270f)
            val viewport = Rect(0, 0, 400, 600)
            fun page(words: List<OcrWord>) = OcrPage(listOf(OcrLine("s0", "maintain other", row, 0, words)), 400, 600, "en")
            val frame = Bitmap.createBitmap(400, 600, Bitmap.Config.ARGB_8888)
            try {
                for (palette in AnnotationPalette.values()) {
                    frame.eraseColor(if (palette == AnnotationPalette.LIGHT) android.graphics.Color.WHITE else android.graphics.Color.BLACK)
                    annotations.show(page(listOf(first)), listOf(hit), frame, screenArea = viewport)
                    check(added.keys.none { it is TextView }) { "A paper chip was drawn on the word" }
                    check(annotations.regions.isEmpty()) { "A resting underline was treated as page text to mask" }
                    val mark = added.keys.filterIsInstance<AnnotationWordUnderline>().single()
                    val params = added.getValue(mark)
                    check(params.x == box.left.toInt() && params.x + params.width == box.right.toInt()) {
                        "Underline width must match the actual OCR word"
                    }
                    val density = context.resources.displayMetrics.density
                    check(params.y >= box.bottom.toInt() - 1 && params.height <= kotlin.math.ceil(density * 12f).toInt()) {
                        "The word window still covers the glyphs"
                    }
                    fun inkOf(armed: Boolean): Bitmap {
                        mark.armed = armed
                        mark.layout(0, 0, params.width, params.height)
                        val drawing = Bitmap.createBitmap(params.width, params.height, Bitmap.Config.ARGB_8888)
                        mark.draw(android.graphics.Canvas(drawing))
                        return drawing
                    }
                    val resting = inkOf(false)
                    check((0 until resting.width).all { x -> (0 until resting.height).all { y -> resting.getPixel(x, y) == 0 } }) {
                        "The word underline is visible before the reader asks"
                    }
                    resting.recycle()
                    val drawing = inkOf(true)
                    check(params.flags and OVERLAY_FLAG_SLIPPERY != 0)
                    selected.clear()
                    val drag = android.view.MotionEvent.obtain(0, 0, android.view.MotionEvent.ACTION_DOWN, 4f, 2f, 0)
                    val move = android.view.MotionEvent.obtain(0, 30, android.view.MotionEvent.ACTION_MOVE, 4f, 2f + density * 30f, 0)
                    val up = android.view.MotionEvent.obtain(0, 60, android.view.MotionEvent.ACTION_UP, 4f, 2f + density * 30f, 0)
                    mark.dispatchTouchEvent(drag); mark.dispatchTouchEvent(move); mark.dispatchTouchEvent(up)
                    drag.recycle(); move.recycle(); up.recycle()
                    check(selected.isEmpty()) { "A swipe that started on the underline opened the word" }
                    check(params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0) {
                        "The overlay kept accepting the swipe. This flag does not prove the reader scrolled."
                    }
                    val center = params.width / 2
                    val inkRows = (0 until params.height).filter { drawing.getPixel(center, it) != android.graphics.Color.TRANSPARENT }
                    val thicknessLimit = kotlin.math.ceil(density * 1.1f).toInt().coerceAtLeast(1)
                    check(inkRows.size in 1..thicknessLimit && params.y + inkRows.first() > row.bottom &&
                        params.y + inkRows.first() <= row.bottom + kotlin.math.ceil(density * 1.2f) + 1) {
                        "Ink must form a fine line directly below the local baseline"
                    }
                    check((inkRows.size until params.width - inkRows.size).all { x ->
                        drawing.getPixel(x, inkRows.first()) == palette.marker
                    }) {
                        "The underline must be continuous between its rounded ends"
                    }
                    drawing.recycle()
                    selected.clear()
                    mark.performClick()
                    check(selected == listOf(hit)) { "The underline should open the word note" }
                }
                annotations.show(page(listOf(first, adjacent)), listOf(hit), frame, screenArea = viewport)
                check(added.keys.none { it is TextView }) { "Dense text must not gain a paper chip" }
                selected.clear()
                added.keys.single().performClick()
                check(selected == listOf(hit)) { "A word underline must still open the note" }
                annotations.hide()
                check(added.keys.all { it.visibility == View.INVISIBLE })
            } finally {
                annotations.clear()
                frame.recycle()
            }
            check(added.isEmpty() && annotations.regions.isEmpty())
        }
    }

    private fun verifyFullPageTranslation() {
        verifyScrolledPageRequests()
        val prefs=targetContext.getSharedPreferences("lingfer_page_qa",android.content.Context.MODE_PRIVATE)
        var calls=0
        var allowed = true
        val translator=MultilingualTranslator(prefs,OfflineVocabulary(targetContext), aiAllowed = { allowed }) {system,user->
            calls++;check(system.contains("完整翻译每段"))
            val segments=org.json.JSONObject(user).getJSONArray("segments")
            val items=org.json.JSONArray()
            // Deliberately omit the second paragraph once, preserving the first.
            for(i in 0 until (if(calls==1) 1 else segments.length())) {
                val part=segments.getJSONObject(i)
                items.put(org.json.JSONObject().put("segmentId",part.getString("id")).put("translation","译："+part.getString("text")))
            }
            org.json.JSONObject().put("items",items).toString()
        }
        val lines=listOf("This is a book.","We maintain a habit.").mapIndexed {i,text->OcrLine("s$i",text,android.graphics.RectF(0f,0f,100f,20f),if(i==0) 0 else 16,emptyList())}
        val page=OcrPage(lines,1000,1600,"en")
        val options=ReadingOptions("auto","zh","cet6","advanced",true,"translation")
        var displayed=emptyList<PageParagraph>()
        try {
            var rejected=false
            try {translator.translatePage(page,options){displayed=it}} catch(_:IllegalStateException){rejected=true}
            check(rejected && displayed.first().translation!=null && displayed.last().translation==null) {"An omitted paragraph was accepted or previous result was lost"}
            allowed = false
            val blocked = runCatching { translator.translatePage(page, options) { displayed = it } }.exceptionOrNull()
            check(blocked is AiConsentRequired && calls == 1 && displayed.first().translation != null) {
                "Cached paragraphs must remain readable without sending the missing paragraph after revocation"
            }
            allowed = true
            val complete=translator.translatePage(page,options){displayed=it}
            check(complete.size==2 && complete.all{it.translation!=null}) {"Full translation incorrectly filtered basic words"}
            allowed = false
            translator.translatePage(page,options.copy(level="zhongkao")){}
            check(calls==2) {"Changing exam scope re-requested full translation"}
            check(ReadingOptions("auto","zh","cet4","intermediate",true,"translation").resolved("zh").target=="zh") {"Full translation changed the requested target language"}
            var sameLanguageRejected=false
            try {translator.translatePage(page,options.copy(target="en")){displayed=it}} catch(_:IllegalStateException){sameLanguageRejected=true}
            check(sameLanguageRejected && displayed.map{it.source}==lines.map{it.text} && calls==2) {"Same-language error lost original text or requested the service"}
        } finally {translator.close()}
    }
    private fun verifyScrolledPageRequests() {
        val prefs = targetContext.getSharedPreferences("lingfer_scrolled_page_qa", android.content.Context.MODE_PRIVATE)
        val options = ReadingOptions("en", "zh", "cet4", "basic", true, "translation")
        val repeated = listOf(PageParagraph("s0", "A repeated footnote."), PageParagraph("s4", "A repeated footnote."))
        var current = true
        var requests = 0
        val delivered = mutableListOf<List<PageParagraph>>()
        val translator = MultilingualTranslator(prefs, OfflineVocabulary(targetContext), { true }) { _, user ->
            requests++
            val parts = org.json.JSONObject(user).getJSONArray("segments")
            check(parts.length() == 1) { "Repeated paragraphs should only be submitted once" }
            if (requests == 1) current = false  // the reader turned to the next page during the HTTP request
            val item = org.json.JSONObject().put("segmentId", parts.getJSONObject(0).getString("id")).put("translation", "同一条脚注。")
            org.json.JSONObject().put("items", org.json.JSONArray().put(item)).toString()
        }
        try {
            val interrupted = runCatching { translator.translateParagraphs(repeated, "en", options, { current }, delivered::add) }.exceptionOrNull()
            check(interrupted is java.util.concurrent.CancellationException && delivered.flatten().all { it.translation == null })
            current = true
            val translated = translator.translateParagraphs(repeated, "en", options, { current }, delivered::add)
            check(requests == 2 && translated.map { it.id } == listOf("s0", "s4") && translated.all { it.translation == "同一条脚注。" })
            translator.translateParagraphs(listOf(PageParagraph("new-page-id", repeated.first().source)), "en", options) {}
            check(requests == 2) { "Reflowing or revisiting the same paragraph must use the translation cache" }
        } finally { translator.close() }
    }

    private fun verifySelectedParagraph() {
        val box = android.graphics.RectF(20f, 30f, 360f, 55f)
        verifyWrappedArticleParagraphs()
        val texts = listOf("They maintain the road.", "They maintain an orchard.", "The trees are old.", "I like apples.")
        var offset = 0
        val lines = texts.mapIndexed { i, text ->
            val paragraphId = listOf("road", "orchard", "orchard", "apples")[i]
            OcrLine("s$i", text, box, offset, emptyList(), paragraphId).also { offset += text.length + 1 }
        }
        val page = OcrPage(lines, 390, 844)
        val start = lines[1].start + texts[1].indexOf("maintain")
        val hit = WordHit("maintain", "maintain", "维持", emptySet(), texts[1], sourceStart = start, sourceEnd = start + 8)
        val selected = checkNotNull(page.paragraphFor(hit))
        check(selected.source == texts[1] + " " + texts[2]) { "Word card selected the first occurrence, a single line, or a neighbouring paragraph" }
        check(page.paragraphFor(hit.copy(sourceStart = 0, sourceEnd = 8)) == null) { "A stale word offset selected unrelated text" }
        check(page.paragraphs.map { it.id } == listOf("road", "orchard", "apples"))

        val requests = mutableListOf<String>()
        val prefs = targetContext.getSharedPreferences("lingfer_paragraph_qa", android.content.Context.MODE_PRIVATE)
        val options = ReadingOptions("auto", "zh", "cet4", "intermediate", true)
        var allowed = true
        val translation = "他们照料着一座果园。那些树很老了。"
        val translator = MultilingualTranslator(prefs, OfflineVocabulary(targetContext), { allowed }) { _, user ->
            val input = org.json.JSONObject(user).getJSONArray("segments")
            val output = org.json.JSONArray()
            for (i in 0 until input.length()) {
                val item = input.getJSONObject(i)
                val text = item.getString("text")
                requests.add(text)
                output.put(org.json.JSONObject().put("segmentId", item.getString("id")).put("translation", if (text == selected.source) translation else "固定译文"))
            }
            org.json.JSONObject().put("items", output).toString()
        }
        try {
            val result = translator.translateParagraphs(listOf(selected), page.language, options) {}
            check(requests == listOf(selected.source) && result.single().translation == translation)
            allowed = false
            check(translator.translateParagraphs(listOf(selected), page.language, options) {} == result)
            check(runCatching { translator.translateParagraphs(listOf(page.paragraphs.last()), page.language, options) {} }.exceptionOrNull() is AiConsentRequired)
            check(requests.size == 1) { "A cached or unauthorised selection sent a request" }
            allowed = true
            val complete = translator.translatePage(page, options) {}
            check(complete.size == 3 && complete[1] == result.single() && requests == listOf(selected.source, texts.first(), texts.last())) {
                "Page translation re-requested the selected paragraph or lost paragraph boundaries"
            }
            requests.clear()
            val longParagraph = PageParagraph("long", "a".repeat(1399) + "🌷" + " grows here.")
            val longResult = translator.translateParagraphs(listOf(longParagraph), page.language, options) {}
            check(longResult.single().source == longParagraph.source && longResult.single().translation != null)
            check(requests.size == 2 && requests.joinToString("") == longParagraph.source)
            check(requests.none { Character.isLowSurrogate(it.first()) || Character.isHighSurrogate(it.last()) })
            runOnMainSync {
                var opened = false
                val card = NativeReadingPanel(targetContext, hit, "cet4", "学习范围", listOf("cet4" to "四级"), listOf(hit), "[]",
                    onSave = {}, onKnown = {}, onExplain = {}, onClose = {}, onRefresh = {}, onStop = {}, onScope = {}, onWord = {},
                    onParagraph = { opened = true })
                all(card).filterIsInstance<Button>().single { it.text == "翻译这段" }.performClick()
                check(opened)
                var closed = false
                val width = NativeReadingStyle.dp(targetContext, 360f)
                val limit = NativeReadingStyle.dp(targetContext, 520f)
                val paired = NativePageTranslationPanel(targetContext, { closed = true }, {}, {}, title = "段落对照", maxPanelHeight = limit)
                paired.show(result, false, null)
                val labels = all(paired).filterIsInstance<TextView>().map { it.text.toString() }
                check(labels.containsAll(listOf("段落对照", selected.source, translation)) && texts.first() !in labels && texts.last() !in labels)
                val widthSpec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY)
                val heightSpec = View.MeasureSpec.makeMeasureSpec(limit * 2, View.MeasureSpec.AT_MOST)
                paired.measure(widthSpec, heightSpec)
                val height = paired.measuredHeight
                check(height in 1 until limit) { "Short paragraphs should leave the article visible" }
                paired.layout(0, 0, width, height)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val folder = File(targetContext.filesDir, "native-ui-qa").apply { mkdirs() }
                paired.draw(android.graphics.Canvas(bitmap))
                File(folder, "paragraph-paired.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
                paired.show(listOf(PageParagraph("long", selected.source.repeat(40), translation.repeat(40))), false, null)
                paired.measure(widthSpec, heightSpec)
                check(paired.measuredHeight == limit) { "Long paragraphs should scroll within the available height" }
                all(paired).filterIsInstance<Button>().single { it.text == "关闭面板" }.performClick()
                check(closed)
            }
        } finally { translator.close() }
    }

    private fun verifyWrappedArticleParagraphs() {
        // Geometry from the public ReadingFixtureActivity on the 1080px AVD.
        // The OCR originally returned its first body paragraph as three buttons.
        val rows = listOf(
            "A clearer view" to android.graphics.RectF(80f, 226f, 725f, 304f),
            "Researchers maintain that" to android.graphics.RectF(83f, 405f, 840f, 457f),
            "consistent practice is more" to android.graphics.RectF(83f, 523f, 849f, 588f),
            "effective than occasional effort." to android.graphics.RectF(82f, 638f, 990f, 696f),
            "A familiar context can reveal a" to android.graphics.RectF(80f, 770f, 965f, 828f),
            "subtle distinction and make an" to android.graphics.RectF(80f, 891f, 965f, 943f),
            "unfamiliar expression easier to" to android.graphics.RectF(82f, 1006f, 977f, 1074f),
            "remember." to android.graphics.RectF(82f, 1129f, 380f, 1183f),
            "Other column" to android.graphics.RectF(720f, 400f, 972f, 450f),
            "NEXT TITLE" to android.graphics.RectF(995f, 400f, 1079f, 450f),
        )
        val first = "Researchers maintain that consistent practice is more effective than occasional effort."
        val second = "A familiar context can reveal a subtle distinction and make an unfamiliar expression easier to remember."
        for (oneBlock in listOf(false, true)) {
            var offset = 0
            val raw = rows.mapIndexed { i, (text, bounds) ->
                OcrLine("s$i", text, bounds, offset, emptyList(), if (oneBlock) "all" else "b$i").also { offset += text.length + 1 }
            }
            val page = OcrPage(OcrPage.groupParagraphs(raw), 1080, 2400)
            check(page.paragraphs.map { it.source } == listOf(rows.first().first, first, second, "Other column", "NEXT TITLE")) {
                "Visual line wrapping changed the public article's paragraphs: ${page.paragraphs}"
            }
            val start = page.text.indexOf("maintain")
            val hit = WordHit("maintain", "maintain", "保持", emptySet(), rows[1].first, sourceStart = start, sourceEnd = start + 8)
            check(page.paragraphFor(hit)?.source == first)
        }
    }

    private fun verifyAiConsent() {
        val prefs = targetContext.getSharedPreferences("lingfer_transport_consent_qa", android.content.Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
        var calls = 0
        val translator = MultilingualTranslator(prefs, OfflineVocabulary(targetContext), { NativeAiConsent.isAllowed(prefs) }) { _, _ ->
            calls++
            "已授权的语境讲解"
        }
        val options = ReadingOptions("auto", "zh", "cet4", "intermediate", true)
        val line = OcrLine("s0", "We maintain a healthy habit.", android.graphics.RectF(0f, 0f, 300f, 50f), 0, emptyList())
        val page = OcrPage(listOf(line), 300, 500, "en")
        fun assertDenied(operation: () -> Unit) {
            val before = calls
            check(runCatching(operation).exceptionOrNull() is AiConsentRequired && calls == before) {
                "A request proceeded without current consent"
            }
        }
        try {
            val hit = translator.analyze(page, options, emptySet()).first { it.word == "maintain" }
            check(hit.translation.isNotBlank() && hit.context.contains("maintain") && calls == 0)
            assertDenied { translator.explain(hit, options) }
            assertDenied { translator.analyze(page.copy(language = "fr"), options, emptySet()) }
            var original = ""
            assertDenied { translator.translatePage(page, options.copy(mode = "translation")) { original = it.single().source } }
            check(original == line.text)

            prefs.edit().putLong(NativeAiConsent.versionKey, 0).putBoolean(NativeAiConsent.allowedKey, true).apply()
            assertDenied { translator.explain(hit, options) }
            prefs.edit().putString(NativeAiConsent.versionKey, "1").apply()
            assertDenied { translator.explain(hit, options) }
            prefs.edit().putLong(NativeAiConsent.versionKey, 1).apply()
            check(translator.explain(hit, options) == "已授权的语境讲解" && calls == 1)
            prefs.edit().putBoolean(NativeAiConsent.allowedKey, false).apply()
            assertDenied { translator.explain(hit, options) }
            assertDenied { translator.translatePage(page, options.copy(mode = "translation")) {} }
        } finally {
            translator.close()
            prefs.edit().clear().apply()
        }
    }

    private fun verifyMenuNavigation() {
        runOnMainSync {
            var selected="";var stopped=false;var language=""
            var refreshed = false
            var openedPage = false; var changedMode = false; var chosen: PageParagraph? = null
            val paragraph = PageParagraph("first", "An easy paragraph with no selected words.")
            val menu=NativeReadingMenu(targetContext,ReadingOptions("auto","zh","cet6","intermediate",true),false,emptyList(),
                onClose={},onPause={},onRefresh={refreshed=true},onStop={stopped=true},onScope={selected=it},onLanguage={key,value->language="$key=$value"},onWord={},onApp={},
                onMode = { changedMode = true }, onPage = { openedPage = true }, paragraphs = listOf(paragraph), onParagraph = { chosen = it })
            fun buttons()=all(menu).filterIsInstance<Button>().filter{it.visibility==View.VISIBLE}
            fun tap(prefix:String)=buttons().first{it.text.toString().startsWith(prefix)}.performClick()
            check(buttons().none{it.text.toString().startsWith("原文") || it.text.toString().startsWith("学习范围")}) {"Root menu still exposes detailed settings"}
            check(buttons().indexOfFirst { it.text == "选段翻译" } < buttons().indexOfFirst { it.text == "整页对照" })
            tap("整页对照"); tap("选段翻译"); tap(paragraph.source)
            check(openedPage && chosen == paragraph && !changedMode) { "Temporary reading changed mode or required a vocabulary hit" }
            tap("返回")
            tap("本页词卡")
            tap("收起并重新识别")
            check(refreshed) {"An empty word list must offer a way to scan the page again"}
            tap("返回")
            tap("阅读设置")
            check(buttons().any{it.text.toString().startsWith("学习范围")})
            tap("翻译语言")
            check(buttons().any{it.text.toString().startsWith("原文")})
            tap("译文");tap("中文")
            check(language=="targetLanguage=zh") {"Language menu did not forward the selected target"}
            tap("返回")
            tap("返回");tap("学习范围");tap("六级")
            check(selected=="cet6") {"Categorizing the menu broke the existing scope callback"}
            tap("返回");tap("返回");tap("更多")
            check(buttons().any{it.text.toString().startsWith("重新识别")})
            tap("停止阅读");check(stopped)

            val settings = targetContext.getSharedPreferences("lingfer_menu_navigation_qa", android.content.Context.MODE_PRIVATE)
            settings.edit().putString("level", "cet6").putString("generalDifficulty", "intermediate").apply()
            val french = ReadingOptions.load(settings).copy(source = "auto", target = "zh")
            val scope = french.learningScope("fr")
            check(french.learningScope().value == "cet6" && french.learningScope("zh").value == "cet6")
            val frenchMenu = NativeReadingMenu(
                targetContext, french, false, emptyList(),
                onClose = {}, onPause = {}, onRefresh = {}, onStop = {},
                onScope = { scope.save(settings, it) }, onLanguage = { _, _ -> }, onWord = {}, onApp = {},
                detectedLanguage = "fr",
            )
            fun frenchButtons() = all(frenchMenu).filterIsInstance<Button>().filter { it.visibility == View.VISIBLE }
            check(all(frenchMenu).filterIsInstance<TextView>().any { it.text.contains("学习辅助 · 进阶") })
            frenchButtons().first { it.text.toString() == "阅读设置" }.performClick()
            frenchButtons().first { it.text.toString() == "参考难度 · 进阶" }.performClick()
            check(frenchButtons().any { it.text.toString() == "进阶" && it.isSelected })
            check(frenchButtons().none { it.text.toString() == "六级" })
            frenchButtons().first { it.text.toString() == "高阶" }.performClick()
            val saved = ReadingOptions.load(settings)
            check(saved.copy(source = "fr").learningScope().label == "高阶" && saved.level == "cet6") {
                "Changing French reading difficulty must preserve the English exam range"
            }
        }
    }
    private fun verifyTranslationReuse() {
        val prefs=targetContext.getSharedPreferences("lingfer_cache_regression",android.content.Context.MODE_PRIVATE)
        val vocabulary=OfflineVocabulary(targetContext)
        var calls=0
        val translator=MultilingualTranslator(prefs,vocabulary, aiAllowed = { true }) { _,user ->
            calls++
            val segments=org.json.JSONObject(user).getJSONArray("segments")
            val items=org.json.JSONArray()
            for(i in 0 until segments.length()) {
                val segment=segments.getJSONObject(i)
                if(segment.getString("text").contains("坚持")) items.put(org.json.JSONObject().put("segmentId",segment.getString("id")).put("source","坚持").put("word","maintain").put("translation","maintain"))
            }
            org.json.JSONObject().put("items",items).toString()
        }
        fun page(menu:Boolean):OcrPage {
            val texts=if(menu) listOf("目录","他们坚持每天练习并保持这个良好习惯。") else listOf("他们坚持每天练习并保持这个良好习惯。")
            var offset=0
            val lines=texts.mapIndexed {i,text->
                val box=android.graphics.RectF(30f,100f+i*80,900f,150f+i*80)
                val start=offset;offset+=text.length+1
                OcrLine("s$i",text,box,start,text.mapIndexed {j,ch->OcrWord(ch.toString(),android.graphics.RectF(30f+j*24,box.top,54f+j*24,box.bottom),start+j,start+j+1)})
            }
            return OcrPage(lines,1000,1600,"zh")
        }
        try {
            val options=ReadingOptions("auto","zh","cet4","intermediate",true)
            val original=translator.analyze(page(false),options,emptySet())
            check(original.single().word=="maintain" && original.single().targetLanguage=="en") {"Chinese reading did not retain its English exam scope"}
            val menu=page(true)
            val moved=translator.analyze(menu,options,emptySet())
            check(calls==1) {"Temporary menu re-requested unchanged reading text"}
            check(menu.text.substring(moved.single().sourceStart!!,moved.single().sourceEnd!!)=="坚持") {"Cached word wasn't remapped to the current page"}
            check(translator.analyze(menu,options,setOf("maintain")).isEmpty()) {"Known word was not excluded"}
            check(translator.analyze(menu,options,emptySet()).size==1 && calls==1) {"Undoing known-word exclusion lost cached vocabulary"}
        } finally {translator.close()}
    }
    private fun runCase(index:Int,width:Int,height:Int,scale:Float) {
        val config=Configuration(targetContext.resources.configuration).apply {screenWidthDp=width;screenHeightDp=height;fontScale=scale}
        val context=targetContext.createConfigurationContext(config)
        val windows=targetContext.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
        val fixture=WordHit("maintain","maintain","vt. 维持；坚持；主张",setOf("cet4"),"Researchers maintain that consistent practice is more effective than occasional effort.")
        val choices=listOf("zhongkao" to "中考","gaokao" to "高考","cet4" to "四级","cet6" to "六级","kaoyan" to "考研","ielts" to "雅思","toefl" to "托福")
        lateinit var panel:NativeReadingPanel
        var requests=0;var saves=0;var chosen="";var closed=false;var stopped=false
        fun remove(){if(panel.isAttachedToWindow) windows.removeViewImmediate(panel)}
        runOnMainSync {
            panel=NativeReadingPanel(context,fixture,"cet4","学习范围",choices,listOf(fixture),"[]",
                onSave={saves++},onKnown={},onExplain={requests++;panel.showLoading()},
                onClose={closed=true;remove()},onRefresh={},onStop={stopped=true;remove()},
                onScope={chosen=it},onWord={})
            val panelWidth=if(width>=680) minOf(440,(width*.48f).toInt()-12) else minOf(440,width-24)
            val params=GlassAnnotations.overlayParams(NativeReadingStyle.dp(context,panelWidth.toFloat()),NativeReadingStyle.dp(context,height*.72f)).apply {gravity=Gravity.CENTER}
            windows.addView(panel,params);panel.showLoading()
        }
        try {
            waitForIdleSync();capture("case-$index-loading")
            var views=all(panel)
            check(views.filterIsInstance<TextView>().any{it.text.toString()==fixture.context}) {"Original sentence cleared while loading"}
            check(views.filterIsInstance<TextView>().any{it.text.toString()==fixture.translation}) {"Offline meaning cleared while loading"}
            check(views.filterIsInstance<Button>().first{it.text.toString()=="正在讲解"}.isEnabled.not()) {"Loading retry was not disabled"}
            runOnMainSync { panel.showOffline(null) }
            check(views.filterIsInstance<TextView>().any { it.text.toString() == NativeAiConsent.prompt })
            check(views.filterIsInstance<TextView>().any { it.text.toString() == fixture.translation })
            check(views.filterIsInstance<TextView>().any { it.text.toString() == fixture.context })
            check(views.filterIsInstance<Button>().none { it.text.contains("讲解") && it.visibility == View.VISIBLE })
            runOnMainSync {panel.showAnswer("详解暂未响应，原词译义和收藏仍可使用。")}
            runOnMainSync {
                val message=all(panel).filterIsInstance<TextView>().first{it.text.toString()=="详解暂未响应，原词译义和收藏仍可使用。"}
                message.requestRectangleOnScreen(Rect(0,0,message.width,minOf(message.height,all(panel).filterIsInstance<ScrollView>().first().height)),true)
            }
            waitForIdleSync();capture("case-$index-error")
            views=all(panel)
            check(views.filterIsInstance<TextView>().any{it.text.toString()==fixture.context}) {"Original sentence cleared on error"}
            check(views.filterIsInstance<TextView>().any{it.text.toString()==fixture.translation}) {"Offline meaning cleared on error"}
            val retry=views.filterIsInstance<Button>().first{it.text.toString()=="重新请求讲解"}
            check(retry.isEnabled)
            runOnMainSync {retry.performClick()}
            check(requests==1) {"Retry did not call the supplied callback"}
            runOnMainSync {panel.showAnswer("本句 maintain 表示坚持认为或主张，后接 that 从句。");all(panel).filterIsInstance<ImageButton>().first().performClick()}
            check(saves==1)
            check(all(panel).filterIsInstance<ImageButton>().first().contentDescription.toString().startsWith("已收藏"))
            capture("case-$index-retry-saved")
            val scope=all(panel).filterIsInstance<Button>().first{it.text.toString().contains("四级")}
            runOnMainSync {scope.performClick()}
            val scopeViews=all(panel).filterIsInstance<Button>()
            check(choices.all{(_,name)->scopeViews.any{it.text.toString().startsWith(name)}}) {"Scope list missing an exam range"}
            runOnMainSync {scopeViews.first{it.text.toString()=="六级"}.performClick()}
            check(chosen=="cet6")
            runOnMainSync {all(panel).filterIsInstance<Button>().first{it.text.toString()==if(index==1) "停止阅读" else "关闭"}.performClick()}
            check(if(index==1) stopped else closed)
            check(panel.parent==null)
        } finally {runOnMainSync {remove()}}
    }
    private fun all(view:View):List<View> = listOf(view)+if(view is ViewGroup) (0 until view.childCount).flatMap{all(view.getChildAt(it))} else emptyList()
    private fun capture(name:String) {
        Thread.sleep(250)
        val image=uiAutomation.takeScreenshot() ?: error("No screenshot available")
        val folder=File(targetContext.filesDir,"native-ui-qa").apply {mkdirs()}
        File(folder,"$name.png").outputStream().use{image.compress(Bitmap.CompressFormat.PNG,100,it)}
        image.recycle()
    }
}
