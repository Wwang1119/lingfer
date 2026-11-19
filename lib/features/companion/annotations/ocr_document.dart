import 'dart:ui';
import '../vocabulary_engine.dart';

class OcrWord {
  const OcrWord(this.text, this.rect, this.start, this.end);
  final String text;
  final Rect rect;
  final int start;
  final int end;
}

class OcrSegment {
  const OcrSegment(this.id, this.text, this.rect, this.start);
  final String id;
  final String text;
  final Rect rect;
  final int start;
  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

class OcrDocument {
  const OcrDocument({
    required this.text,
    required this.width,
    required this.height,
    required this.words,
    required this.segments,
    this.language,
  });
  final String text;
  final String? language;
  final double width;
  final double height;
  final List<OcrWord> words;
  final List<OcrSegment> segments;

  factory OcrDocument.fromMap(Map raw) {
    final lines = (raw['lines'] as List? ?? const []).whereType<Map>();
    final words = <OcrWord>[];
    final segments = <OcrSegment>[];
    var offset = 0;
    final text = StringBuffer();
    for (final line in lines) {
      final value = line['text'] as String? ?? '';
      if (value.isEmpty) continue;
      if (text.isNotEmpty) {
        text.write('\n');
        offset++;
      }
      final start = offset;
      final id = line['id'] as String? ?? 's${segments.length}';
      segments.add(OcrSegment(id, value, _rect(line), start));
      for (final word
          in (line['words'] as List? ?? const []).whereType<Map>()) {
        final surface = word['text'] as String? ?? '';
        final local =
            (word['start'] as num?)?.toInt() ?? value.indexOf(surface);
        if (surface.isEmpty ||
            local < 0 ||
            local + surface.length > value.length) {
          continue;
        }
        words.add(
          OcrWord(
            surface,
            _rect(word),
            start + local,
            start + local + surface.length,
          ),
        );
      }
      text.write(value);
      offset += value.length;
    }
    return OcrDocument(
      text: text.isNotEmpty ? text.toString() : raw['text'] as String? ?? '',
      width: (raw['imageWidth'] as num?)?.toDouble() ?? 1,
      height: (raw['imageHeight'] as num?)?.toDouble() ?? 1,
      words: words,
      segments: segments,
      language: raw['detectedLanguage'] as String?,
    );
  }

  factory OcrDocument.fromText(String text) {
    var offset = 0;
    final segments = <OcrSegment>[];
    for (final line in text.split('\n')) {
      segments.add(OcrSegment('s${segments.length}', line, Rect.zero, offset));
      offset += line.length + 1;
    }
    return OcrDocument(
      text: text,
      width: 1,
      height: 1,
      words: const [],
      segments: segments,
    );
  }

  static Rect _rect(Map v) => Rect.fromLTWH(
    (v['left'] as num?)?.toDouble() ?? 0,
    (v['top'] as num?)?.toDouble() ?? 0,
    (v['width'] as num?)?.toDouble() ?? 0,
    (v['height'] as num?)?.toDouble() ?? 0,
  );

  List<Rect> anchors(VocabularyHit hit) {
    final ranges = <(int, int)>[];
    if (hit.sourceStart != null && hit.sourceEnd != null) {
      ranges.add((hit.sourceStart!, hit.sourceEnd!));
    } else {
      for (final match in RegExp(
        RegExp.escape(hit.surface),
        caseSensitive: false,
      ).allMatches(text)) {
        ranges.add((match.start, match.end));
      }
    }
    return ranges
        .map((range) {
          final boxes = words.where(
            (w) => w.start < range.$2 && w.end > range.$1 && !w.rect.isEmpty,
          );
          return boxes.isEmpty
              ? Rect.zero
              : boxes.map((w) => w.rect).reduce((a, b) => a.expandToInclude(b));
        })
        .where((v) => !v.isEmpty)
        .toList();
  }
}

class AnnotationPlacement {
  const AnnotationPlacement({required this.anchor, this.label});
  final Rect anchor;
  final Rect? label;
}

abstract final class AnnotationPlacer {
  /// A translation is only placed in real whitespace. Dense text keeps an
  /// interactive underline instead of painting over neighbouring glyphs.
  static AnnotationPlacement place({
    required Rect anchor,
    required Size labelSize,
    required Rect viewport,
    required List<Rect> textBoxes,
    required List<Rect> occupied,
    double gap = 4,
    double padding = 2,
  }) {
    final w = labelSize.width, h = labelSize.height;
    final candidates = <Rect>[
      Rect.fromLTWH(anchor.center.dx - w / 2, anchor.top - gap - h, w, h),
      Rect.fromLTWH(anchor.center.dx - w / 2, anchor.bottom + gap, w, h),
      Rect.fromLTWH(anchor.right + gap, anchor.center.dy - h / 2, w, h),
      Rect.fromLTWH(anchor.left - gap - w, anchor.center.dy - h / 2, w, h),
      Rect.fromLTWH(viewport.right - w - padding, anchor.top, w, h),
      Rect.fromLTWH(viewport.left + padding, anchor.top, w, h),
    ];
    for (final candidate in candidates) {
      if (!viewport.contains(candidate.topLeft) ||
          !viewport.contains(candidate.bottomRight)) {
        continue;
      }
      if (textBoxes.any((r) => r.inflate(padding).overlaps(candidate)) ||
          occupied.any((r) => r.inflate(padding).overlaps(candidate))) {
        continue;
      }
      return AnnotationPlacement(anchor: anchor, label: candidate);
    }
    return AnnotationPlacement(anchor: anchor);
  }
}
