import 'package:flutter/services.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';

class AssetBooksService {
  Future<List<Book>> loadBundledBooks({required VocabularyLevel defaultLevel}) async {
    // Dynamically scan bundled assets via AssetManifest (works cross-platform).
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest
          .listAssets()
          .where((k) => k.startsWith('assets/books/'))
          .where((k) {
            final lower = k.toLowerCase();
            return lower.endsWith('.txt') || lower.endsWith('.epub');
          })
          .toList()
        ..sort();

      return keys
          .map((path) => Book.fromAsset(path, defaultLevel: defaultLevel))
          .toList(growable: false);
    } catch (_) {
      return const <Book>[];
    }
  }
}
