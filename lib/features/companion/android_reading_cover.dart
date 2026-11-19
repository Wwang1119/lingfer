import 'package:flutter/material.dart';

import 'lingfer_theme.dart';

/// The Android screen-reading entry keeps its launch settings beside the action.
class AndroidReadingCover extends StatelessWidget {
  const AndroidReadingCover({
    super.key,
    required this.title,
    required this.description,
    required this.running,
    required this.action,
    required this.preferences,
  });

  final String title;
  final String description;
  final bool running;
  final Widget action;
  final Widget preferences;

  static const ink = Color(0xFF294B57);
  static const paper = Color(0xFFF6F5EC);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingferColors.paper,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFD9E0DD)),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ink, Color(0xFF355C63)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final showDrawing =
                          bounds.maxWidth >= 235 &&
                          MediaQuery.textScalerOf(context).scale(16) <= 20;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (running)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 5),
                                    child: Text(
                                      '会话中',
                                      style: TextStyle(
                                        color: paper,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                Text(
                                  title,
                                  style: LingferType.heading.copyWith(
                                    color: paper,
                                    fontSize: 28,
                                    letterSpacing: .5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    color: Color(0xFFE1EBE7),
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showDrawing) ...[
                            const SizedBox(width: 14),
                            const CustomPaint(
                              size: Size(78, 80),
                              painter: _AnnotatedPagePainter(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  action,
                ],
              ),
            ),
          ),
          preferences,
        ],
      ),
    );
  }
}

/// A paper leaf with a marked passage and a margin note.
class _AnnotatedPagePainter extends CustomPainter {
  const _AnnotatedPagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 78, size.height / 80);
    canvas.rotate(-.075);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x777FA2A2);
    RRect leaf(double x, double y) => RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, 44, 57),
      const Radius.circular(4),
    );
    canvas.drawRRect(leaf(24, 18), pen);
    canvas.drawRRect(leaf(20, 14), Paint()..color = const Color(0xFF365A61));
    canvas.drawRRect(leaf(20, 14), pen);
    canvas.drawRRect(leaf(15, 10), Paint()..color = const Color(0xFFE6E7D8));
    final ruling = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6
      ..color = const Color(0xFF91A19C);
    for (final y in [22.0, 28.0, 34.0, 48.0, 54.0]) {
      canvas.drawLine(
        Offset(22, y),
        Offset(y == 34 || y == 54 ? 40 : 50, y),
        ruling,
      );
    }
    final amber = Paint()
      ..color = const Color(0xFF9C6C3F)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(22, 36), const Offset(40, 36), amber);
    final note = RRect.fromRectAndRadius(
      const Rect.fromLTWH(42, 38, 29, 14),
      const Radius.circular(3),
    );
    canvas.drawRRect(note, Paint()..color = const Color(0xFFF3DFB7));
    ruling.color = const Color(0xFF866B45);
    canvas.drawLine(const Offset(48, 45), const Offset(64, 45), ruling);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnnotatedPagePainter oldDelegate) => false;
}
