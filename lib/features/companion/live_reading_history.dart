import 'dart:convert';

import 'page_translation.dart';
import 'vocabulary_engine.dart';

/// The last bounded native reading session, independently of the current live
/// screen and of words the learner explicitly chooses to save.
class LocalReadingSnapshot {
  const LocalReadingSnapshot({
    required this.sessionId,
    required this.text,
    required this.hits,
    required this.parts,
    required this.optionsSignature,
    required this.pageCount,
    required this.updatedAt,
    this.retainedPageCount = 0,
    this.resolvedSource,
    this.resolvedTarget,
  });

  static const maximumBytes = 2 * 1024 * 1024;
  final String sessionId;
  final String text;
  final List<VocabularyHit> hits;
  final List<TranslatedParagraph> parts;
  final String optionsSignature;
  final int pageCount;
  final int retainedPageCount;
  final double updatedAt;
  final String? resolvedSource;
  final String? resolvedTarget;

  LocalReadingSnapshot withResults({
    List<VocabularyHit>? hits,
    List<TranslatedParagraph>? parts,
  }) => LocalReadingSnapshot(
    sessionId: sessionId,
    text: text,
    hits: hits ?? this.hits,
    parts: parts ?? this.parts,
    optionsSignature: optionsSignature,
    pageCount: pageCount,
    retainedPageCount: retainedPageCount,
    updatedAt: DateTime.now().millisecondsSinceEpoch / 1000,
    resolvedSource: resolvedSource,
    resolvedTarget: resolvedTarget,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'sessionId': sessionId,
    'text': text,
    'hits': hits.map((hit) => hit.toJson()).toList(),
    'translationSegments': parts
        .map(
          (part) => {
            'id': part.id,
            'source': part.source,
            'translation': part.translation,
          },
        )
        .toList(),
    'optionsSignature': optionsSignature,
    'pageCount': pageCount,
    'retainedPageCount': retainedPageCount,
    'updatedAt': updatedAt,
    'resolvedSource': resolvedSource,
    'resolvedTarget': resolvedTarget,
  };

  static LocalReadingSnapshot? fromJson(Object? raw) {
    try {
      return _fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  static LocalReadingSnapshot? _fromJson(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['sessionId'] is! String ||
        raw['text'] is! String ||
        raw['optionsSignature'] is! String ||
        raw['hits'] is! List ||
        raw['translationSegments'] is! List ||
        raw['pageCount'] is! num ||
        raw['updatedAt'] is! num) {
      return null;
    }
    final text = raw['text'] as String;
    final count = (raw['pageCount'] as num).toInt();
    if (text.isEmpty ||
        text.runes.length > 240000 ||
        count < 1 ||
        count > 60 ||
        (raw['hits'] as List).length > 480 ||
        (raw['translationSegments'] as List).length > 7200) {
      return null;
    }
    final parts = (raw['translationSegments'] as List)
        .whereType<Map>()
        .where((value) => value['source'] is String)
        .map(
          (value) => TranslatedParagraph(
            value['id']?.toString() ?? '',
            value['source'] as String,
            value['translation'] is String
                ? value['translation'] as String
                : null,
          ),
        )
        .toList();
    return LocalReadingSnapshot(
      sessionId: raw['sessionId'] as String,
      text: text,
      hits: (raw['hits'] as List)
          .map(VocabularyHit.fromJson)
          .whereType<VocabularyHit>()
          .toList(),
      parts: parts,
      optionsSignature: raw['optionsSignature'] as String,
      pageCount: count,
      retainedPageCount: (raw['retainedPageCount'] as num?)?.toInt() ?? count,
      updatedAt: (raw['updatedAt'] as num).toDouble(),
      resolvedSource: raw['resolvedSource'] as String?,
      resolvedTarget: raw['resolvedTarget'] as String?,
    );
  }

  static LocalReadingSnapshot? decode(String? raw) {
    if (raw == null || utf8.encode(raw).length > maximumBytes) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
