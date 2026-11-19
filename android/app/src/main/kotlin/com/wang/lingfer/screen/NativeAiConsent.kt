package com.wang.lingfer.screen

import android.content.Context
import android.content.SharedPreferences

/** Reads the same legacy SharedPreferences record as Flutter's AiConsentStore. */
internal object NativeAiConsent {
    const val versionKey = "flutter.companion_ai_consent_version_v1"
    const val allowedKey = "flutter.companion_ai_consent_allowed_v1"
    const val prompt = "联网 AI 未开启。可在语渡的设置中允许联网 AI。"

    fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun isAllowed(preferences: SharedPreferences): Boolean {
        val record = try {
            preferences.all
        } catch (_: RuntimeException) {
            return false
        }
        return record[versionKey] == 1L && record[allowedKey] == true
    }
}

internal class AiConsentRequired : IllegalStateException(NativeAiConsent.prompt)
