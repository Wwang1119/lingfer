import 'package:flutter/material.dart';
import '../companion_controller.dart';
import '../reading_controls.dart';
import '../vocabulary_engine.dart';
import 'annotated_image_reader.dart';
import 'ocr_document.dart';

/// The original SelectableText remains the hit-test target for selection.
/// Only translation capsules intercept taps; underlines never block reading.
class AnchoredText extends StatelessWidget {
  const AnchoredText({
    super.key,
    required this.text,
    required this.hits,
    required this.style,
    required this.controller,
    required this.child,
  });
  final String text;
  final List<VocabularyHit> hits;
  final TextStyle style;
  final CompanionController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final obstacles = <Rect>[];
      for (final match in RegExp(r'\S+').allMatches(text)) {
        obstacles.addAll(
          painter
              .getBoxesForSelection(
                TextSelection(baseOffset: match.start, extentOffset: match.end),
              )
              .map((box) => box.toRect()),
        );
      }
      final occupied = <Rect>[];
      final anchors = <Rect>[];
      final labels = <Widget>[];
      for (final hit in hits.take(24)) {
        var start = hit.sourceStart ?? text.indexOf(hit.surface);
        var end = hit.sourceEnd ?? start + hit.surface.length;
        if (start < 0 ||
            end > text.length ||
            start >= end ||
            text.substring(start, end) != hit.surface) {
          start = text.indexOf(hit.surface);
          end = start + hit.surface.length;
        }
        if (start < 0 || end > text.length || start >= end) continue;
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        if (boxes.isEmpty) continue;
        final anchor = boxes.first.toRect();
        anchors.add(anchor);
        final caption = TextPainter(
          text: TextSpan(
            text: hit.shortTranslation,
            style: const TextStyle(fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: 150);
        final placement = AnnotationPlacer.place(
          anchor: anchor,
          labelSize: Size(caption.width + 16, 25),
          viewport: Rect.fromLTWH(0, 0, constraints.maxWidth, painter.height),
          textBoxes: obstacles,
          occupied: occupied,
        );
        if (placement.label case final rect?) {
          occupied.add(rect);
          labels.add(
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                onTap: () => showGlassWordDetail(context, controller, hit),
                child: GlassSurface(
                  radius: 12,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      hit.shortTranslation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF18324A),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Underlines(anchors)),
            ),
          ),
          ...labels,
        ],
      );
    },
  );
}

class _Underlines extends CustomPainter {
  const _Underlines(this.rects);
  final List<Rect> rects;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF007AFF).withValues(alpha: .65)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final rect in rects) {
      canvas.drawLine(
        Offset(rect.left, rect.bottom),
        Offset(rect.right, rect.bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Underlines oldDelegate) =>
      oldDelegate.rects != rects;
}
