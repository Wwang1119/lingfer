import 'package:flutter/services.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';

class BundledPublicDomainBook {
  const BundledPublicDomainBook({
    required this.title,
    required this.originalTitle,
    required this.author,
    required this.assetPath,
    required this.publicationYear,
    required this.sourceUrl,
  });

  final String title;
  final String originalTitle;
  final String author;
  final String assetPath;
  final int publicationYear;
  final String sourceUrl;

  Book toBook(VocabularyLevel level) => Book(
    title: title,
    author: author,
    defaultLevel: level,
    source: BookSource.asset,
    locator: assetPath,
    blurb: '$originalTitle · 英文原著全本',
  );
}

class AssetBooksService {
  /// Only app-bundled, reviewed titles. This never enumerates device files.
  static const publicDomainCatalog = <BundledPublicDomainBook>[
    BundledPublicDomainBook(
      title: '爱丽丝梦游仙境',
      originalTitle: 'Alice’s Adventures in Wonderland',
      author: 'Lewis Carroll',
      assetPath: 'assets/books/alice_in_wonderland.txt',
      publicationYear: 1865,
      sourceUrl: 'https://www.gutenberg.org/ebooks/11',
    ),
    BundledPublicDomainBook(
      title: '福尔摩斯历险记',
      originalTitle: 'The Adventures of Sherlock Holmes',
      author: 'Arthur Conan Doyle',
      assetPath: 'assets/books/sherlock_holmes_adventures.txt',
      publicationYear: 1892,
      sourceUrl: 'https://www.gutenberg.org/ebooks/1661',
    ),
    BundledPublicDomainBook(
      title: '傲慢与偏见',
      originalTitle: 'Pride and Prejudice',
      author: 'Jane Austen',
      assetPath: 'assets/books/pride_and_prejudice.txt',
      publicationYear: 1813,
      sourceUrl: 'https://www.gutenberg.org/ebooks/1342',
    ),
  ];

  Future<List<Book>> loadBundledBooks({
    required VocabularyLevel defaultLevel,
  }) async {
    // Dynamically scan bundled assets via AssetManifest (works cross-platform).
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys =
          manifest
              .listAssets()
              .where((k) => k.startsWith('assets/books/'))
              .where((k) {
                final lower = k.toLowerCase();
                return lower.endsWith('.txt') || lower.endsWith('.epub');
              })
              .toList()
            ..sort();

      final known = {
        for (final entry in publicDomainCatalog) entry.assetPath: entry,
      };
      return keys
          .map(
            (path) =>
                known[path]?.toBook(defaultLevel) ??
                Book.fromAsset(path, defaultLevel: defaultLevel),
          )
          .toList(growable: false);
    } catch (_) {
      return const <Book>[];
    }
  }
}
