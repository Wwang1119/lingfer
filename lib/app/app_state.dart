import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/vocabulary_level.dart';

class AppState extends ChangeNotifier {
  static const _shelfKey = 'lens_shelf_v2';

  SharedPreferences? _prefs;
  bool _initialized = false;

  final List<Book> _shelf = <Book>[];
  List<Book> get shelf => List<Book>.unmodifiable(_shelf);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _prefs = await SharedPreferences.getInstance();
    _loadShelf();
  }

  int progressTopChunk(Book book) {
    final prefs = _prefs;
    if (prefs == null) return 0;
    return prefs.getInt('progress_topChunk_${book.stableKey}') ?? 0;
  }

  Future<void> addToShelf(Book book) async {
    _shelf.removeWhere((b) => b.stableKey == book.stableKey);
    _shelf.insert(0, book);
    notifyListeners();
    await _persistShelf();
  }

  Future<void> removeFromShelf(Book book) async {
    _shelf.removeWhere((b) => b.stableKey == book.stableKey);
    notifyListeners();
    await _persistShelf();
  }

  Future<void> replaceBook({
    required String oldId,
    required Book newBook,
  }) async {
    final idx = _shelf.indexWhere((b) => b.stableKey == oldId);
    if (idx < 0) {
      await addToShelf(newBook);
      return;
    }

    // Avoid duplicates if another card already uses the new ID.
    _shelf.removeWhere((b) => b.stableKey == newBook.stableKey && b.stableKey != oldId);

    _shelf[idx] = newBook;
    notifyListeners();

    final prefs = _prefs;
    if (prefs != null && oldId != newBook.stableKey) {
      try {
        final oldProgress = 'progress_topChunk_$oldId';
        final newProgress = 'progress_topChunk_${newBook.stableKey}';
        final v = prefs.getInt(oldProgress);
        if (v != null && !prefs.containsKey(newProgress)) {
          await prefs.setInt(newProgress, v);
        }
        await prefs.remove(oldProgress);

        final oldPrefix = 'chunk_level_${oldId}_';
        final newPrefix = 'chunk_level_${newBook.stableKey}_';
        for (final k in prefs.getKeys()) {
          if (!k.startsWith(oldPrefix)) continue;
          final suffix = k.substring(oldPrefix.length);
          final nk = '$newPrefix$suffix';
          final val = prefs.getString(k);
          if (val != null && !prefs.containsKey(nk)) {
            await prefs.setString(nk, val);
          }
          await prefs.remove(k);
        }

        // Horizontal paging progress keys are dimension-dependent (suffix varies).
        final oldPagePrefix = 'progress_page_${oldId}_';
        final newPagePrefix = 'progress_page_${newBook.stableKey}_';
        for (final k in prefs.getKeys()) {
          if (!k.startsWith(oldPagePrefix)) continue;
          final suffix = k.substring(oldPagePrefix.length);
          final nk = '$newPagePrefix$suffix';
          final val = prefs.getInt(k);
          if (val != null && !prefs.containsKey(nk)) {
            await prefs.setInt(nk, val);
          }
          await prefs.remove(k);
        }

        Future<void> migrateStringKey(String ok, String nk) async {
          final val = prefs.getString(ok);
          if (val != null && !prefs.containsKey(nk)) {
            await prefs.setString(nk, val);
          }
          await prefs.remove(ok);
        }

        Future<void> migrateIntKey(String ok, String nk) async {
          final val = prefs.getInt(ok);
          if (val != null && !prefs.containsKey(nk)) {
            await prefs.setInt(nk, val);
          }
          await prefs.remove(ok);
        }

        // Bookmarks & highlights.
        await migrateIntKey(
          'bookmark_page_$oldId',
          'bookmark_page_${newBook.stableKey}',
        );
        await migrateIntKey(
          'bookmark_chunk_$oldId',
          'bookmark_chunk_${newBook.stableKey}',
        );
        await migrateStringKey(
          'bookmarks_page_$oldId',
          'bookmarks_page_${newBook.stableKey}',
        );
        await migrateStringKey(
          'bookmarks_chunk_$oldId',
          'bookmarks_chunk_${newBook.stableKey}',
        );
        await migrateStringKey(
          'highlights_page_$oldId',
          'highlights_page_${newBook.stableKey}',
        );
        await migrateStringKey(
          'highlights_chunk_$oldId',
          'highlights_chunk_${newBook.stableKey}',
        );
      } catch (_) {}
    }

    await _persistShelf();
  }

  void _loadShelf() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_shelfKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _shelf.clear();
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = <String, Object?>{};
        item.forEach((k, v) {
          if (k is String) map[k] = v;
        });
        final b = Book.fromJson(map);
        if (b == null) continue;
        // Strict de-duplication by composite book ID.
        if (seen.contains(b.stableKey)) continue;
        seen.add(b.stableKey);
        _shelf.add(b);
      }
    } catch (_) {
      _shelf.clear();
    }
    notifyListeners();
  }

  Future<void> _persistShelf() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final list = _shelf.map((b) => b.toJson()).toList(growable: false);
      await prefs.setString(_shelfKey, jsonEncode(list));
    } catch (_) {}
  }

  Book createCatalogBook({
    required String title,
    required String author,
    required String assetPath,
    required VocabularyLevel defaultLevel,
    String? coverAssetPath,
    String? blurb,
  }) {
    return Book(
      title: title,
      author: author,
      defaultLevel: defaultLevel,
      source: BookSource.asset,
      locator: assetPath,
      coverAssetPath: coverAssetPath,
      blurb: blurb,
    );
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}
