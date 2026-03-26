import 'package:flutter/cupertino.dart';

import 'lens_book_cover.dart';

class CatalogBookCard extends StatelessWidget {
  const CatalogBookCard({
    super.key,
    required this.title,
    required this.author,
    required this.coverAssetPath,
    required this.onPressed,
  });

  final String title;
  final String author;
  final String coverAssetPath;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.7,
              child: LensBookCover(
                seedText: title,
                coverAssetPath: coverAssetPath,
                borderRadius: 16,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              author,
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
    );
  }
}
