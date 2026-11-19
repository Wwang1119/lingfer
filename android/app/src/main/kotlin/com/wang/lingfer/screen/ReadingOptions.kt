package com.wang.lingfer.screen

import android.content.SharedPreferences

internal class LearningScope(
    val title: String,
    val value: String,
    val choices: List<Pair<String, String>>,
    private val preferenceKey: String,
) {
    val label get() = choices.firstOrNull { it.first == value }?.second ?: value

    fun save(prefs: SharedPreferences, selection: String) {
        prefs.edit().putString(preferenceKey, selection).apply()
    }
}

data class ReadingOptions(val source: String, val target: String, val level: String,
    val difficulty: String, val automatic: Boolean, val mode:String="learning") {
    val signature get() = "$source|$target|$level|$difficulty"+(if(mode=="translation") "|translation" else "")
    // Chinese reading can teach English too: never silently replace a chosen
    // exam scope with the unrelated generic difficulty selector.
    fun resolved(detected:String):ReadingOptions {
        val actual=if(source=="auto") detected else source
        return if(mode=="learning" && actual=="zh" && target=="zh") copy(target="en") else this
    }

    internal fun learningScope(detected: String? = null): LearningScope {
        val actualSource = if (source == "auto") detected ?: "en" else source
        return if (actualSource == "en" || resolved(actualSource).target == "en") {
            LearningScope("学习范围", level, examLevels, "level")
        } else {
            LearningScope("参考难度", difficulty, generalDifficulties, "generalDifficulty")
        }
    }

    companion object {
        private val examLevels = listOf(
            "zhongkao" to "中考", "gaokao" to "高考", "cet4" to "四级", "cet6" to "六级",
            "kaoyan" to "考研", "ielts" to "雅思", "toefl" to "托福",
        )
        private val generalDifficulties = listOf("basic" to "基础", "intermediate" to "进阶", "advanced" to "高阶")
        val languages = linkedMapOf("auto" to "自动识别", "zh" to "中文", "en" to "英语", "ja" to "日语", "ko" to "韩语", "fr" to "法语", "de" to "德语", "es" to "西班牙语", "pt" to "葡萄牙语", "it" to "意大利语", "hi" to "印地语")
        fun load(prefs: SharedPreferences) = ReadingOptions(prefs.getString("sourceLanguage", "auto") ?: "auto",
            prefs.getString("targetLanguage", "zh") ?: "zh", prefs.getString("level", "cet4") ?: "cet4",
            prefs.getString("generalDifficulty", "intermediate") ?: "intermediate", prefs.getBoolean("automatic", true),prefs.getString("readingMode","learning") ?: "learning")
    }
}
