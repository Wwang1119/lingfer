import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';
import 'imported_file_store.dart';

class ScanBookOcrLine {
  const ScanBookOcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  static ScanBookOcrLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] ?? '').toString().trim();
    final left = _asDouble(raw['left']);
    final top = _asDouble(raw['top']);
    final width = _asDouble(raw['width']);
    final height = _asDouble(raw['height']);
    if (text.isEmpty || left == null || top == null || width == null || height == null) {
      return null;
    }
    return ScanBookOcrLine(
      text: text,
      left: left,
      top: top,
      width: width,
      height: height,
    );
  }
}

class ScanBookOcrCache {
  const ScanBookOcrCache({
    required this.rawText,
    required this.cleanedText,
    required this.imageWidth,
    required this.imageHeight,
    required this.lines,
    required this.annotatedTexts,
  });

  final String rawText;
  final String cleanedText;
  final double imageWidth;
  final double imageHeight;
  final List<ScanBookOcrLine> lines;
  final Map<String, String> annotatedTexts;

  ScanBookOcrCache copyWith({
    String? rawText,
    String? cleanedText,
    double? imageWidth,
    double? imageHeight,
    List<ScanBookOcrLine>? lines,
    Map<String, String>? annotatedTexts,
  }) {
    return ScanBookOcrCache(
      rawText: rawText ?? this.rawText,
      cleanedText: cleanedText ?? this.cleanedText,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      lines: lines ?? this.lines,
      annotatedTexts: annotatedTexts ?? this.annotatedTexts,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'rawText': rawText,
        'cleanedText': cleanedText,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'lines': lines.map((e) => e.toJson()).toList(growable: false),
        'annotatedTexts': annotatedTexts,
      };

  static ScanBookOcrCache? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawText = (raw['rawText'] ?? '').toString();
    final cleanedText = (raw['cleanedText'] ?? '').toString();
    final imageWidth = _asDouble(raw['imageWidth']) ?? 1;
    final imageHeight = _asDouble(raw['imageHeight']) ?? 1;
    final linesRaw = raw['lines'];
    final lines = <ScanBookOcrLine>[];
    if (linesRaw is List) {
      for (final item in linesRaw) {
        final line = ScanBookOcrLine.fromJson(item);
        if (line != null) lines.add(line);
      }
    }

    final annotated = <String, String>{};
    final annotatedRaw = raw['annotatedTexts'];
    if (annotatedRaw is Map) {
      annotatedRaw.forEach((key, value) {
        if (key is String && value is String && value.trim().isNotEmpty) {
          annotated[key] = value;
        }
      });
    }

    return ScanBookOcrCache(
      rawText: rawText,
      cleanedText: cleanedText,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      lines: List<ScanBookOcrLine>.unmodifiable(lines),
      annotatedTexts: Map<String, String>.unmodifiable(annotated),
    );
  }
}

class ScanBookPage {
  const ScanBookPage({
    required this.path,
    required this.createdAtMs,
    this.cache,
  });

  final String path;
  final int createdAtMs;
  final ScanBookOcrCache? cache;

  ScanBookPage copyWith({
    String? path,
    int? createdAtMs,
    ScanBookOcrCache? cache,
    bool clearCache = false,
  }) {
    return ScanBookPage(
      path: path ?? this.path,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      cache: clearCache ? null : (cache ?? this.cache),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'createdAtMs': createdAtMs,
        'cache': cache?.toJson(),
      };

  static ScanBookPage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pagePath = (raw['path'] ?? '').toString().trim();
    if (pagePath.isEmpty) return null;
    final created = raw['createdAtMs'];
    return ScanBookPage(
      path: pagePath,
      createdAtMs: created is int ? created : DateTime.now().millisecondsSinceEpoch,
      cache: ScanBookOcrCache.fromJson(raw['cache']),
    );
  }
}

