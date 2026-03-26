import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

class LiquidCupertinoTextSelectionControls extends CupertinoTextSelectionControls {
  LiquidCupertinoTextSelectionControls();

  static const double _kKnobRadius = 8.5;
  static const double _kBarHalfWidth = 2.4;
  static const double _kOverlap = 1.5;

  @override
  Size getHandleSize(double textLineHeight) {
    final h = textLineHeight + _kKnobRadius * 2 - _kOverlap;
    // Wider handle => larger gesture hitbox (easier to drag precisely).
    return Size(_kKnobRadius * 2 + 6, h);
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final desiredSize = getHandleSize(textLineHeight);
    final baseColor = CupertinoTheme.of(context).selectionHandleColor;
    final handle = SizedBox.fromSize(
      size: desiredSize,
      child: CustomPaint(
        painter: _LiquidHandlePainter(baseColor),
      ),
    );

    switch (type) {
      case TextSelectionHandleType.left:
        return handle;
      case TextSelectionHandleType.right:
        return Transform(
          transform: Matrix4.identity()
            ..translateByDouble(desiredSize.width / 2, desiredSize.height / 2, 0, 1)
            ..rotateZ(math.pi)
            ..translateByDouble(-desiredSize.width / 2, -desiredSize.height / 2, 0, 1),
          child: handle,
        );
      case TextSelectionHandleType.collapsed:
        // Keep the larger hitbox, but do not paint an extra caret here.
        return SizedBox.fromSize(size: desiredSize);
    }
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final handleSize = getHandleSize(textLineHeight);
    switch (type) {
      case TextSelectionHandleType.left:
        return Offset(handleSize.width / 2, handleSize.height);
      case TextSelectionHandleType.right:
        return Offset(handleSize.width / 2, handleSize.height - 2 * _kKnobRadius + _kOverlap);
      case TextSelectionHandleType.collapsed:
        return Offset(handleSize.width / 2, textLineHeight + (handleSize.height - textLineHeight) / 2);
    }
  }
}

class _LiquidHandlePainter extends CustomPainter {
  const _LiquidHandlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const knobR = LiquidCupertinoTextSelectionControls._kKnobRadius;
    const barHalf = LiquidCupertinoTextSelectionControls._kBarHalfWidth;
    const overlap = LiquidCupertinoTextSelectionControls._kOverlap;

    final cx = size.width / 2;
    final circle = Rect.fromCircle(
      center: Offset(cx, knobR),
      radius: knobR,
    );
    final barTop = 2 * knobR - overlap;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - barHalf, barTop, cx + barHalf, size.height),
      const Radius.circular(999),
    );

    final path = Path()
      ..addOval(circle)
      ..addRRect(bar);

    // A tiny shadow makes it feel like "liquid glass" floating above text.
    canvas.drawShadow(path, const Color(0x33000000), 2.2, true);

    final paint = Paint()..color = color.withValues(alpha: 0.86);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiquidHandlePainter oldDelegate) => oldDelegate.color != color;
}

final TextSelectionControls liquidCupertinoTextSelectionControls =
    LiquidCupertinoTextSelectionControls();
