import '../../models/vocabulary_level.dart';
import 'annotations/ocr_document.dart';
import 'reading_assistant.dart';
import 'reading_preferences.dart';
import 'vocabulary_engine.dart';

class MultilingualReader {
  MultilingualReader(this.engine, this.assistant);
  final VocabularyEngine engine;
  final ReadingAssistant assistant;
  final Map<String, List<VocabularyHit>> _cache = {};
  final Map<String, Future<List<VocabularyHit>>> _pending = {};

  Future<List<VocabularyHit>> analyze(
    OcrDocument document,
    ReadingPreferences preferences,
    VocabularyLevel level, {
    Set<String> known = const {},
  }) async {
    preferences = resolvePreferences(document, preferences);
    if (preferences.source == preferences.target) return const [];
    // Automatic Latin-language detection is performed natively. Text-only
    // auto mode goes through the translator so French is never treated as English.
    if (preferences.source == ReadingLanguage.en &&
        preferences.target == ReadingLanguage.zh) {
      return engine.extract(document.text, level, known: known);
    }
    final key = '${preferences.toJson()}|${level.name}|${document.text}';
    var hits = _cache[key];
    if (hits == null) {
      final request = _pending.putIfAbsent(key, () async {
        final raw = await assistant.selectVocabulary(
          segments: document.segments.map((s) => s.toJson()).toList(),
          preferences: preferences,
          level: level.label,
        );
        final found = decode(raw, document, preferences, level);
        if (_cache.length >= 64) _cache.remove(_cache.keys.first);
        _cache[key] = found;
        return found;
      });
      try {
        hits = await request;
      } finally {
        _pending.remove(key);
      }
    }
    return hits.where((h) => !known.contains(h.studyKey)).toList();
  }

  static ReadingPreferences resolvePreferences(
    OcrDocument document,
    ReadingPreferences preferences,
  ) {
    if (preferences.source != ReadingLanguage.auto) return preferences;
    var detected = ReadingLanguage.parse(
      document.language,
      fallback: ReadingLanguage.auto,
    );
    if (detected == ReadingLanguage.auto) {
      final text = document.text;
      final latin = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').allMatches(text).length;
      final nonLatin = RegExp(
        r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af\u0900-\u097f]',
      ).allMatches(text).length;
      final englishWords = RegExp(
        r'\b(the|and|that|with|this|than|is|are|for|from|your|you)\b',
        caseSensitive: false,
      ).allMatches(text).length;
      if (latin >= 60 && latin >= nonLatin * 3) {
        // A short toolbar must not turn a predominantly Latin article into
        // Chinese. Unknown Latin languages still go to the language-aware API.
        detected = englishWords >= 2
            ? ReadingLanguage.en
            : ReadingLanguage.auto;
      } else if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) {
        detected = ReadingLanguage.ja;
      } else if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) {
        detected = ReadingLanguage.ko;
      } else if (RegExp(r'[\u0900-\u097f]').hasMatch(text)) {
        detected = ReadingLanguage.hi;
      } else if (RegExp(r'[\u3400-\u9fff]').hasMatch(text)) {
        detected = ReadingLanguage.zh;
      } else if (englishWords >= 2) {
        detected = ReadingLanguage.en;
      }
    }
    return preferences.copyWith(
      source: detected,
      target:
          detected == ReadingLanguage.zh &&
              preferences.mode == ReadingMode.learning &&
              preferences.target == ReadingLanguage.zh
          ? ReadingLanguage.en
          : preferences.target,
    );
  }

  List<VocabularyHit> decode(
    List<Map<String, dynamic>> values,
    OcrDocument document,
    ReadingPreferences preferences,
    VocabularyLevel level,
  ) {
    final hits = <VocabularyHit>[];
    final seen = <String>{};
    for (final raw in values.take(24)) {
      final source = raw['source'],
          target = raw['translation'],
          word = raw['word'];
      if (source is! String ||
          source.isEmpty ||
          target is! String ||
          target.isEmpty ||
          word is! String) {
        continue;
      }
      final segment = document.segments
          .where((s) => s.id == raw['segmentId'])
          .firstOrNull;
      if (segment == null) continue;
      final offset = segment.text.indexOf(source);
      if (offset < 0) continue;
      final actualSource = preferences.source == ReadingLanguage.auto
          ? ReadingLanguage.parse(
              raw['sourceLanguage'],
              fallback: ReadingLanguage.auto,
            )
          : preferences.source;
      final english =
          actualSource == ReadingLanguage.en ||
          preferences.target == ReadingLanguage.en;
      final entry = engine.lookup(word);
      if (english && (entry == null || !entry.matches(level))) continue;
      final key = entry?.word ?? word.toLowerCase();
      if (!seen.add(key)) continue;
      final translated = preferences.target == ReadingLanguage.en
          ? key
          : target;
      hits.add(
        VocabularyHit(
          entry: VocabularyEntry(
            word: key,
            translation: translated,
            tags: english
                ? entry!.tags
                : {'estimated-${preferences.difficulty.name}'},
          ),
          surface: source,
          context: VocabularyEngine.sentenceAt(
            document.text,
            segment.start + offset,
            segment.start + offset + source.length,
          ),
          sourceLanguage: actualSource.code,
          targetLanguage: preferences.target.code,
          annotation: translated,
          sourceStart: segment.start + offset,
          sourceEnd: segment.start + offset + source.length,
        ),
      );
    }
    return hits;
  }
}
