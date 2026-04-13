import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

class LiquidCupertinoTextSelectionControls extends CupertinoTextSelectionControls {
  LiquidCupertinoTextSelectionControls();

  static const double _kKnobRadius = 8.5;
  static const double _kBarHalfWidth = 2.35;
  static const double _kOverlap = 1.1;
  static const double _kHorizontalHitPadding = 16;
  static const double _kVerticalHitPadding = 12;

  @override
  Size getHandleSize(double textLineHeight) {
    final visibleHeight = textLineHeight + _kKnobRadius * 2 - _kOverlap;
    return Size(
      _kKnobRadius * 2 + _kHorizontalHitPadding * 2,
      visibleHeight + _kVerticalHitPadding * 2,
    );
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
    final visibleSize = Size(
      _kKnobRadius * 2 + 2,
      textLineHeight + _kKnobRadius * 2 - _kOverlap,
    );
    final paintedHandle = SizedBox.fromSize(
      size: visibleSize,
      child: CustomPaint(
        painter: _LiquidHandlePainter(baseColor),
      ),
    );
    final handle = SizedBox.fromSize(
      size: desiredSize,
      child: Center(
        child: paintedHandle,
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
    final visibleHeight = textLineHeight + _kKnobRadius * 2 - _kOverlap;
    final topInset = (handleSize.height - visibleHeight) / 2;
    switch (type) {
      case TextSelectionHandleType.left:
        return Offset(handleSize.width / 2, topInset + visibleHeight);
      case TextSelectionHandleType.right:
        return Offset(
          handleSize.width / 2,
          topInset + textLineHeight,
        );
      case TextSelectionHandleType.collapsed:
        return Offset(
          handleSize.width / 2,
          textLineHeight + (handleSize.height - textLineHeight) / 2,
        );
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
    canvas.drawShadow(path, const Color(0x24000000), 2.6, true);

    final paint = Paint()..color = color.withValues(alpha: 0.92);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiquidHandlePainter oldDelegate) => oldDelegate.color != color;
}

final TextSelectionControls liquidCupertinoTextSelectionControls =
    LiquidCupertinoTextSelectionControls();
