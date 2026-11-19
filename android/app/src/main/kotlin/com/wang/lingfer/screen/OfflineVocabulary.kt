package com.wang.lingfer.screen

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class WordHit(val word: String, val surface: String, val translation: String, val tags: Set<String>, val context: String, val sourceLanguage: String = "en", val targetLanguage: String = "zh", val annotation: String? = null, val sourceStart: Int? = null, val sourceEnd: Int? = null) {
    val key get() = if (sourceLanguage == "en" || targetLanguage == "en") word else "$sourceLanguage:$targetLanguage:$word"
    fun nativeMap(): Map<String, Any?> = mapOf("word" to word, "surface" to surface, "translation" to translation, "tags" to tags.toList(), "context" to context,
        "sourceLanguage" to sourceLanguage, "targetLanguage" to targetLanguage, "annotation" to annotation, "sourceStart" to sourceStart, "sourceEnd" to sourceEnd, "studyKey" to key)
    fun json() = JSONObject().put("word", word).put("surface", surface).put("translation", translation)
        .put("tags", JSONArray(tags.toList())).put("context", context)
        .put("sourceLanguage", sourceLanguage).put("targetLanguage", targetLanguage).put("annotation", annotation)
        .put("sourceStart", sourceStart).put("sourceEnd", sourceEnd).put("studyKey", key)
}

class OfflineVocabulary(context: Context) {
    private val english = Regex("[A-Za-z]+")

    private fun boundary(text: String, at: Int): Boolean {
        if (text[at] in ".!?;。！？；") return true
        if (text[at] != '\n') return false
        if (at == 0 || at + 1 == text.length || text[at - 1] == '\n' || text[at + 1] == '\n') return true
        val previous = text.substring(text.lastIndexOf('\n', at - 1) + 1, at).trim()
        val nextEnd = text.indexOf('\n', at + 1).let { if (it < 0) text.length else it }
        val next = text.substring(at + 1, nextEnd).trim()
        return previous.length < 35 || english.findAll(previous).take(5).count() < 5 || english.findAll(next).take(2).count() < 2 || next == next.uppercase()
    }
    private val entries = context.assets.open("flutter_assets/assets/data/vocabulary.json")
        .bufferedReader().use { JSONObject(it.readText()).getJSONObject("entries") }

    fun lemma(surface: String): String? {
        val word = surface.lowercase().replace('’', '\'')
        if (entries.has(word)) return word
        val candidates = mutableListOf<String>()
        if (word.endsWith("'s")) candidates.add(word.dropLast(2))
        if (word.endsWith("ies") && word.length > 4) candidates.add(word.dropLast(3) + "y")
        if (word.endsWith("es")) candidates.add(word.dropLast(2))
        if (word.endsWith("s") && !word.endsWith("ss")) candidates.add(word.dropLast(1))
        for (suffix in listOf("ing", "ed")) {
            if (!word.endsWith(suffix) || word.length < suffix.length + 3) continue
            val stem = word.dropLast(suffix.length)
            candidates.addAll(listOf(stem, stem + "e"))
            if (stem.length > 2 && stem.last() == stem[stem.length - 2]) candidates.add(stem.dropLast(1))
            if (suffix == "ed" && stem.endsWith("i")) candidates.add(stem.dropLast(1) + "y")
        }
        return candidates.firstOrNull { entries.has(it) }
    }

    fun lookup(surface: String, level: String? = null): WordHit? {
        val word = lemma(surface) ?: return null
        val entry = entries.getJSONObject(word)
        val list = entry.getJSONArray("tags")
        val tags = (0 until list.length()).map { list.getString(it) }.toSet()
        if (level != null && !matches(tags, level)) return null
        return WordHit(word, surface, entry.getString("translation"), tags, "")
    }

    private fun matches(tags: Set<String>, level: String): Boolean {
        val tag = mapOf("zhongkao" to "zk", "gaokao" to "gk", "cet4" to "cet4", "cet6" to "cet6", "kaoyan" to "ky", "ielts" to "ielts", "toefl" to "toefl")[level] ?: "cet4"
        return tag in tags && (tag == "zk" || "zk" !in tags) && (tag in listOf("zk", "gk") || "gk" !in tags)
    }

    fun englishCandidates(text: String, level: String): List<String> {
        val candidates = mutableListOf<Pair<String, Int>>()
        for (word in entries.keys()) {
            val entry = lookup(word, level) ?: continue
            val score = Regex("[\\p{IsHan}]{2,10}").findAll(entry.translation).filter { text.contains(it.value) }.maxOfOrNull { it.value.length } ?: continue
            candidates.add(word to score)
        }
        return candidates.sortedByDescending { it.second }.take(120).map { it.first }
    }

    fun extract(text: String, level: String, known: Set<String>): List<WordHit> {
        val tag = mapOf("zhongkao" to "zk", "gaokao" to "gk", "cet4" to "cet4", "cet6" to "cet6", "kaoyan" to "ky", "ielts" to "ielts", "toefl" to "toefl")[level] ?: "cet4"
        val seen = mutableSetOf<String>()
        val hits = mutableListOf<WordHit>()
        for (match in Regex("[A-Za-z]+(?:['’-][A-Za-z]+)*").findAll(text)) {
            val word = lemma(match.value) ?: continue
            if (word in known || word in seen) continue
            val raw = entries.getJSONObject(word)
            val rawTags = raw.getJSONArray("tags")
            val tags = (0 until rawTags.length()).map { rawTags.getString(it) }.toSet()
            if (tag !in tags) continue
            if (tag != "zk" && "zk" in tags) continue
            if (tag !in listOf("zk", "gk") && "gk" in tags) continue
            seen.add(word)
            var left = match.range.first
            var right = match.range.last + 1
            while (left > 0 && match.range.first - left < 180 && !boundary(text, left - 1)) left--
            while (right < text.length && right - match.range.last < 220 && !boundary(text, right)) right++
            if (right < text.length && boundary(text, right)) right++
            hits.add(WordHit(word, match.value, raw.getString("translation"), tags, text.substring(left, right).trim().replace(Regex("\\s*\\n\\s*"), " "), sourceStart = match.range.first, sourceEnd = match.range.last + 1))
            if (hits.size >= 24) break
        }
        return hits
    }
}
