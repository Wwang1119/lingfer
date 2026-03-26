import 'dart:io';

import 'vocabulary_level.dart';

enum BookSource { localFile, asset, mock }

class Book {
  const Book({
    required this.title,
    required this.author,
    required this.defaultLevel,
    required this.source,
    required this.locator,
    this.coverAssetPath,
    this.blurb,
  });

  final String title;
  final String author;
  final VocabularyLevel defaultLevel;
  final BookSource source;

  // For local files: absolute path. For assets: asset path. For mock: mock URL.
  final String locator;
  final String? coverAssetPath;
  final String? blurb;

  // Alias for readability: product requirements call this "level".
  VocabularyLevel get level => defaultLevel;

  String get id => stableKey;

  Book withDefaultLevel(VocabularyLevel next) => Book(
        title: title,
        author: author,
        defaultLevel: next,
        source: source,
        locator: locator,
        coverAssetPath: coverAssetPath,
        blurb: blurb,
      );

  String get stableKey {
    // Composite ID (title + level) to prevent shelf duplication and to ensure
    // progress/caches are stable even if local file paths change (sandbox copy).
    final normalizedTitle = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    final levelKey = defaultLevel.label.trim().replaceAll(RegExp(r'\s+'), ' ');
    return '${normalizedTitle}_$levelKey';
  }

  String get subtitle {
    switch (source) {
      case BookSource.localFile:
        return '本地导入';
      case BookSource.asset:
        return '公版书';
      case BookSource.mock:
        return '占位';
    }
  }

  static Book fromLocalPath(String path, {required VocabularyLevel defaultLevel}) {
    final name = path.split(Platform.pathSeparator).last;
    final title =
        name.replaceAll(RegExp(r'\.(txt|epub|docx|pdf)$', caseSensitive: false), '');
    return Book(
      title: title.isEmpty ? name : title,
      author: '本地导入',
      defaultLevel: defaultLevel,
      source: BookSource.localFile,
      locator: path,
    );
  }

  static Book fromAsset(String assetPath, {required VocabularyLevel defaultLevel}) {
    final name = assetPath.split('/').last;
    final title = name.replaceAll(
      RegExp(r'\.(txt|epub|pdf)$', caseSensitive: false),
      '',
    );
    return Book(
      title: title.isEmpty ? name : title,
      author: '公版书',
      defaultLevel: defaultLevel,
      source: BookSource.asset,
      locator: assetPath,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'author': author,
        // Persist both keys for backward compatibility with older builds.
        'defaultLevel': defaultLevel.name,
        'level': defaultLevel.name,
        'source': source.name,
        'locator': locator,
        'coverAssetPath': coverAssetPath,
        'blurb': blurb,
      };

  static Book? fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final author = json['author'];
    final defaultLevel = (json['level'] is String) ? json['level'] : json['defaultLevel'];
    final source = json['source'];
    final locator = json['locator'];
    if (title is! String ||
        author is! String ||
        defaultLevel is! String ||
        source is! String ||
        locator is! String) {
      return null;
    }

    VocabularyLevel? level;
    for (final l in VocabularyLevel.values) {
      if (l.name == defaultLevel) {
        level = l;
        break;
      }
    }
    BookSource? src;
    for (final s in BookSource.values) {
      if (s.name == source) {
        src = s;
        break;
      }
    }
    if (level == null || src == null) return null;

    final cover = json['coverAssetPath'];
    final blurb = json['blurb'];
    return Book(
      title: title,
      author: author,
      defaultLevel: level,
      source: src,
      locator: locator,
      coverAssetPath: cover is String ? cover : null,
      blurb: blurb is String ? blurb : null,
    );
  }
}
