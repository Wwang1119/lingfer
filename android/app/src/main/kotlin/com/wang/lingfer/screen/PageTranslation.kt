package com.wang.lingfer.screen

import android.content.Context
import android.view.Gravity
import android.widget.*
import org.json.JSONObject

data class PageParagraph(val id:String,val source:String,val translation:String?=null) {
    fun nativeMap():Map<String,Any?> = mapOf("id" to id,"source" to source,"translation" to translation)
    fun json()=JSONObject().put("id",id).put("source",source).put("translation",translation ?: JSONObject.NULL)
}

internal class NativePageTranslationPanel(context:Context,private val onClose:()->Unit,
    private val onRetry:()->Unit,private val onStop:()->Unit,private val onSettings:()->Unit={}):LinearLayout(context) {
    private val content=LinearLayout(context).apply {orientation=VERTICAL}
    private fun dp(v:Int)=NativeReadingStyle.dp(context,v.toFloat())
    init {
        orientation=VERTICAL;background=NativeReadingStyle.glass(context);clipToOutline=true
        val heading=LinearLayout(context).apply {gravity=Gravity.CENTER_VERTICAL}
        heading.addView(TextView(context).apply {text="整页对照";textSize=23f;includeFontPadding=false;typeface=NativeReadingStyle.heading(context);setTextColor(NativeReadingStyle.ink);setPadding(dp(16),dp(12),0,dp(12))},LayoutParams(0,-2,1f))
        heading.addView(action("关闭面板",onClose));addView(heading)
        addView(ScrollView(context).apply {addView(content)},LayoutParams(-1,0,1f))
        addView(action("停止阅读",onStop))
    }
    fun show(parts:List<PageParagraph>,loading:Boolean,error:String?) {
        content.removeAllViews();content.setPadding(dp(16),dp(8),dp(16),dp(24))
        content.addView(label("已翻译 ${parts.count{it.translation!=null}} / ${parts.size} 段 · 不筛难度，不排除熟词",13f,true))
        if(loading) content.addView(ProgressBar(context))
        if(error!=null) {
            content.addView(label(error,15f,true))
            if(error.contains("相同语言")) content.addView(action("更改语言或阅读方式",onSettings))
            else content.addView(action("重试未完成段落",onRetry))
        }
        if(parts.isEmpty() && !loading && error==null) content.addView(label("当前页没有文字，请关闭面板后停稳页面。",16f,true))
        parts.forEach {p->
            content.addView(label(p.source,16f,false))
            content.addView(label(p.translation ?: "尚未翻译",17f,p.translation==null).apply {if(p.translation!=null) setTextColor(NativeReadingStyle.accent)})
            content.addView(android.view.View(context).apply {setBackgroundColor(NativeReadingStyle.line)},LayoutParams(-1,dp(1)).apply {topMargin=dp(8);bottomMargin=dp(8)})
        }
        content.addView(label("关闭面板后继续自动识别页面变化。译文不会加入生词本。",13f,true))
    }
    private fun label(value:String,size:Float,muted:Boolean)=TextView(context).apply {
        text=value;textSize=size;setTextColor(if(muted) NativeReadingStyle.muted else NativeReadingStyle.ink)
        setLineSpacing(dp(5).toFloat(),1f);setPadding(0,dp(8),0,dp(8));setTextIsSelectable(true)
    }
    private fun action(value:String,callback:()->Unit)=Button(context).apply {
        text=value;isAllCaps=false;includeFontPadding=false;gravity=Gravity.CENTER;minimumHeight=dp(48);setTextColor(NativeReadingStyle.accent)
        background=NativeReadingStyle.control(context);setOnClickListener{callback()}
    }
}
