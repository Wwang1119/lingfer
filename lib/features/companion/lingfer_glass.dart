import 'dart:ui';

import 'package:flutter/material.dart';

import 'lingfer_theme.dart';

/// A bounded material for floating controls, never a filter over reading text.
class LingferGlassSurface extends StatelessWidget {
  const LingferGlassSurface({
    super.key,
    required this.child,
    this.radius = 30,
    this.borderRadius,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final BorderRadius? borderRadius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final solid =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final corners = borderRadius ?? BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: solid
              ? const [Colors.white, Colors.white]
              : const [Color(0xF5FFFFFF), Color(0xCFF9FAF8), Color(0xEAF7F8F5)],
          stops: solid ? const [0, 1] : const [0, .55, 1],
        ),
        border: Border.all(
          color: solid ? LingferColors.muted : const Color(0xE6FFFFFF),
          width: solid ? 1 : .8,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x0F19213D),
                  blurRadius: 26,
                  offset: Offset(0, 9),
                ),
                BoxShadow(
                  color: Color(0x0619213D),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: solid
            ? content
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: content,
              ),
      ),
    );
  }
}
