part of 'companion_shell.dart';

class _AndroidEmptyLibrary extends StatelessWidget {
  const _AndroidEmptyLibrary({
    required this.onImport,
    required this.onReadSample,
  });

  final VoidCallback? onImport;
  final VoidCallback onReadSample;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.folder_open_rounded,
              color: LingferColors.accent,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '还没有本地资料',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '支持 TXT、EPUB、PDF 和 DOCX',
          style: TextStyle(fontSize: 13, color: LingferColors.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(backgroundColor: LingferColors.tint),
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('选择文件'),
            ),
            TextButton(onPressed: onReadSample, child: const Text('试读一段')),
          ],
        ),
      ],
    ),
  );
}

class _AndroidFileMark extends StatelessWidget {
  const _AndroidFileMark({required this.format});
  final String format;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$format 文件',
    excludeSemantics: true,
    child: Container(
      width: 42,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: LingferColors.tint,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(8),
        ),
        border: const Border(
          left: BorderSide(color: LingferColors.accent, width: 3),
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          format,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: LingferColors.accent,
          ),
        ),
      ),
    ),
  );
}

class _AndroidBookShelf extends StatelessWidget {
  const _AndroidBookShelf({required this.onOpen});

  final ValueChanged<BundledPublicDomainBook> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entries = AssetBooksService.publicDomainCatalog;
      if (entries.isEmpty || constraints.maxWidth < 1) {
        return const SizedBox.shrink();
      }
      final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
      const spacing = 12.0;
      final columnWidth =
          (constraints.maxWidth - spacing * (entries.length - 1)) /
          entries.length;
      final stacked = columnWidth < 88 * textScale;
      final horizontal = stacked || columnWidth >= 198 * textScale;
      return Wrap(
        spacing: spacing,
        runSpacing: 10,
        children: [
          for (final entry in entries)
            SizedBox(
              width: stacked ? constraints.maxWidth : columnWidth,
              child: _AndroidBookTile(
                key: ValueKey('bundled-book-${entry.assetPath}'),
                book: entry,
                horizontal: horizontal,
                onPressed: () => onOpen(entry),
              ),
            ),
        ],
      );
    },
  );
}

class _AndroidBookTile extends StatelessWidget {
  const _AndroidBookTile({
    super.key,
    required this.book,
    required this.horizontal,
    required this.onPressed,
  });
  final BundledPublicDomainBook book;
  final bool horizontal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cover = _ClothBookCover(book: book);
    final caption = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: LingferType.interfaceHeading.copyWith(
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          book.author,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: LingferColors.muted,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label:
          '${book.title}，${book.originalTitle}，${book.author}，${book.publicationYear} 年',
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: horizontal
                ? Row(
                    children: [
                      SizedBox(width: 60, child: cover),
                      const SizedBox(width: 14),
                      Expanded(child: caption),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [cover, const SizedBox(height: 10), caption],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Flat jacket artwork uses the actual edition's title and publication year.
/// Accessible text is supplied by the tile, separately from the book lettering.
class _ClothBookCover extends StatelessWidget {
  const _ClothBookCover({required this.book});
  final BundledPublicDomainBook book;

  @override
  Widget build(BuildContext context) {
    final cloth = switch (book.assetPath) {
      'assets/books/alice_in_wonderland.txt' => const Color(0xFF345851),
      'assets/books/sherlock_holmes_adventures.txt' => const Color(0xFF424C60),
      'assets/books/pride_and_prejudice.txt' => const Color(0xFF82594F),
      _ => LingferColors.accent,
    };
    const foil = Color(0xFFF4E6C6);
    return AspectRatio(
      aspectRatio: .75,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cloth,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(3),
            right: Radius.circular(7),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x210F231F),
              offset: Offset(1, 3),
              blurRadius: 5,
            ),
          ],
        ),
        child: FittedBox(
          child: SizedBox(
            width: 102,
            height: 136,
            child: Stack(
              children: [
                const Positioned.fill(
                  left: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0x38000000), width: 1),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  left: 11,
                  right: 6,
                  top: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: foil.withValues(alpha: .47),
                        width: .65,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 3,
                              children: [
                                for (final word in book.originalTitle.split(
                                  ' ',
                                ))
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      word,
                                      softWrap: false,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(
                                        fontFamily: 'serif',
                                        color: foil,
                                        fontSize: 12,
                                        height: 1.12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 16,
                          child: Divider(color: foil, height: 6, thickness: .6),
                        ),
                        Text(
                          '${book.publicationYear}',
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: foil,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
