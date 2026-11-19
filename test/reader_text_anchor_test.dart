import 'package:flutter_test/flutter_test.dart';

import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/services/ai_translation_service.dart';
import 'package:lingfer/services/reader_text_anchor.dart';

({String text, List<ReaderAnnotationSpan> spans}) annotate(
  String source,
  Map<String, String> vocabulary, {
  TranslationMode mode = TranslationMode.enToZh,
}) {
  final spans = <ReaderAnnotationSpan>[];
  final text = AiTranslationService.applyVocabReplacements(
    source,
    vocabulary,
    mode: mode,
    onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
      spans.add(
        ReaderAnnotationSpan(
          sourceOffset: sourceOffset,
          renderedStart: renderedStart,
          renderedEnd: renderedEnd,
        ),
      );
    },
  );
  return (text: text, spans: spans);
}

void main() {
  test(
    'Original parentheses retain exact positions through generated glosses',
    () {
      const source = 'An occasional (original aside) visitor arrives.';
      final result = annotate(source, {'occasional': '偶尔的', 'visitor': '访客'});
      expect(result.spans, hasLength(2));
      final originalOffset = source.indexOf('original aside');
      final renderedOffset = ReaderTextAnchor.renderedOffset(
        originalOffset,
        result.spans,
      );
      expect(
        result.text.substring(renderedOffset),
        startsWith('original aside)'),
      );
      expect(
        ReaderTextAnchor.sourceOffset(renderedOffset, result.spans),
        originalOffset,
      );
      for (var offset = 0; offset <= source.length; offset++) {
        expect(
          ReaderTextAnchor.sourceOffset(
            ReaderTextAnchor.renderedOffset(offset, result.spans),
            result.spans,
          ),
          offset,
        );
      }
    },
  );

  test(
    'Positions inside a gloss and its edges resolve to the source word end',
    () {
      const source = 'Context gives meaning.';
      final result = annotate(source, {'context': '语境', 'meaning': '含义'});
      for (final span in result.spans) {
        for (
          var offset = span.renderedStart;
          offset <= span.renderedEnd;
          offset++
        ) {
          expect(
            ReaderTextAnchor.sourceOffset(offset, result.spans),
            span.sourceOffset,
          );
        }
        expect(
          ReaderTextAnchor.renderedOffset(span.sourceOffset, result.spans),
          span.renderedStart,
        );
      }
    },
  );

  test('Changing gloss lengths preserves the same original reading anchor', () {
    const source = 'An occasional visitor observes the garden.';
    final before = annotate(source, {'occasional': '偶尔的', 'visitor': '访客'});
    final after = annotate(source, {
      'occasional': '偶尔发生而非经常发生的',
      'visitor': '来访者或访问者',
      'observes': '观察',
    });
    final oldPosition = before.text.indexOf('garden');
    final originalPosition = ReaderTextAnchor.sourceOffset(
      oldPosition,
      before.spans,
    );
    expect(originalPosition, source.indexOf('garden'));
    final newPosition = ReaderTextAnchor.renderedOffset(
      originalPosition,
      after.spans,
    );
    expect(after.text.substring(newPosition), startsWith('garden.'));
    expect(newPosition, isNot(oldPosition));
  });

  test(
    'Removing and restoring annotations across modes keeps UTF-16 anchors',
    () {
      const source = 'A 😀 café (原文括号) welcomes a visitor to 阅读。';
      final before = annotate(source, {'café': '咖啡馆🧬', 'visitor': '访客'});
      final after = annotate(source, {
        '阅读': 'reading',
      }, mode: TranslationMode.zhToEn);
      final position = before.text.indexOf('welcomes');
      final originalPosition = ReaderTextAnchor.sourceOffset(
        position,
        before.spans,
      );
      expect(originalPosition, source.indexOf('welcomes'));
      expect(
        after.text.substring(
          ReaderTextAnchor.renderedOffset(originalPosition, after.spans),
        ),
        startsWith('welcomes'),
      );
      final noAnnotations = ReaderTextAnchor.renderedOffset(
        originalPosition,
        const [],
      );
      expect(source.substring(noAnnotations), startsWith('welcomes'));
      final restored = ReaderTextAnchor.renderedOffset(
        originalPosition,
        before.spans,
      );
      expect(restored, position);
    },
  );
}
