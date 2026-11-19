import 'reading_assistant.dart';
import 'reading_preferences.dart';

/// Paragraph translations never enter the vocabulary/known-word store.
class TranslatedParagraph {
  const TranslatedParagraph(this.id, this.source, [this.translation]);
  final String id;
  final String source;
  final String? translation;
  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'translation': translation,
  };

  static List<TranslatedParagraph> split(String text) {
    final result = <TranslatedParagraph>[];
    for (final line in text.split(RegExp(r'\n+'))) {
      var remaining = line.trim();
      while (remaining.isNotEmpty) {
        var end = remaining.length > 1400 ? 1400 : remaining.length;
        if (end < remaining.length) {
          // Keep surrogate pairs together, then prefer a nearby word boundary.
          if (remaining.codeUnitAt(end - 1) >= 0xd800 &&
              remaining.codeUnitAt(end - 1) <= 0xdbff) {
            end--;
          }
          final boundary = remaining.lastIndexOf(' ', end);
          if (boundary > end ~/ 2) end = boundary;
        }
        result.add(
          TranslatedParagraph('p${result.length}', remaining.substring(0, end)),
        );
        remaining = remaining.substring(end).trimLeft();
      }
    }
    return result;
  }
}

class PageTranslator {
  PageTranslator(this.assistant);
  final ReadingAssistant assistant;
  final _cache = <String, String>{};
  final _pending = <String, Future<Map<String, String>>>{};

  void remember(
    List<TranslatedParagraph> parts,
    ReadingLanguage source,
    ReadingLanguage target,
  ) {
    for (final part in parts) {
      if (part.translation != null && part.translation!.isNotEmpty) {
        _cache['${source.code}|${target.code}|${part.source}'] =
            part.translation!;
      }
    }
    while (_cache.length > 600) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<List<TranslatedParagraph>> translate(
    String text,
    ReadingLanguage source,
    ReadingLanguage target, {
    void Function(List<TranslatedParagraph>)? onUpdate,
    bool Function()? isCurrent,
  }) async {
    if (text.length > 12000) {
      throw const AssistantUnavailable(
        '内容超过当前页翻译上限，请选取不超过 12000 字的一段文字。原文仍可阅读。',
      );
    }
    return translateRememberedParts(
      TranslatedParagraph.split(text),
      source,
      target,
      onUpdate: onUpdate,
      isCurrent: isCurrent,
    );
  }

  /// Retry an explicitly opened local session without regrouping its bilingual
  /// pairs or retranslating completed source segments. Each network batch keeps
  /// the same existing 24-segment/2400-character request contract.
  Future<List<TranslatedParagraph>> translateRememberedParts(
    List<TranslatedParagraph> original,
    ReadingLanguage source,
    ReadingLanguage target, {
    void Function(List<TranslatedParagraph>)? onUpdate,
    bool Function()? isCurrent,
  }) async {
    if (source == target) {
      throw const AssistantUnavailable('原文与译文语言相同，请修改译文语言。');
    }
    if (original.fold<int>(0, (count, part) => count + part.source.length) >
        240000) {
      throw const AssistantUnavailable('本地记录过长，请分段查看原文。');
    }
    if (original.any((part) => part.source.length > 2400)) {
      throw const AssistantUnavailable('这段本地原文过长，请选取较短段落重试；已有译文仍保留。');
    }
    final parts = List<TranslatedParagraph>.of(original);
    String key(TranslatedParagraph p) =>
        '${source.code}|${target.code}|${p.source}';
    List<TranslatedParagraph> snapshot() => parts
        .map((p) => TranslatedParagraph(p.id, p.source, _cache[key(p)]))
        .toList();
    onUpdate?.call(snapshot());
    final missing = parts.where((p) => !_cache.containsKey(key(p))).toList();
    while (missing.isNotEmpty) {
      if (isCurrent?.call() == false) return snapshot();
      final batch = <TranslatedParagraph>[];
      var length = 0;
      while (missing.isNotEmpty &&
          batch.length < 24 &&
          length + missing.first.source.length <= 2400) {
        final part = missing.removeAt(0);
        batch.add(part);
        length += part.source.length;
      }
      final requestKey =
          '${source.code}|${target.code}|${batch.map((p) => '${p.id}:${p.source}').join('\n')}';
      final request = _pending.putIfAbsent(
        requestKey,
        () => assistant.translateParagraphs(
          paragraphs: batch.map((p) => {'id': p.id, 'text': p.source}).toList(),
          source: source,
          target: target,
        ),
      );
      Map<String, String> values;
      try {
        values = await request;
      } finally {
        _pending.remove(requestKey);
      }
      for (final part in batch) {
        final value = values[part.id];
        if (value != null && value.trim().isNotEmpty) _cache[key(part)] = value;
      }
      if (isCurrent?.call() == false) return snapshot();
      onUpdate?.call(snapshot());
      if (batch.any((p) => !_cache.containsKey(key(p)))) {
        throw const AssistantUnavailable('部分段落尚未译完，已完成的译文会保留，请重试。');
      }
    }
    final result = snapshot();
    // Bound session memory after retaining a complete copy for the caller.
    while (_cache.length > 600) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }
}
