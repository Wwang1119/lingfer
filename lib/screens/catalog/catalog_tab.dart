import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;

import '../../app/app_state.dart';
import '../../models/book.dart';
import '../../models/vocabulary_level.dart';
import '../reading/pdf_reader_page.dart';
import '../reading/reading_screen.dart';
import '../../widgets/lens_book_cover.dart';

class CatalogTab extends StatelessWidget {
  const CatalogTab({super.key});

  // Data-driven catalog for V2.0 Explore tab.
  static const List<Map<String, Object>> _catalog = [
    {
      'category': '中国名著',
      'books': [
        {
          'title': '我这一辈子',
          'author': '老舍',
          'assetPath': 'assets/books/wo_zhe_yi_bei_zi.epub',
          'coverAssetPath': 'assets/covers/wo_zhe_yi_bei_zi.jpg',
        },
        {
          'title': '茶馆',
          'author': '老舍',
          'assetPath': 'assets/books/cha_guan.epub',
          'coverAssetPath': 'assets/covers/cha_guan.jpg',
        },
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    const pageBg = Color(0xFFF6F4EE);

    return material.Scaffold(
      backgroundColor: pageBg,
      body: material.Material(
        color: pageBg,
        child: CupertinoPageScaffold(
          backgroundColor: pageBg,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: pageBg),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '探索',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: Color(0xFF1C1C1E),
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFCF6),
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(color: const Color(0x10000000)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '像 Apple Books 一样开始今天的阅读',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1C1C1E),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '从经典文本开始，加入书架后可直接进入语境翻译与精读模式。',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: Color(0xFF6E6E73),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: const [
                                    SizedBox(
                                      width: 54,
                                      height: 78,
                                      child: LensBookCover(
                                        seedText: '我这一辈子',
                                        coverAssetPath:
                                            'assets/covers/wo_zhe_yi_bei_zi.jpg',
                                        borderRadius: 16,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    SizedBox(
                                      width: 54,
                                      height: 78,
                                      child: LensBookCover(
                                        seedText: '茶馆',
                                        coverAssetPath: 'assets/covers/cha_guan.jpg',
                                        borderRadius: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Text(
                      '已加入书架 ${state.shelf.length} 本',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: _catalog.length,
                  itemBuilder: (context, sectionIndex) {
                    final section = _catalog[sectionIndex];
                    final title = section['category'];
                    final books = section['books'];
                    if (title is! String || books is! List) {
                      return const SizedBox.shrink();
                    }

                    return _ExploreSection(
                      title: title,
                      books: books,
                      onBookPressed: (bookMap) => _openBookFromMap(
                        context,
                        state,
                        bookMap,
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBookFromMap(
    BuildContext context,
    AppState state,
    Object raw,
  ) async {
    if (raw is! Map) return;
    final title = raw['title'];
    final author = raw['author'];
    final assetPath = raw['assetPath'];
    if (title is! String || author is! String || assetPath is! String) return;

    final book = Book(
      title: title,
      author: author,
      defaultLevel: VocabularyLevel.cet4,
      source: BookSource.asset,
      locator: assetPath,
    );

    await state.addToShelf(book);
    if (!context.mounted) return;

    // Immersive reading: cover the entire tab scaffold.
    final lower = assetPath.toLowerCase();
    if (lower.endsWith('.pdf')) {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute<void>(
          builder: (_) => PdfReaderPage(book: book),
        ),
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => ReadingScreen(book: book),
      ),
    );
  }
}

class _ExploreSection extends StatelessWidget {
  const _ExploreSection({
    required this.title,
    required this.books,
    required this.onBookPressed,
  });

  final String title;
  final List books;
  final ValueChanged<Object> onBookPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${books.length} 本公版精选',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 264,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: books.length,
              itemBuilder: (context, index) {
                final item = books[index];
                if (item is! Map) return const SizedBox.shrink();
                final t = item['title'];
                final a = item['author'];
                final c = item['coverAssetPath'];
                if (t is! String || a is! String) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding:
                      EdgeInsets.only(right: index == books.length - 1 ? 0 : 18),
                  child: _ExploreBookCard(
                    title: t,
                    author: a,
                    coverAssetPath: c is String ? c : null,
                    onPressed: () => onBookPressed(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreBookCard extends StatelessWidget {
  const _ExploreBookCard({
    required this.title,
    required this.author,
    required this.coverAssetPath,
    required this.onPressed,
  });

  final String title;
  final String author;
  final String? coverAssetPath;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const coverRadius = 20.0;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: SizedBox(
        width: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(coverRadius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 40,
                    offset: Offset(0, 22),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: AspectRatio(
                  aspectRatio: 0.70,
                  child: LensBookCover(
                    seedText: title,
                    coverAssetPath: coverAssetPath,
                    borderRadius: coverRadius,
                    enableShadow: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
