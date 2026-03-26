class CatalogSection {
  const CatalogSection({required this.title, required this.books});

  final String title;
  final List<CatalogBook> books;
}

class CatalogBook {
  const CatalogBook({
    required this.title,
    required this.author,
    required this.blurb,
    required this.assetBookPath,
    required this.assetCoverPath,
    required this.section,
  });

  final String title;
  final String author;
  final String blurb;
  final String assetBookPath;
  final String assetCoverPath;
  final String section;
}

const catalogSections = <CatalogSection>[
  CatalogSection(
    title: '四级进阶',
    books: [
      CatalogBook(
        title: '傲慢与偏见',
        author: 'Jane Austen',
        blurb: '经典爱情与阶级讽刺，适合精读与词汇标注练习。',
        assetBookPath: 'assets/books/傲慢与偏见.epub',
        assetCoverPath: 'assets/covers/pride_and_prejudice.jpg',
        section: '四级进阶',
      ),
    ],
  ),
  CatalogSection(
    title: '世界名著',
    books: [
      CatalogBook(
        title: '老人与海',
        author: 'Ernest Hemingway',
        blurb: '短篇体量，句式清晰，非常适合作为阅读训练起点。',
        assetBookPath: 'assets/books/老人与海.epub',
        assetCoverPath: 'assets/covers/the_old_man_and_the_sea.jpg',
        section: '世界名著',
      ),
    ],
  ),
  CatalogSection(
    title: '短篇精选',
    books: [
      CatalogBook(
        title: 'The Gift of the Magi',
        author: 'O. Henry',
        blurb: '反转结尾的温柔短篇，适合做段落级理解与复盘。',
        assetBookPath: 'assets/books/gift_of_the_magi.txt',
        assetCoverPath: 'assets/covers/gift_of_the_magi.jpg',
        section: '短篇精选',
      ),
    ],
  ),
];

