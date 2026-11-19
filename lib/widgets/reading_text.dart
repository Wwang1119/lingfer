import 'package:flutter/widgets.dart';

import '../services/reader_text_anchor.dart';
import 'book_reader_presentation.dart';

class ReadingText extends StatelessWidget {
  const ReadingText({
    super.key,
    required this.chunkText,
    required this.accentColor,
    required this.fontSize,
    required this.baseColor,
    this.annotations,
  });

  final String chunkText;
  final Color accentColor;
  final double fontSize;
  final Color baseColor;

  /// Null preserves legacy parsing. An empty list means all text is source prose.
  final List<ReaderAnnotationSpan>? annotations;

  /// Styles only the contents of explicitly inserted glosses in a UTF-16 slice.
  /// The supplied spans retain their full-text offsets even when a page starts
  /// inside a gloss; original parentheses and new outer brackets remain prose.
  static List<TextSpan> spansForAnnotations(
    String text, {
    required int start,
    required int end,
    required List<ReaderAnnotationSpan> annotations,
    required TextStyle accentStyle,
  }) {
    final sliceStart = start.clamp(0, text.length);
    final sliceEnd = end.clamp(sliceStart, text.length);
    final spans = <TextSpan>[];
    var cursor = sliceStart;
    for (final annotation in annotations) {
      final innerStart = (annotation.renderedStart + 1).clamp(cursor, sliceEnd);
      final innerEnd = (annotation.renderedEnd - 1).clamp(innerStart, sliceEnd);
      if (innerEnd <= innerStart) continue;
      if (cursor < innerStart) {
        spans.add(TextSpan(text: text.substring(cursor, innerStart)));
      }
      spans.add(
        TextSpan(
          text: text.substring(innerStart, innerEnd),
          style: accentStyle,
        ),
      );
      cursor = innerEnd;
      if (cursor == sliceEnd) break;
    }
    if (cursor < sliceEnd) {
      spans.add(TextSpan(text: text.substring(cursor, sliceEnd)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );

    final baseStyle = BookReaderTypography.body(size: fontSize, ink: baseColor);
    // Keep accepting cached level colours, while presenting all annotations
    // with the same readable ink in both horizontal and vertical readers.
    final accentStyle = BookReaderTypography.annotation(
      size: fontSize,
      ink: baseColor,
    );

    final strut = StrutStyle(
      fontSize: fontSize,
      height: 1.6,
      forceStrutHeight: true,
    );

    final spans = <TextSpan>[];
    final explicitAnnotations = annotations;
    if (explicitAnnotations != null) {
      spans.addAll(
        spansForAnnotations(
          chunkText,
          start: 0,
          end: chunkText.length,
          annotations: explicitAnnotations,
          accentStyle: accentStyle,
        ),
      );
    } else {
      var i = 0;
      while (i < chunkText.length) {
        final open = chunkText.indexOf('(', i);
        if (open == -1) {
          spans.add(TextSpan(text: chunkText.substring(i)));
          break;
        }
        final close = chunkText.indexOf(')', open + 1);
        if (close == -1) {
          spans.add(TextSpan(text: chunkText.substring(i)));
          break;
        }

        if (open > i) {
          spans.add(TextSpan(text: chunkText.substring(i, open)));
        }
        spans.add(const TextSpan(text: '('));
        final inside = chunkText.substring(open + 1, close);
        spans.add(TextSpan(text: inside, style: accentStyle));
        spans.add(const TextSpan(text: ')'));
        i = close + 1;
      }
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textScaler: MediaQuery.textScalerOf(context),
      textAlign: TextAlign.start,
      overflow: TextOverflow.clip,
      strutStyle: strut,
      textHeightBehavior: textHeightBehavior,
    );
  }
}
