import 'package:flutter/cupertino.dart';

import '../models/book.dart';
import 'lens_book_cover.dart';

class BookShelfCard extends StatelessWidget {
  const BookShelfCard({
    super.key,
    required this.book,
    required this.progressTopChunk,
    required this.onPressed,
    this.onLongPress,
  });

  final Book book;
  final int progressTopChunk;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    const cardRadius = 20.0;
    return GestureDetector(
      onTap: onPressed,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: const Color(0x11000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 34,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 82,
              child: _MiniCover(book: book),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6E73),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          book.level.label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (progressTopChunk > 0)
                        Text(
                          '进度：第 $progressTopChunk 段',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 18,
              color: Color(0xFFAEAEB2),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    return LensBookCover(
      seedText: book.title,
      coverAssetPath: book.coverAssetPath,
      borderRadius: 16,
      enableShadow: false,
    );
  }
}
