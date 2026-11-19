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
            verifyAnnotationGeometry()
            verifyTranslationReuse()
            verifyFullPageTranslation()
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
    private fun verifyAnnotationGeometry() {
        val first=OcrWord("坚",android.graphics.RectF(40f,100f,62f,130f),0,1)
        val second=OcrWord("持",android.graphics.RectF(64f,94f,86f,128f),1,2)
        val wrapped=OcrWord("阅",android.graphics.RectF(40f,150f,62f,180f),3,4)
        val page=OcrPage(listOf(OcrLine("s0","坚持",android.graphics.RectF(40f,94f,86f,130f),0,listOf(first,second)),OcrLine("s1","阅",wrapped.box,3,listOf(wrapped))),300,500,"zh")
        val hit=WordHit("read","坚持\n阅","read",emptySet(),"坚持阅读",sourceStart=0,sourceEnd=4)
        val boxes=AnnotationGeometry.boxes(page,hit)
        check(boxes.size==3 && boxes[0]==first.box && boxes[1]==second.box && boxes[2]==wrapped.box) {"Glyph or line rectangles were merged into an inaccurate block"}
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
    private fun verifyFullPageTranslation() {
        val prefs=targetContext.getSharedPreferences("lingfer_page_qa",android.content.Context.MODE_PRIVATE)
        var calls=0
        val translator=MultilingualTranslator(prefs,OfflineVocabulary(targetContext)) {system,user->
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
            val complete=translator.translatePage(page,options){displayed=it}
            check(complete.size==2 && complete.all{it.translation!=null}) {"Full translation incorrectly filtered basic words"}
            translator.translatePage(page,options.copy(level="zhongkao")){}
            check(calls==2) {"Changing exam scope re-requested full translation"}
            check(ReadingOptions("auto","zh","cet4","intermediate",true,"translation").resolved("zh").target=="zh") {"Full translation changed the requested target language"}
            var sameLanguageRejected=false
            try {translator.translatePage(page,options.copy(target="en")){displayed=it}} catch(_:IllegalStateException){sameLanguageRejected=true}
            check(sameLanguageRejected && displayed.map{it.source}==lines.map{it.text} && calls==2) {"Same-language error lost original text or requested the service"}
        } finally {translator.close()}
    }
    private fun verifyMenuNavigation() {
        runOnMainSync {
            var selected="";var stopped=false;var language=""
            val menu=NativeReadingMenu(targetContext,ReadingOptions("auto","zh","cet6","intermediate",true),false,emptyList(),
                onClose={},onPause={},onRefresh={},onStop={stopped=true},onScope={selected=it},onLanguage={key,value->language="$key=$value"},onWord={},onApp={})
            fun buttons()=all(menu).filterIsInstance<Button>().filter{it.visibility==View.VISIBLE}
            fun tap(prefix:String)=buttons().first{it.text.toString().startsWith(prefix)}.performClick()
            check(buttons().none{it.text.toString().startsWith("原文") || it.text.toString().startsWith("学习范围")}) {"Root menu still exposes detailed settings"}
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
        }
    }
    private fun verifyTranslationReuse() {
        val prefs=targetContext.getSharedPreferences("lingfer_cache_regression",android.content.Context.MODE_PRIVATE)
        val vocabulary=OfflineVocabulary(targetContext)
        var calls=0
        val translator=MultilingualTranslator(prefs,vocabulary) { _,user ->
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
