import 'dart:io';

import 'vocabulary_level.dart';

enum BookSource { localFile, asset, mock }

const _bookTitleSuffixPattern =
    r'\.(txt|epub|docx|pdf|png|jpg|jpeg|heic|webp)$';

class Book {
  const Book({
    required this.title,
    required this.author,
    required this.defaultLevel,
    required this.source,
    required this.locator,
    this.isPinned = false,
    this.coverAssetPath,
    this.coverFilePath,
    this.blurb,
  });

  final String title;
  final String author;
  final VocabularyLevel defaultLevel;
  final BookSource source;

  // For local files: absolute path. For assets: asset path. For mock: mock URL.
  final String locator;
  final bool isPinned;
  final String? coverAssetPath;
  final String? coverFilePath;
  final String? blurb;

  // Alias for readability: product requirements call this "level".
  VocabularyLevel get level => defaultLevel;

  String get lowerLocator => locator.toLowerCase();

  bool get isPdf => lowerLocator.endsWith('.pdf');

  bool get isScanDocument => lowerLocator.endsWith('.lingfer_scan.json');

  bool get isImage =>
      lowerLocator.endsWith('.png') ||
      lowerLocator.endsWith('.jpg') ||
      lowerLocator.endsWith('.jpeg') ||
      lowerLocator.endsWith('.heic') ||
      lowerLocator.endsWith('.webp');

  bool get isScanContent => isImage || isScanDocument;

  String get id => stableKey;

  Book withDefaultLevel(VocabularyLevel next) => Book(
        title: title,
        author: author,
        defaultLevel: next,
        source: source,
        locator: locator,
        isPinned: isPinned,
        coverAssetPath: coverAssetPath,
        coverFilePath: coverFilePath,
        blurb: blurb,
      );

  Book withPinned(bool pinned) => Book(
        title: title,
        author: author,
        defaultLevel: defaultLevel,
        source: source,
        locator: locator,
        isPinned: pinned,
        coverAssetPath: coverAssetPath,
        coverFilePath: coverFilePath,
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
    if (isImage) {
      return '扫描图片';
    }
    if (isScanDocument) {
      return '扫描文稿';
    }
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
    final lower = path.toLowerCase();
    final title = name.replaceAll(
      RegExp(_bookTitleSuffixPattern, caseSensitive: false),
      '',
    );
    return Book(
      title: title.isEmpty ? name : title,
      author: lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.heic') ||
              lower.endsWith('.webp')
          ? '图片导入'
          : '本地导入',
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
        'isPinned': isPinned,
        'coverAssetPath': coverAssetPath,
        'coverFilePath': coverFilePath,
        'blurb': blurb,
      };

  static Book? fromJson(Map<String, Object?> json) {
    final title = json['title'];
    final author = json['author'];
    final defaultLevel = (json['level'] is String) ? json['level'] : json['defaultLevel'];
    final source = json['source'];
    final locator = json['locator'];
    final isPinned = json['isPinned'];
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
    final coverFile = json['coverFilePath'];
    final blurb = json['blurb'];
    return Book(
      title: title,
      author: author,
      defaultLevel: level,
      source: src,
      locator: locator,
      isPinned: isPinned is bool ? isPinned : false,
      coverAssetPath: cover is String ? cover : null,
      coverFilePath: coverFile is String ? coverFile : null,
      blurb: blurb is String ? blurb : null,
    );
  }
}
