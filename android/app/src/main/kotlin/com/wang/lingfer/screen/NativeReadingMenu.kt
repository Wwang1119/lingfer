package com.wang.lingfer.screen

import android.content.Context
import android.view.Gravity
import android.widget.*

/** Small reading controls; all changes go through the existing session. */
internal class NativeReadingMenu(context:Context,options:ReadingOptions,paused:Boolean,words:List<WordHit>,
    onClose:()->Unit,onPause:()->Unit,onRefresh:()->Unit,onStop:()->Unit,
    onScope:(String)->Unit,onLanguage:(String,String)->Unit,onWord:(WordHit)->Unit,onApp:()->Unit,onMode:(String)->Unit={},onPage:()->Unit={},
    error:String?=null,detectedLanguage:String?=null):LinearLayout(context) {
    private fun dp(value:Int)=NativeReadingStyle.dp(context,value.toFloat())
    init {
        orientation=VERTICAL;background=NativeReadingStyle.glass(context);clipToOutline=true;setPadding(dp(8),dp(8),dp(8),dp(8))
        val heading=LinearLayout(context).apply {gravity=Gravity.CENTER_VERTICAL;setPadding(dp(16),dp(8),dp(6),0)}
        val back=action("返回"){}.apply {visibility=GONE;layoutParams=LayoutParams(-2,dp(48));setPadding(dp(8),0,dp(10),0)}
        val title=TextView(context).apply {text="阅读菜单";textSize=22f;includeFontPadding=false;typeface=NativeReadingStyle.heading(context);setTextColor(NativeReadingStyle.ink)}
        heading.addView(back);heading.addView(title,LayoutParams(0,-2,1f))
        heading.addView(action("关闭",onClose).apply {layoutParams=LayoutParams(-2,dp(48));setPadding(dp(10),0,dp(10),0)});addView(heading)
        val content=LinearLayout(context).apply {orientation=VERTICAL;setPadding(dp(12),0,dp(12),dp(12))}
        addView(ScrollView(context).apply {addView(content)},LayoutParams(-1,0,1f))
        val scopes=linkedMapOf("zhongkao" to "中考","gaokao" to "高考","cet4" to "四级","cet6" to "六级","kaoyan" to "考研","ielts" to "雅思","toefl" to "托福")
        fun screen(name:String,parent:(()->Unit)?=null) {
            title.text=name;content.removeAllViews();back.visibility=if(parent==null) GONE else VISIBLE
            back.setOnClickListener {parent?.invoke()}
        }
        fun note(value:String) {content.addView(TextView(context).apply {text=value;textSize=13f;setTextColor(NativeReadingStyle.muted);setPadding(dp(12),dp(12),dp(12),dp(8))})}
        lateinit var root:()->Unit
        lateinit var settings:()->Unit
        lateinit var languages:()->Unit
        fun languageChoice(key:String,label:String,selected:String,allowAuto:Boolean) {
            screen(label,languages)
            ReadingOptions.languages.filter {allowAuto || it.key!="auto"}.forEach {(code,name)->
                content.addView(action(name+(if(code==selected) " ✓" else "")){onLanguage(key,code)})
            }
        }
        languages={
            screen("翻译语言",settings)
            content.addView(action("原文 · ${ReadingOptions.languages[options.source]}  ⌄"){languageChoice("sourceLanguage","原文语言",options.source,true)})
            content.addView(action("译文 · ${ReadingOptions.languages[options.target]}  ⌄"){languageChoice("targetLanguage","译文语言",options.target,false)})
        }
        settings={
            screen("阅读设置",root)
            content.addView(action("阅读方式 · ${if(options.mode=="translation") "整页对照" else "学习辅助"}  ⌄") {
                screen("阅读方式",settings)
                content.addView(action("学习辅助 · 按难度筛词"){onMode("learning")})
                content.addView(action("整页对照 · 完整译文，需联网"){onMode("translation")})
            })
            if(options.mode=="learning") content.addView(action("学习范围 · ${scopes[options.level]}  ⌄") {
                screen("学习范围",settings)
                scopes.forEach {(key,value)->content.addView(action(value+(if(key==options.level) " ✓" else "")){onScope(key)})}
            })
            content.addView(action("翻译语言 · ${ReadingOptions.languages[options.source]} → ${ReadingOptions.languages[options.target]}  ⌄",languages))
        }
        root={
            screen("阅读菜单")
            note("${if(options.mode=="translation") "整页对照" else "学习辅助 · ${scopes[options.level]}"} · ${ReadingOptions.languages[options.source]} → ${ReadingOptions.languages[options.target]}")
            if(error!=null) {
                note(error)
                val source=if(options.source=="auto") detectedLanguage else options.source
                if(options.mode=="translation" && source==options.target) {
                    val target=if(source=="zh") "en" else "zh"
                    content.addView(action("改译成${ReadingOptions.languages[target]}"){onLanguage("targetLanguage",target)})
                } else content.addView(action("重试当前页",onRefresh))
            }
            if(options.mode=="translation") content.addView(action("本页译文",onPage))
            else content.addView(action("本页词卡 · ${words.size} 个") {
                screen("本页词卡",root)
                if(words.isEmpty()) note("当前页没有待学词，可在阅读设置调整范围。")
                words.forEach {word->content.addView(action("${word.surface} · ${word.annotation ?: MultilingualTranslator.compact(word.translation)}"){onWord(word)})}
            })
            content.addView(action(if(paused) "继续识别" else "暂停识别",onPause))
            content.addView(action("阅读设置  ›",settings))
            content.addView(action("更多  ›") {
                screen("更多",root)
                content.addView(action("重新识别当前页",onRefresh))
                content.addView(action("回到语渡 · 生词本与设置",onApp))
            })
        }
        root()
        addView(action("停止阅读",onStop))
    }
    private fun action(title:String,callback:()->Unit)=Button(context).apply {
        text=title;textSize=15f;isAllCaps=false;includeFontPadding=false;gravity=Gravity.START or Gravity.CENTER_VERTICAL
        setTextColor(NativeReadingStyle.ink);background=NativeReadingStyle.control(context);stateListAnimator=null
        minimumHeight=dp(52);minHeight=dp(52);minimumWidth=dp(48);minWidth=dp(48)
        setPadding(dp(14),dp(10),dp(14),dp(10))
        layoutParams=LayoutParams(-1,-2).apply {bottomMargin=dp(6)}
        val symbol=when {title.startsWith("本页")->"book";title.contains("暂停")||title.contains("继续")->"pause";title.startsWith("阅读设置")->"settings";title.startsWith("更多")->"more";title.startsWith("停止")->"stop";title.startsWith("重新")->"refresh";else->null}
        if(symbol!=null) {
            val icon=NativeReadingIcon(symbol,NativeReadingStyle.accent).apply {setBounds(0,0,dp(20),dp(20))}
            setCompoundDrawables(icon,null,null,null);compoundDrawablePadding=dp(12)
        }
        setOnClickListener {callback()}
    }
}
