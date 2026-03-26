import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../models/book.dart';

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book, required this.onPressed});

  final Book book;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const cardRadius = 16.0;

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cardRadius),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(color: const Color(0x11000000)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CoverPlaceholder(title: book.title),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E6E73),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final seed = title.hashCode;
    final hue = (seed % 360).toDouble();
    final c1 = HSVColor.fromAHSV(1, hue, 0.25, 0.98).toColor();
    final c2 = HSVColor.fromAHSV(1, (hue + 28) % 360, 0.18, 0.92).toColor();

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c2],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: const Color(0x10FFFFFF)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Text(
            _monogram(title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFF1C1C1E),
            ),
          ),
        ),
      ],
    );
  }

  String _monogram(String t) {
    final s = t.trim();
    if (s.isEmpty) return 'L';
    return s.characters.take(2).toString().toUpperCase();
  }
}
