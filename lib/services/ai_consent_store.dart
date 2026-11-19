import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiConsentState {
  const AiConsentState({this.version = 0, this.accepted = false});
  final int version;
  final bool accepted;
  bool get decided => version == AiConsentStore.currentVersion;
  bool get allowed => decided && accepted;
}

/// This permission is separate from the system screen-sharing authorization.
/// On iOS the App Group is authoritative, so a choice made in the extension is
/// checked again before each Flutter request rather than trusting an old cache.
abstract final class AiConsentStore {
  static const currentVersion = 1;
  static const versionKey = 'companion_ai_consent_version_v1';
  static const allowedKey = 'companion_ai_consent_allowed_v1';
  static const policyUrl = 'https://docs.qq.com/doc/DRnZUeGhsY2JraXJD';
  static const contactEmail = 'wyxwyx05@163.com';
  static const disclosure =
      '联网翻译、词汇筛选、文字整理和语境讲解会把对应 OCR 文字、原文选段、词语及上下文，'
      '通过腾讯云中转发送给 DeepSeek 处理。书内阅读、整页对照及随屏阅读启用这些功能后，'
      '内容变化时可能自动发送文字。屏幕图片和照片在本机识别，不随这些 AI 请求上传。\n\n'
      '文字可能包含个人信息，语渡不保证自动脱敏。腾讯云和 DeepSeek 的实际云端留存规则尚未核实，'
      '不承诺请求后立即删除或不留日志。\n\n'
      '你可以选择仅本机阅读，继续使用本地资料、已保存结果和可用的离线词义；'
      '允许或关闭联网 AI 均不影响你的收藏和阅读进度。可在设置中更改选择。';
  static const _channel = MethodChannel('lingfer/share_reader');

  static Future<AiConsentState> read() async {
    if (Platform.isIOS) {
      try {
        final values = await _channel.invokeMapMethod<String, dynamic>(
          'getAIConsent',
        );
        if (values == null) return const AiConsentState();
        final state = AiConsentState(
          version: (values['version'] as num?)?.toInt() ?? 0,
          accepted: values['allowed'] == true,
        );
        await _mirror(state);
        return state;
      } catch (_) {
        // Missing/unavailable native coordination must not authorize a request.
        return const AiConsentState();
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return AiConsentState(
        version: prefs.getInt(versionKey) ?? 0,
        accepted: prefs.getBool(allowedKey) ?? false,
      );
    } catch (_) {
      return const AiConsentState();
    }
  }

  static Future<bool> isAllowed() async => (await read()).allowed;

  static Future<AiConsentState> setAllowed(bool allowed) async {
    if (Platform.isIOS) {
      try {
        final values = await _channel.invokeMapMethod<String, dynamic>(
          'setAIConsent',
          {'version': currentVersion, 'allowed': allowed},
        );
        if (values == null) return const AiConsentState();
        final state = AiConsentState(
          version: (values['version'] as num?)?.toInt() ?? 0,
          accepted: values['allowed'] == true,
        );
        await _mirror(state);
        return state;
      } catch (_) {
        return const AiConsentState();
      }
    }
    final state = AiConsentState(version: currentVersion, accepted: allowed);
    try {
      await _mirror(state);
      return state;
    } catch (_) {
      return const AiConsentState();
    }
  }

  static Future<void> _mirror(AiConsentState state) async {
    final prefs = await SharedPreferences.getInstance();
    if (state.version <= 0) {
      await prefs.remove(versionKey);
      await prefs.remove(allowedKey);
      return;
    }
    // A native reader may inspect the preferences between these two writes.
    // Publish the choice first so a stale approval cannot become current
    // while the user's new refusal is being saved.
    if (!await prefs.setBool(allowedKey, state.accepted) ||
        !await prefs.setInt(versionKey, state.version)) {
      throw StateError('Could not persist the AI consent choice');
    }
  }
}
