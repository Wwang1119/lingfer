import 'dart:convert';

import 'package:flutter/services.dart';

import '../../models/vocabulary_level.dart';

class VocabularyEntry {
  const VocabularyEntry({
    required this.word,
    required this.translation,
    required this.tags,
  });

  final String word;
  final String translation;
  final Set<String> tags;

  bool matches(VocabularyLevel level) {
    final tag = switch (level) {
      VocabularyLevel.zhongkao => 'zk',
      VocabularyLevel.gaokao => 'gk',
      VocabularyLevel.cet4 => 'cet4',
      VocabularyLevel.cet6 => 'cet6',
      VocabularyLevel.kaoyan => 'ky',
      VocabularyLevel.ielts => 'ielts',
      VocabularyLevel.toefl => 'toefl',
    };
    if (!tags.contains(tag)) return false;
    if (level == VocabularyLevel.zhongkao) return true;
    // The exam lists overlap. Remove school-level words from advanced modes,
    // then let the learner's own known-word list refine the selection.
    if (tags.contains('zk')) return false;
    if (level != VocabularyLevel.gaokao && tags.contains('gk')) return false;
    return true;
  }
}

class VocabularyHit {
  const VocabularyHit({
    required this.entry,
    required this.surface,
    required this.context,
    this.sourceLanguage = 'en',
    this.targetLanguage = 'zh',
    this.annotation,
    this.sourceStart,
    this.sourceEnd,
  });

  final VocabularyEntry entry;
  final String surface;
  final String context;
  final String sourceLanguage;
  final String targetLanguage;
  final String? annotation;
  final int? sourceStart;
  final int? sourceEnd;
  String get studyKey => sourceLanguage == 'en' || targetLanguage == 'en'
      ? entry.word
      : '$sourceLanguage:$targetLanguage:${entry.word}';
  String get shortTranslation =>
      annotation ??
      entry.translation
          .split('\n')
          .first
          .replaceFirst(RegExp(r'^[a-z./ ,]+\.\s*'), '')
          .split(RegExp(r'[,，;；]'))
          .first
          .trim();

  Map<String, Object?> toJson() => {
    'word': entry.word,
    'surface': surface,
    'translation': entry.translation,
    'tags': entry.tags.toList(),
    'context': context,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'annotation': annotation,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'studyKey': studyKey,
  };

  static VocabularyHit? fromJson(Object? raw) {
    if (raw is! Map ||
        raw['word'] is! String ||
        raw['translation'] is! String) {
      return null;
    }
    return VocabularyHit(
      entry: VocabularyEntry(
        word: raw['word'] as String,
        translation: raw['translation'] as String,
        tags: ((raw['tags'] as List?) ?? const []).whereType<String>().toSet(),
      ),
      surface: raw['surface'] as String? ?? raw['word'] as String,
      context: raw['context'] as String? ?? '',
      sourceLanguage: raw['sourceLanguage'] as String? ?? 'en',
      targetLanguage: raw['targetLanguage'] as String? ?? 'zh',
      annotation: raw['annotation'] as String?,
      sourceStart: (raw['sourceStart'] as num?)?.toInt(),
      sourceEnd: (raw['sourceEnd'] as num?)?.toInt(),
    );
  }
}

class VocabularyEngine {
  VocabularyEngine(this.entries);

  final Map<String, VocabularyEntry> entries;
  static Future<VocabularyEngine>? _loading;

  static Future<VocabularyEngine> load() => _loading ??= () async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/data/vocabulary.json'))
            as Map;
    return VocabularyEngine.fromJson(raw);
  }();

  factory VocabularyEngine.fromJson(Map raw) {
    final data = raw['entries'] as Map;
    return VocabularyEngine({
      for (final item in data.entries)
        item.key as String: VocabularyEntry(
          word: item.key as String,
          translation: (item.value as Map)['translation'] as String,
          tags: ((item.value as Map)['tags'] as List).cast<String>().toSet(),
        ),
    });
  }

  VocabularyEntry? lookup(String surface) {
    final word = surface.toLowerCase().replaceAll('’', "'");
    if (entries.containsKey(word)) return entries[word];
    final candidates = <String>[];
    if (word.endsWith("'s")) candidates.add(word.substring(0, word.length - 2));
    if (word.endsWith('ies') && word.length > 4) {
      candidates.add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('es')) candidates.add(word.substring(0, word.length - 2));
    if (word.endsWith('s') && !word.endsWith('ss')) {
      candidates.add(word.substring(0, word.length - 1));
    }
    for (final suffix in ['ing', 'ed']) {
      if (!word.endsWith(suffix) || word.length < suffix.length + 3) continue;
      final stem = word.substring(0, word.length - suffix.length);
      candidates.addAll([stem, '${stem}e']);
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        candidates.add(stem.substring(0, stem.length - 1));
      }
      if (suffix == 'ed' && stem.endsWith('i')) {
        candidates.add('${stem.substring(0, stem.length - 1)}y');
      }
    }
    for (final candidate in candidates) {
      if (entries.containsKey(candidate)) return entries[candidate];
    }
    return null;
  }

  List<VocabularyHit> extract(
    String text,
    VocabularyLevel level, {
    Set<String> known = const {},
    int limit = 24,
  }) {
    final seen = <String>{};
    final results = <VocabularyHit>[];
    for (final match in RegExp(
      r"[A-Za-z]+(?:['’-][A-Za-z]+)*",
    ).allMatches(text)) {
      final surface = match.group(0)!;
      final entry = lookup(surface);
      if (entry == null ||
          known.contains(entry.word) ||
          !entry.matches(level) ||
          !seen.add(entry.word)) {
        continue;
      }
      results.add(
        VocabularyHit(
          entry: entry,
          surface: surface,
          context: sentenceAt(text, match.start, match.end),
          sourceStart: match.start,
          sourceEnd: match.end,
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  static String sentenceAt(String text, int start, int end) {
    var left = start;
    var right = end;
    while (left > 0 && start - left < 180 && !_boundaryAt(text, left - 1)) {
      left--;
    }
    while (right < text.length &&
        right - end < 220 &&
        !_boundaryAt(text, right)) {
      right++;
    }
    if (right < text.length && _boundaryAt(text, right)) {
      right++;
    }
    return text
        .substring(left, right)
        .trim()
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
  }

  static final _english = RegExp(r'[A-Za-z]+');

  static bool _boundaryAt(String text, int at) {
    if ('.!?;。！？；'.contains(text[at])) {
      return true;
    }
    if (text[at] != '\n') {
      return false;
    }
    if (at == 0 ||
        at + 1 == text.length ||
        text[at - 1] == '\n' ||
        text[at + 1] == '\n') {
      return true;
    }
    final previousStart = text.lastIndexOf('\n', at - 1) + 1;
    final nextEnd = text.indexOf('\n', at + 1);
    final previous = text.substring(previousStart, at).trim();
    final next = text
        .substring(at + 1, nextEnd < 0 ? text.length : nextEnd)
        .trim();
    // OCR emits visual lines. Continue a long English line, but keep paragraph
    // gaps, short headings, and interface labels outside the sentence.
    return previous.length < 35 ||
        _english.allMatches(previous).take(5).length < 5 ||
        _english.allMatches(next).take(2).length < 2 ||
        next == next.toUpperCase();
  }
}
