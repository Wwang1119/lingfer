import 'package:flutter/widgets.dart';

class ReadingText extends StatelessWidget {
  const ReadingText({
    super.key,
    required this.chunkText,
    required this.accentColor,
    required this.fontSize,
    required this.baseColor,
  });

  final String chunkText;
  final Color accentColor;
  final double fontSize;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    const textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );

    final baseStyle = TextStyle(
      color: baseColor,
      fontSize: fontSize,
      height: 1.6,
      letterSpacing: 0.5,
      decoration: TextDecoration.none,
    );
    final accentStyle = TextStyle(
      color: accentColor,
      fontSize: (fontSize - 2).clamp(12, 30),
      height: 1.6,
      letterSpacing: 0.5,
      decoration: TextDecoration.none,
    );

    final strut = StrutStyle(
      fontSize: fontSize,
      height: 1.6,
      forceStrutHeight: true,
    );

    final spans = <TextSpan>[];
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
