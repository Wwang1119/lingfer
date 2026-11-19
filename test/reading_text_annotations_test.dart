import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lingfer/features/companion/lingfer_theme.dart';
import 'package:lingfer/models/translation_mode.dart';
import 'package:lingfer/services/ai_translation_service.dart';
import 'package:lingfer/services/reader_text_anchor.dart';
import 'package:lingfer/widgets/reading_text.dart';

void main() {
  Future<TextSpan> showText(
    WidgetTester tester,
    String text,
    List<ReaderAnnotationSpan> annotations,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ReadingText(
            chunkText: text,
            annotations: annotations,
            accentColor: LingferColors.accent,
            fontSize: 18,
            baseColor: LingferColors.ink,
          ),
        ),
      ),
    );
    return tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
  }

  testWidgets(
    'Explicitly empty annotations keep original English parentheses in body style',
    (tester) async {
      const source = 'Alice (an original English aside) continued reading.';
      final span = await showText(tester, source, const []);
      expect(span.toPlainText(), source);
      expect(span.style!.color, LingferColors.ink);
      expect(span.style!.fontSize, 18);
      expect(
        span.children!.whereType<TextSpan>().every(
          (child) => child.style == null,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Only newly generated Chinese gloss contents get annotation style',
    (tester) async {
      const source = 'Alice (an original English aside) felt curious.';
      final annotations = <ReaderAnnotationSpan>[];
      final text = AiTranslationService.applyVocabReplacements(
        source,
        {'curious': '好奇的'},
        mode: TranslationMode.enToZh,
        onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
          annotations.add(
            ReaderAnnotationSpan(
              sourceOffset: sourceOffset,
              renderedStart: renderedStart,
              renderedEnd: renderedEnd,
            ),
          );
        },
      );
      final root = await showText(tester, text, annotations);
      expect(
        root.toPlainText(),
        source.replaceFirst('curious', 'curious(好奇的)'),
      );
      final coloured = root.children!
          .whereType<TextSpan>()
          .where((span) => span.style != null)
          .toList();
      expect(coloured, hasLength(1));
      expect(coloured.single.text, '好奇的');
      expect(coloured.single.style!.color, LingferColors.accent);
      expect(coloured.single.style!.fontSize, 16);
      expect(
        root.children!
            .whereType<TextSpan>()
            .where((span) => span.style == null)
            .map((span) => span.text)
            .join(),
        contains('(an original English aside)'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Page slices preserve every UTF-16 unit and continue explicit gloss colour',
    () {
      const source = 'A 😀 curious reader (original aside) paused.';
      final annotations = <ReaderAnnotationSpan>[];
      final text = AiTranslationService.applyVocabReplacements(
        source,
        {'curious': '好奇而专注的🧬', 'paused': '暂停'},
        mode: TranslationMode.enToZh,
        onAnnotation: (sourceOffset, renderedStart, renderedEnd) {
          annotations.add(
            ReaderAnnotationSpan(
              sourceOffset: sourceOffset,
              renderedStart: renderedStart,
              renderedEnd: renderedEnd,
            ),
          );
        },
      );
      const accent = TextStyle(color: LingferColors.accent, fontSize: 16);
      final cuts = [
        0,
        annotations.first.renderedStart + 3,
        annotations.first.renderedEnd - 3,
        text.indexOf('original aside') + 4,
        text.length,
      ];
      final pages = <String>[];
      for (var page = 0; page < cuts.length - 1; page++) {
        final start = cuts[page], end = cuts[page + 1];
        final spans = ReadingText.spansForAnnotations(
          text,
          start: start,
          end: end,
          annotations: annotations,
          accentStyle: accent,
        );
        final pageText = TextSpan(children: spans).toPlainText();
        expect(pageText, text.substring(start, end));
        pages.add(pageText);
        var offset = start;
        for (final span in spans) {
          for (var i = 0; i < span.text!.length; i++, offset++) {
            final isGloss = annotations.any(
              (annotation) =>
                  offset >= annotation.renderedStart + 1 &&
                  offset < annotation.renderedEnd - 1,
            );
            expect(
              span.style == accent,
              isGloss,
              reason: 'UTF-16 offset $offset',
            );
          }
        }
        expect(offset, end);
      }
      expect(pages.join(), text);
    },
  );
}
