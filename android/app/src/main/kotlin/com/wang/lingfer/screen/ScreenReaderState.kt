package com.wang.lingfer.screen

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.EventChannel

object ScreenReaderState {
    @Volatile var running = false
    @Volatile var paused = false
    @Volatile var hostActive = true
    var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(value: Map<String, Any?>) { main.post { sink?.success(value) } }

    fun status(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences("lingfer_screen", Context.MODE_PRIVATE)
        return mutableMapOf<String,Any?>(
            "supported" to true,
            "running" to running,
            "paused" to paused,
            "level" to prefs.getString("level", "cet4"),
            "sourceLanguage" to prefs.getString("sourceLanguage", "auto"),
            "targetLanguage" to prefs.getString("targetLanguage", "zh"),
            "readingMode" to prefs.getString("readingMode","learning"),
            "generalDifficulty" to prefs.getString("generalDifficulty", "intermediate"),
            "automatic" to prefs.getBoolean("automatic", true),
            "overlayAllowed" to Settings.canDrawOverlays(context),
            "known" to (prefs.getStringSet("known", emptySet()) ?: emptySet()).toList(),
            "saved" to prefs.getString("saved", "[]"),
            "lastText" to prefs.getString("lastText", ""),
            "lastHits" to prefs.getString("lastHits", "[]"),
            "lastOptionsSignature" to prefs.getString("lastOptionsSignature", ""),
            "detectedLanguage" to prefs.getString("lastDetectedLanguage", "en")
        ).apply {
            if(prefs.getString("readingMode","learning")=="translation" &&
                prefs.getString("lastTranslatedText",null)==prefs.getString("lastText","") &&
                prefs.getString("lastTranslationTarget",null)==prefs.getString("targetLanguage","zh") &&
                (prefs.getString("sourceLanguage","auto")=="auto" || prefs.getString("sourceLanguage","auto")==prefs.getString("lastTranslationSource",null))) {
                try {
                    val array=org.json.JSONArray(prefs.getString("lastTranslationSegments","[]"))
                    val parts=(0 until array.length()).map {i->val p=array.getJSONObject(i);mapOf("id" to p.optString("id"),"source" to p.optString("source"),"translation" to (p.opt("translation") as? String))}
                    if(parts.isNotEmpty()) {put("translationSegments",parts);if(parts.any{it["translation"]==null}) put("translationError","尚有段落未完成，请重试。")}
                } catch(_:Exception){}
            }
        }
    }
}
