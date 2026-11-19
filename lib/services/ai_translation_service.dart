import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/translation_mode.dart';
import '../models/vocabulary_level.dart';
import 'ai_consent_store.dart';

class AiTranslationService {
  AiTranslationService({
    required String proxyUrl,
    required String appSecret,
    http.Client Function()? clientFactory,
  }) : _proxyUri = Uri.tryParse(proxyUrl),
       _appSecret = appSecret,
       _clientFactory = clientFactory ?? (() => http.Client());

  final Uri? _proxyUri;
  final String _appSecret;
  final http.Client Function() _clientFactory;

  static const String _garbleImmunityPrompt =
      '原文可能包含由 PDF 公式或特殊符号产生的识别错误。'
      '不确定的符号请保留原样并注明无法确认，不得根据上下文猜测补全。'
      '仅翻译可以可靠识别的内容。';

  /// Sanitizes noisy PDF selections so they won't break JSON encoding or model
  /// parsing. We intentionally keep common punctuation and CJK/Latin letters,
  /// but strip control chars, zero-width chars, surrogates and private-use
  /// glyphs (which often come from PDF \"art fonts\").
  static String _sanitizeForAi(String raw, {int maxLen = 1800}) {
    if (raw.isEmpty) return '';

    final input = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final sb = StringBuffer();

    for (final rune in input.runes) {
      // Keep newlines/tabs for paragraph structure.
      if (rune == 0x0A || rune == 0x09) {
        sb.writeCharCode(rune);
        continue;
      }

      // Control chars.
      if (rune < 0x20 || rune == 0x7F) continue;

      // Soft hyphen.
      if (rune == 0x00AD) continue;

      // NBSP -> normal space.
      if (rune == 0x00A0) {
        sb.write(' ');
        continue;
      }

      // Zero-widths / BOM.
      if (rune == 0xFEFF || (rune >= 0x200B && rune <= 0x200D)) continue;

      // UTF-16 surrogate code points (invalid Unicode scalar values).
      if (rune >= 0xD800 && rune <= 0xDFFF) continue;

      // Private use areas (often \"art font\" glyphs -> garbage extraction).
      if ((rune >= 0xE000 && rune <= 0xF8FF) ||
          (rune >= 0xF0000 && rune <= 0xFFFFD) ||
          (rune >= 0x100000 && rune <= 0x10FFFD)) {
        continue;
      }

      sb.writeCharCode(rune);
      if (sb.length >= maxLen) break;
    }

    var out = sb.toString();
    out = out.replaceAll(RegExp(r'[ \t]+'), ' ');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  Future<String> translateChunk({
    required String raw,
    required VocabularyLevel level,
    required TranslationMode mode,
  }) async {
    // Commercial-grade graceful degradation: never throw, always return raw.
    try {
      final jsonText = await fetchVocabJson(raw: raw, level: level, mode: mode);
      if (jsonText == null) return raw;
      final vocab = parseVocabJson(jsonText, mode: mode, source: raw);
      if (vocab.isEmpty) return raw;
      return applyVocabReplacements(raw, vocab, mode: mode);
    } catch (error, stackTrace) {
      debugPrint('[ai] translate fallback error=$error');
      debugPrintStack(stackTrace: stackTrace);
      return raw;
    }
  }

  Future<String?> fetchVocabJson({
    required String raw,
    required VocabularyLevel level,
    required TranslationMode mode,
  }) async {
    if (!await AiConsentStore.isAllowed()) return null;
    final uri = _proxyUri;
    if (uri == null) {
      debugPrint('[ai] Proxy URL is invalid or empty. Set DEEPSEEK_PROXY_URL.');
      return null;
    }
    if (_appSecret.isEmpty) {
      debugPrint('[ai] APP_SECRET is empty. Set APP_SECRET.');
      return null;
    }

    final systemPrompt = switch (mode) {
      TranslationMode.zhToEn =>
        '你现在的任务是提取【${level.label}】难度的核心考点词，并结合上下文语境给出英文翻译。\n'
            '警告：绝对禁止提取初高中基础词汇（如 life, ice, memory 等）！宁可少提或不提，也绝不凑数。\n'
            '如果该段落没有符合【${level.label}】难度的高级词汇，请直接返回空 JSON {}。\n'
            '请务必只返回合法的 JSON 格式，格式为：{"中文词1": "English1", "中文词2": "English2"}，不要返回任何其他废话。\n'
            '$_garbleImmunityPrompt',
      TranslationMode.enToZh =>
        '提取这段英文文本中的【${level.label}】难度核心生词，结合语境给出精准的中文翻译。\n'
            '严禁提取基础简单词汇，宁可少提或不提，也绝不凑数。\n'
            '如果该段落没有符合【${level.label}】难度的生词，请直接返回空 JSON {}。\n'
            '请务必只返回合法的 JSON 格式，格式为：{"EnglishWord": "中文翻译"}，不要返回任何其他内容。\n'
            '键必须是原文中出现的英文词或短语；值必须包含中文释义，不要返回英文定义、英文同义词或原词本身。\n'
            '$_garbleImmunityPrompt',
    };

    final body = <String, Object?>{
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': raw},
      ],
      'temperature': 0.2,
    };
    try {
      final client = _clientFactory();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
            if (!await AiConsentStore.isAllowed()) {
              throw const _AiConsentRequired();
            }
            response = await client
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'X-App-Secret': _appSecret,
                  },
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 25));

            // Retry on 5xx.
            if (response.statusCode >= 500) {
              throw Exception('Proxy HTTP ${response.statusCode}');
            }
            break;
          } on _AiConsentRequired {
            rethrow;
          } catch (e) {
            lastError = e;
            if (attempt < 2) {
              final backoffMs = 350 * (attempt + 1) * (attempt + 1);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              continue;
            }
          }
        }

        if (response == null) {
          throw Exception('Proxy request failed: $lastError');
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Reading content is intentionally excluded from logs.
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content = (message is Map<String, dynamic>)
            ? message['content']
            : null;
        if (content is! String || content.trim().isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException(
            'DeepSeek response missing message.content',
          );
        }

        return validateVocabResponse(
          _extractJsonObject(content),
          mode: mode,
          source: raw,
        );
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] fetch vocab json error=$error');
      debugPrintStack(stackTrace: stackTrace);
      // Reading content is intentionally excluded from logs.
      return null;
    }
  }

  /// Translates the selected plain text (used by PDF reader overlay).
  ///
  /// Returns null on any error; callers should degrade gracefully.
  Future<String?> translatePlainText({
    required String raw,
    required TranslationMode mode,
  }) async {
    if (!await AiConsentStore.isAllowed()) return null;
    final uri = _proxyUri;
    if (uri == null) {
      debugPrint('[ai] Proxy URL is invalid or empty. Set DEEPSEEK_PROXY_URL.');
      return null;
    }
    if (_appSecret.isEmpty) {
      debugPrint('[ai] APP_SECRET is empty. Set APP_SECRET.');
      return null;
    }

    final sanitized = _sanitizeForAi(raw);
    if (sanitized.isEmpty) {
      debugPrint('[ai] plain translate: selection sanitized to empty.');
      return null;
    }

    final systemPrompt = switch (mode) {
      TranslationMode.enToZh =>
        '你是一名专业的中英翻译。请将用户提供的英文文本翻译为简体中文。\n'
            '要求：忠实准确、语言自然；尽量保留原文段落结构与标点；只输出翻译后的中文，不要解释，不要添加任何多余内容。',
      TranslationMode.zhToEn =>
        'You are a professional translator. Translate the user-provided Chinese text into natural English.\n'
            'Requirements: accurate and fluent; preserve paragraph structure and punctuation when possible; output only the translation, no extra commentary.',
    };
    final guardedSystemPrompt = '$systemPrompt\n\n$_garbleImmunityPrompt';

    final body = <String, Object?>{
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': guardedSystemPrompt},
        {'role': 'user', 'content': sanitized},
      ],
      'temperature': 0.2,
    };

    try {
      final client = _clientFactory();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
            if (!await AiConsentStore.isAllowed()) {
              throw const _AiConsentRequired();
            }
            response = await client
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'X-App-Secret': _appSecret,
                  },
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 25));

            // Retry on 5xx.
            if (response.statusCode >= 500) {
              throw Exception('Proxy HTTP ${response.statusCode}');
            }
            break;
          } on _AiConsentRequired {
            rethrow;
          } catch (e) {
            lastError = e;
            if (attempt < 2) {
              final backoffMs = 350 * (attempt + 1) * (attempt + 1);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              continue;
            }
          }
        }

        if (response == null) {
          throw Exception('Proxy request failed: $lastError');
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Reading content is intentionally excluded from logs.
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content = (message is Map<String, dynamic>)
            ? message['content']
            : null;
        if (content is! String || content.trim().isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException(
            'DeepSeek response missing message.content',
          );
        }

        return content.trim();
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] plain translate error=$error');
      debugPrintStack(stackTrace: stackTrace);
      // Reading content is intentionally excluded from logs.
      return null;
    }
  }

  /// Cleans noisy OCR output into readable body text.
  ///
  /// The primary use case is photo-based scanning: keep the image itself
  /// selectable, but present a cleaner body-text version underneath.
  /// This method never throws. If the proxy is unavailable or the request
  /// fails, it falls back to locally sanitized text.
  Future<String> cleanupOcrPlainText({required String raw}) async {
    final sanitized = _sanitizeForAi(raw, maxLen: 4200);
    if (sanitized.isEmpty) return '';
    if (!await AiConsentStore.isAllowed()) return sanitized;

    final uri = _proxyUri;
    if (uri == null) {
      debugPrint('[ai] OCR cleanup: proxy URL missing, using local fallback.');
      return sanitized;
    }
    if (_appSecret.isEmpty) {
      debugPrint('[ai] OCR cleanup: APP_SECRET missing, using local fallback.');
      return sanitized;
    }

    const systemPrompt =
        '你是一个 OCR 正文整理助手。请将用户提供的一页 OCR 文本整理成适合阅读的正文段落。\n'
        '规则：\n'
        '1. 删除页眉页脚、页码、装饰符号、图标字符、广告语、重复标题、明显乱码、公式残片、无意义特殊符号。\n'
        '2. 删除明显不是正文的碎片内容，但不要编造任何原文里不存在的句子。\n'
        '3. 宁可保留疑似正文的小字、边注、对话标识、脚注或弱化文字，也不要误删真实正文。\n'
        '4. 不要因为字体小、字数少、位置靠边，就擅自删除可能属于正文的内容。\n'
        '5. 保留原始语言，不要翻译，不要总结，不要添加解释。\n'
        '6. 合并被 OCR 生硬拆开的行，让段落格式更自然。\n'
        '7. 如果某些字符看起来像 OCR 误识别，请在不改变原意的前提下进行最小修复。\n'
        '8. 最终只输出整理后的纯文本正文，不要 Markdown，不要代码块，不要额外说明。';

    final body = <String, Object?>{
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': sanitized},
      ],
      'temperature': 0.15,
    };

    try {
      final client = _clientFactory();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
            if (!await AiConsentStore.isAllowed()) {
              throw const _AiConsentRequired();
            }
            response = await client
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'X-App-Secret': _appSecret,
                  },
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 25));

            if (response.statusCode >= 500) {
              throw Exception('Proxy HTTP ${response.statusCode}');
            }
            break;
          } on _AiConsentRequired {
            rethrow;
          } catch (e) {
            lastError = e;
            if (attempt < 2) {
              final backoffMs = 350 * (attempt + 1) * (attempt + 1);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              continue;
            }
          }
        }

        if (response == null) {
          throw Exception('Proxy request failed: $lastError');
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Reading content is intentionally excluded from logs.
          debugPrint(
            '[ai] OCR cleanup proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content = (message is Map<String, dynamic>)
            ? message['content']
            : null;
        if (content is! String || content.trim().isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException(
            'DeepSeek response missing message.content',
          );
        }

        return _stripMarkdownFence(content).trim();
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] OCR cleanup error=$error');
      debugPrintStack(stackTrace: stackTrace);
      // Reading content is intentionally excluded from logs.
      return sanitized;
    }
  }

  /// Extracts a list of core vocabulary entries from an English paragraph.
  ///
  /// This is used by the PDF "Apple Glass" bottom sheet in 【核心生词】 mode.
  /// Returns an empty list on any error (never throws).
  Future<List<CoreVocabItem>> extractCoreVocabulary({
    required String raw,
    required VocabularyLevel level,
  }) async {
    try {
      final jsonText = await fetchCoreVocabularyJson(raw: raw, level: level);
      if (jsonText == null) return const <CoreVocabItem>[];
      return parseCoreVocabularyJson(jsonText);
    } catch (error, stackTrace) {
      debugPrint('[ai] extract core vocab error=$error');
      debugPrintStack(stackTrace: stackTrace);
      return const <CoreVocabItem>[];
    }
  }

  Future<String?> fetchCoreVocabularyJson({
    required String raw,
    required VocabularyLevel level,
  }) async {
    if (!await AiConsentStore.isAllowed()) return null;
    final uri = _proxyUri;
    if (uri == null) {
      debugPrint('[ai] Proxy URL is invalid or empty. Set DEEPSEEK_PROXY_URL.');
      return null;
    }
    if (_appSecret.isEmpty) {
      debugPrint('[ai] APP_SECRET is empty. Set APP_SECRET.');
      return null;
    }

    final systemPrompt =
        '你是一个英语学习专家。请从以下英文段落中，提取出所有符合【${level.label}】大纲的核心词汇。\n'
        '必须极其严格地以 JSON 数组格式返回，每个对象包含：\n'
        'word (原词), phonetic (音标, 若不确定请返回空字符串 ""), meaning (在这个句子中的精准语境中文意思)。\n'
        '如果没有符合该难度的词，返回空数组 []。\n'
        '警告：不要输出任何其他废话，不要 Markdown，不要代码块，只允许输出 JSON 数组本身。\n'
        '$_garbleImmunityPrompt';

    // Sanitize noisy PDF selections to improve model stability.
    final normalized = _sanitizeForAi(raw);
    if (normalized.isEmpty) {
      debugPrint('[ai] core vocab: selection sanitized to empty.');
      return null;
    }

    final body = <String, Object?>{
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': normalized},
      ],
      'temperature': 0.2,
    };

    try {
      final client = _clientFactory();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
            if (!await AiConsentStore.isAllowed()) {
              throw const _AiConsentRequired();
            }
            response = await client
                .post(
                  uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'X-App-Secret': _appSecret,
                  },
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 25));

            if (response.statusCode >= 500) {
              throw Exception('Proxy HTTP ${response.statusCode}');
            }
            break;
          } on _AiConsentRequired {
            rethrow;
          } catch (e) {
            lastError = e;
            if (attempt < 2) {
              final backoffMs = 350 * (attempt + 1) * (attempt + 1);
              await Future<void>.delayed(Duration(milliseconds: backoffMs));
              continue;
            }
          }
        }

        if (response == null) {
          throw Exception('Proxy request failed: $lastError');
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Reading content is intentionally excluded from logs.
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content = (message is Map<String, dynamic>)
            ? message['content']
            : null;
        if (content is! String || content.trim().isEmpty) {
          // Reading content is intentionally excluded from logs.
          throw const FormatException(
            'DeepSeek response missing message.content',
          );
        }

        final extracted = _extractJsonArray(content);
        try {
          final maybe = jsonDecode(extracted);
          if (maybe is List && maybe.isEmpty) {
            // Reading content is intentionally excluded from logs.
            debugPrint('[ai] Model returned empty vocab list [].');
          }
        } catch (_) {}
        return extracted;
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] fetch core vocab json error=$error');
      debugPrintStack(stackTrace: stackTrace);
      // Reading content is intentionally excluded from logs.
      return null;
    }
  }

  String _extractJsonObject(String content) {
    final trimmed = content.trim();
    try {
      final direct = jsonDecode(trimmed);
      if (direct is Map) return trimmed;
    } catch (_) {}

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw const FormatException('Model output is not JSON');
    }
    return trimmed.substring(start, end + 1);
  }

  String _stripMarkdownFence(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    return trimmed
        .replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\n?'), '')
        .replaceFirst(RegExp(r'\n?```$'), '')
        .trim();
  }

  String _extractJsonArray(String content) {
    final trimmed = content.trim();
    try {
      final direct = jsonDecode(trimmed);
      if (direct is List) return trimmed;
      if (direct is Map) {
        final data = direct['data'];
        if (data is List) return jsonEncode(data);
      }
    } catch (_) {}

    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) {
      throw const FormatException('Model output is not JSON array');
    }
    final sub = trimmed.substring(start, end + 1);
    final decoded = jsonDecode(sub);
    if (decoded is! List) {
      throw const FormatException('Model output is not JSON array');
    }
    return sub;
  }

  static Map<String, String> parseVocabJson(
    String jsonText, {
    TranslationMode? mode,
    String? source,
  }) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) return const <String, String>{};
    final result = <String, String>{};
    decoded.forEach((k, v) {
      if (k is String && v is String) {
        final kk = k.trim();
        final vv = v.trim();
        if (kk.isNotEmpty && vv.isNotEmpty) result[kk] = vv;
      }
    });
    return mode == null
        ? result
        : filterVocabularyForMode(result, mode: mode, source: source);
  }

  /// Returns only cacheable vocabulary JSON. A legitimate empty object means
  /// no matches; an entirely invalid nonempty response remains a failed request.
  static String? validateVocabResponse(
    String jsonText, {
    required TranslationMode mode,
    required String source,
  }) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('Vocabulary response must be an object');
    }
    final vocab = parseVocabJson(jsonText, mode: mode, source: source);
    if (decoded.isNotEmpty && vocab.isEmpty) {
      // Never log source text or model-produced vocabulary.
      debugPrint(
        '[ai] Vocabulary response has no valid target-language entries.',
      );
      return null;
    }
    return jsonEncode(vocab);
  }

  /// Validates both sides of an inline gloss before rendering or caching it.
  /// Original prose is never changed by this filter: a rejected entry simply
  /// leaves its source word unannotated.
  static Map<String, String> filterVocabularyForMode(
    Map<String, String> vocab, {
    required TranslationMode mode,
    String? source,
  }) {
    final result = <String, String>{};
    final han = RegExp(r'[\u3400-\u9FFF]');
    final latin = RegExp(r'[A-Za-z]');
    for (final entry in vocab.entries) {
      final word = entry.key.trim();
      final meaning = entry.value.trim();
      if (word.isEmpty || meaning.isEmpty) continue;
      if (word.toLowerCase() == meaning.toLowerCase()) continue;
      final valid = switch (mode) {
        TranslationMode.enToZh =>
          latin.hasMatch(word) && !han.hasMatch(word) && han.hasMatch(meaning),
        TranslationMode.zhToEn =>
          han.hasMatch(word) &&
              latin.hasMatch(meaning) &&
              !han.hasMatch(meaning),
      };
      if (!valid) continue;
      if (source != null && !_sourcePattern(word, mode).hasMatch(source)) {
        continue;
      }
      result[word] = meaning;
    }
    return result;
  }

  /// Callers can treat a mismatching historical cache as a cache miss without
  /// deleting the file, reading progress, or any saved vocabulary.
  static bool matchesVocabularyMode(
    Map<String, String> vocab, {
    required TranslationMode mode,
    String? source,
  }) =>
      filterVocabularyForMode(vocab, mode: mode, source: source).length ==
      vocab.length;

  static RegExp _sourcePattern(String word, TranslationMode mode) => RegExp(
    mode == TranslationMode.enToZh
        ? r'(?<![A-Za-zÀ-ÖØ-öø-ÿ])' +
              RegExp.escape(word) +
              r'(?![A-Za-zÀ-ÖØ-öø-ÿ])'
        : RegExp.escape(word),
    caseSensitive: mode == TranslationMode.zhToEn,
  );

  static String applyVocabReplacements(
    String text,
    Map<String, String> vocab, {
    required TranslationMode mode,
    void Function(int sourceOffset, int renderedStart, int renderedEnd)?
    onAnnotation,
  }) {
    final validated = filterVocabularyForMode(vocab, mode: mode, source: text);
    final keys = validated.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (keys.isEmpty) return text;
    final alternatives = keys.map(RegExp.escape).join('|');
    final pattern = RegExp(
      mode == TranslationMode.enToZh
          ? r'(?<![A-Za-zÀ-ÖØ-öø-ÿ])(?:' +
                alternatives +
                r')(?![A-Za-zÀ-ÖØ-öø-ÿ])'
          : '(?:$alternatives)',
      caseSensitive: mode == TranslationMode.zhToEn,
    );
    final meanings = mode == TranslationMode.enToZh
        ? {
            for (final entry in validated.entries)
              entry.key.toLowerCase(): entry.value,
          }
        : validated;
    // Match the original string once. Sequential replaceAll calls would also
    // annotate words that a previous replacement had just inserted in a gloss.
    var insertedLength = 0;
    return text.replaceAllMapped(pattern, (match) {
      final original = match.group(0)!;
      final lookup = mode == TranslationMode.enToZh
          ? original.toLowerCase()
          : original;
      final annotation = '(${meanings[lookup]})';
      // String/Match offsets use UTF-16, as do Flutter text selections. Only
      // newly generated annotations are reported; source parentheses stay prose.
      final renderedStart = match.end + insertedLength;
      onAnnotation?.call(
        match.end,
        renderedStart,
        renderedStart + annotation.length,
      );
      insertedLength += annotation.length;
      return '$original$annotation';
    });
  }

  static List<CoreVocabItem> parseCoreVocabularyJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    final list = switch (decoded) {
      List() => decoded,
      Map() => (decoded['data'] is List) ? decoded['data'] as List : null,
      _ => null,
    };
    if (list == null) return const <CoreVocabItem>[];

    final result = <CoreVocabItem>[];
    final seen = <String>{};

    for (final item in list) {
      if (item is! Map) continue;
      final wordRaw = item['word'];
      final word = (wordRaw is String) ? wordRaw.trim() : '';
      if (word.isEmpty) continue;
      final key = word.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);

      final phoneticRaw = item['phonetic'];
      final phonetic = (phoneticRaw is String) ? phoneticRaw.trim() : '';
      final meaningRaw = item['meaning'];
      final meaning = (meaningRaw is String) ? meaningRaw.trim() : '';

      result.add(
        CoreVocabItem(word: word, phonetic: phonetic, meaning: meaning),
      );
    }

    return result;
  }
}

@immutable
class CoreVocabItem {
  const CoreVocabItem({
    required this.word,
    required this.phonetic,
    required this.meaning,
  });

  final String word;
  final String phonetic;
  final String meaning;
}

class _AiConsentRequired implements Exception {
  const _AiConsentRequired();
}
