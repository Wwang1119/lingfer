import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/translation_mode.dart';
import '../models/vocabulary_level.dart';

class AiTranslationService {
  AiTranslationService({
    required String proxyUrl,
    required String appSecret,
  })  : _proxyUri = Uri.tryParse(proxyUrl),
        _appSecret = appSecret;

  final Uri? _proxyUri;
  final String _appSecret;

  static const String _garbleImmunityPrompt =
      '提取的英文中可能包含由 PDF 矢量公式/特殊符号引起的乱码。'
      '请你作为顶级语言专家，极其智能地忽略这些乱码，结合上下文脑补并修复成正常的句子后再翻译或提取生词。'
      '绝对不要把乱码直接翻译出来或报错。';

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
      final vocab = parseVocabJson(jsonText);
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
    final rawPreviewStart = raw.length <= 240 ? raw : raw.substring(0, 240);
    final rawPreviewEnd = raw.length <= 240 ? '' : raw.substring(raw.length - 240);
    final promptForLog = StringBuffer()
      ..writeln('[ai] mode=${mode.name} level=${level.label} rawLen=${raw.length}')
      ..writeln('[ai] systemPrompt:\n$systemPrompt')
      ..writeln('[ai] userContentPreview(start):\n$rawPreviewStart');
    if (rawPreviewEnd.isNotEmpty) {
      promptForLog.writeln('[ai] userContentPreview(end):\n$rawPreviewEnd');
    }

    try {
      final client = http.Client();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
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
          debugPrint(promptForLog.toString());
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content =
            (message is Map<String, dynamic>) ? message['content'] : null;
        if (content is! String || content.trim().isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing message.content');
        }

        final extracted = _extractJsonObject(content);
        try {
          final maybe = jsonDecode(extracted);
          if (maybe is Map && maybe.isEmpty) {
            debugPrint(promptForLog.toString());
            debugPrint('[ai] Model returned empty JSON {}.');
          }
        } catch (_) {
          // If it isn't valid JSON, _extractJsonObject will have thrown earlier.
        }
        return extracted;
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] fetch vocab json error=$error');
      debugPrintStack(stackTrace: stackTrace);
      debugPrint(promptForLog.toString());
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

    final rawPreview = sanitized.length <= 240
        ? sanitized
        : sanitized.substring(0, 240);
    final promptForLog = StringBuffer()
      ..writeln(
        '[ai] plain translate mode=${mode.name} rawLen=${raw.length} sanitizedLen=${sanitized.length}',
      )
      ..writeln('[ai] systemPrompt:\n$guardedSystemPrompt')
      ..writeln('[ai] userContentPreview:\n$rawPreview');

    try {
      final client = http.Client();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
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
          debugPrint(promptForLog.toString());
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content =
            (message is Map<String, dynamic>) ? message['content'] : null;
        if (content is! String || content.trim().isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing message.content');
        }

        return content.trim();
      } finally {
        client.close();
      }
    } catch (error, stackTrace) {
      debugPrint('[ai] plain translate error=$error');
      debugPrintStack(stackTrace: stackTrace);
      debugPrint(promptForLog.toString());
      return null;
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

    final preview = normalized.length <= 260
        ? normalized
        : normalized.substring(0, 260);
    final promptForLog = StringBuffer()
      ..writeln('[ai] core vocab level=${level.label} rawLen=${normalized.length}')
      ..writeln('[ai] systemPrompt:\n$systemPrompt')
      ..writeln('[ai] userContentPreview:\n$preview');

    try {
      final client = http.Client();
      try {
        http.Response? response;
        Object? lastError;

        for (var attempt = 0; attempt < 3; attempt += 1) {
          try {
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
          debugPrint(promptForLog.toString());
          debugPrint(
            '[ai] Proxy HTTP ${response.statusCode} body=${response.body}',
          );
          throw Exception('Proxy HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('Unexpected DeepSeek response JSON');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing choices');
        }
        final message = (choices.first as Map<String, dynamic>)['message'];
        final content =
            (message is Map<String, dynamic>) ? message['content'] : null;
        if (content is! String || content.trim().isEmpty) {
          debugPrint(promptForLog.toString());
          debugPrint('[ai] Proxy raw response: ${response.body}');
          throw const FormatException('DeepSeek response missing message.content');
        }

        final extracted = _extractJsonArray(content);
        try {
          final maybe = jsonDecode(extracted);
          if (maybe is List && maybe.isEmpty) {
            debugPrint(promptForLog.toString());
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
      debugPrint(promptForLog.toString());
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

  static Map<String, String> parseVocabJson(String jsonText) {
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
    return result;
  }

  static String applyVocabReplacements(
    String text,
    Map<String, String> vocab, {
    required TranslationMode mode,
  }) {
    final keys = vocab.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    var output = text;
    for (final key in keys) {
      final english = vocab[key]!;
      if (key.isEmpty || english.isEmpty) continue;
      switch (mode) {
        case TranslationMode.zhToEn:
          output = output.replaceAll(key, '$key($english)');
        case TranslationMode.enToZh:
          final escaped = RegExp.escape(key);
          final re = RegExp(r'\b' + escaped + r'\b', caseSensitive: false);
          output = output.replaceAllMapped(re, (m) => '${m.group(0)}($english)');
      }
    }
    return output;
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