class ScanBookDocument {
  const ScanBookDocument({
    required this.path,
    required this.title,
    required this.pages,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String path;
  final String title;
  final List<ScanBookPage> pages;
  final int createdAtMs;
  final int updatedAtMs;

  String? get coverPath => pages.isEmpty ? null : pages.first.path;

  ScanBookDocument copyWith({
    String? path,
    String? title,
    List<ScanBookPage>? pages,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return ScanBookDocument(
      path: path ?? this.path,
      title: title ?? this.title,
      pages: pages ?? this.pages,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'pages': pages.map((e) => e.toJson()).toList(growable: false),
      };

  Book toBook(VocabularyLevel level, {bool isPinned = false}) => Book(
        title: title,
        author: '${pages.length} 页扫描',
        defaultLevel: level,
        source: BookSource.localFile,
        locator: path,
        coverFilePath: coverPath,
        isPinned: isPinned,
      );

  static ScanBookDocument? fromJson(String path, Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString().trim();
    final pagesRaw = json['pages'];
    if (title.isEmpty || pagesRaw is! List) return null;

    final pages = <ScanBookPage>[];
    for (final item in pagesRaw) {
      final page = ScanBookPage.fromJson(item);
      if (page != null) pages.add(page);
    }
    if (pages.isEmpty) return null;

    final createdAt = json['createdAtMs'];
    final updatedAt = json['updatedAtMs'];
    return ScanBookDocument(
      path: path,
      title: title,
      pages: List<ScanBookPage>.unmodifiable(pages),
      createdAtMs: createdAt is int ? createdAt : DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: updatedAt is int ? updatedAt : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ScanBookStore {
  static Future<Directory> _scanDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}Lingfer${Platform.pathSeparator}ScanBooks',
    );
    await dir.create(recursive: true);
    return dir;
  }

  static String _sanitizeTitle(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return defaultTitle();
    return t.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static String defaultTitle() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '扫描文稿 $mm.$dd $hh:$min';
  }

  static Future<ScanBookDocument> create({
    required String title,
    required String firstImagePath,
  }) {
    return createFromImages(title: title, imagePaths: <String>[firstImagePath]);
  }

  static Future<ScanBookDocument> createFromImages({
    required String title,
    required List<String> imagePaths,
  }) async {
    final cleaned = imagePaths.where((e) => e.trim().isNotEmpty).toList(growable: false);
    if (cleaned.isEmpty) {
      throw ArgumentError('imagePaths must not be empty');
    }

    final dir = await _scanDir();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pages = <ScanBookPage>[];
    for (final imagePath in cleaned) {
      final storedImage = await ImportedFileStore.ingest(imagePath);
      pages.add(
        ScanBookPage(
          path: storedImage,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    final file = File(
      '${dir.path}${Platform.pathSeparator}scan_$now.lingfer_scan.json',
    );
    final document = ScanBookDocument(
      path: file.path,
      title: _sanitizeTitle(title),
      pages: List<ScanBookPage>.unmodifiable(pages),
      createdAtMs: now,
      updatedAtMs: now,
    );
    await _write(document);
    return document;
  }

  static Future<ScanBookDocument?> load(String manifestPath) async {
    try {
      final file = File(manifestPath);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ScanBookDocument.fromJson(manifestPath, decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<ScanBookDocument?> rename({
    required String manifestPath,
    required String title,
  }) async {
    final current = await load(manifestPath);
    if (current == null) return null;
    final updated = current.copyWith(
      title: _sanitizeTitle(title),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(updated);
    return updated;
  }

  static Future<ScanBookDocument?> appendPage({
    required String manifestPath,
    required String imagePath,
  }) {
    return appendPages(
      manifestPath: manifestPath,
      imagePaths: <String>[imagePath],
    );
  }

  static Future<ScanBookDocument?> appendPages({
    required String manifestPath,
    required List<String> imagePaths,
  }) async {
    final current = await load(manifestPath);
    if (current == null) return null;
    final cleaned = imagePaths.where((e) => e.trim().isNotEmpty).toList(growable: false);
    if (cleaned.isEmpty) return current;

    final nextPages = <ScanBookPage>[...current.pages];
    for (final imagePath in cleaned) {
      final storedImage = await ImportedFileStore.ingest(imagePath);
      nextPages.add(
        ScanBookPage(
          path: storedImage,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    final updated = current.copyWith(
      pages: List<ScanBookPage>.unmodifiable(nextPages),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(updated);
    return updated;
  }

  static Future<ScanBookDocument?> updatePageCache({
    required String manifestPath,
    required String pagePath,
    required ScanBookOcrCache cache,
  }) async {
    final current = await load(manifestPath);
    if (current == null) return null;
    final nextPages = <ScanBookPage>[];
    var changed = false;
    for (final page in current.pages) {
      if (page.path == pagePath) {
        nextPages.add(page.copyWith(cache: cache));
        changed = true;
      } else {
        nextPages.add(page);
      }
    }
    if (!changed) return current;

    final updated = current.copyWith(
      pages: List<ScanBookPage>.unmodifiable(nextPages),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(updated);
    return updated;
  }

  static Future<ScanBookDocument?> syncPages({
    required String manifestPath,
    required List<String> orderedPagePaths,
  }) async {
    final current = await load(manifestPath);
    if (current == null) return null;

    final nextPaths = orderedPagePaths.where((e) => e.trim().isNotEmpty).toList(growable: false);
    if (nextPaths.isEmpty) {
      await delete(manifestPath);
      return null;
    }

    final currentByPath = <String, ScanBookPage>{
      for (final page in current.pages) page.path: page,
    };
    final nextPages = <ScanBookPage>[];
    for (final path in nextPaths) {
      final page = currentByPath[path];
      if (page != null) nextPages.add(page);
    }
    if (nextPages.isEmpty) {
      await delete(manifestPath);
      return null;
    }

    final removedPaths = current.pages
        .where((page) => !nextPaths.contains(page.path))
        .map((page) => page.path)
        .toList(growable: false);
    for (final path in removedPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    final updated = current.copyWith(
      pages: List<ScanBookPage>.unmodifiable(nextPages),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(updated);
    return updated;
  }

  static Future<void> delete(String manifestPath) async {
    final current = await load(manifestPath);
    if (current == null) {
      final file = File(manifestPath);
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    for (final page in current.pages) {
      try {
        final file = File(page.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    try {
      final file = File(current.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> _write(ScanBookDocument document) async {
    final file = File(document.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
      flush: true,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
