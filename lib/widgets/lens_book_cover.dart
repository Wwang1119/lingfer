import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// A unified, Apple-ish book cover widget.
///
/// - Loads an asset cover when available.
/// - Falls back to a subtle, texture-like placeholder (no big title text),
///   so the cover doesn't look like "a label slapped on a rectangle".
class LensBookCover extends StatelessWidget {
  const LensBookCover({
    super.key,
    required this.seedText,
    this.coverAssetPath,
    this.borderRadius = 18,
    this.enableShadow = true,
  });

  final String seedText;
  final String? coverAssetPath;
  final double borderRadius;
  final bool enableShadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final cover = ClipRRect(
      borderRadius: radius,
      child: coverAssetPath == null
          ? _Placeholder(seedText: seedText)
          : Image.asset(
              coverAssetPath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _Placeholder(seedText: seedText);
              },
            ),
    );

    if (!enableShadow) return cover;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 44,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: cover,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seedText});

  final String seedText;

  @override
  Widget build(BuildContext context) {
    final seed = seedText.trim().isEmpty ? 0 : seedText.hashCode;
    final hue = (seed % 360).toDouble();
    final c1 = HSVColor.fromAHSV(1, hue, 0.08, 0.96).toColor();
    final c2 = HSVColor.fromAHSV(1, (hue + 22) % 360, 0.07, 0.92).toColor();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c2],
            ),
          ),
        ),
        // A soft glassy wash.
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x10FFFFFF),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
              ),
            ),
          ),
        ),
        // A faint "spine" hint, like a real book.
        const Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x1A000000),
                  Color(0x06000000),
                  Color(0x14000000),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Icon(
            CupertinoIcons.book,
            size: 34,
            color: const Color(0xFF8E8E93).withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
