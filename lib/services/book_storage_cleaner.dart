import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

class BookStorageCleaner {
  static int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static String _bookCacheKey(Book book) {
    final hash = _fnv1a32(book.locator);
    return '${book.source.name}_$hash';
  }

  static Future<void> deletePrefs(Book book) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reading progress (both vertical and horizontal paging).
      await prefs.remove('progress_topChunk_${book.stableKey}');
      final pageProgressPrefix = 'progress_page_${book.stableKey}_';
      for (final k in prefs.getKeys()) {
        if (k.startsWith(pageProgressPrefix)) {
          await prefs.remove(k);
        }
      }

      // Bookmarks (legacy single-index keys + newer lists).
      await prefs.remove('bookmark_page_${book.stableKey}');
      await prefs.remove('bookmark_chunk_${book.stableKey}');
      await prefs.remove('bookmarks_page_${book.stableKey}');
      await prefs.remove('bookmarks_chunk_${book.stableKey}');

      // Highlights (if present).
      await prefs.remove('highlights_page_${book.stableKey}');
      await prefs.remove('highlights_chunk_${book.stableKey}');

      final prefix = 'chunk_level_${book.stableKey}_';
      for (final k in prefs.getKeys()) {
        if (k.startsWith(prefix)) {
          await prefs.remove(k);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('[clean] prefs delete error=$error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> deleteCaches(Book book) async {
    // Never throw: deletion is best-effort.
    Directory? tmp;
    try {
      tmp = await getTemporaryDirectory();
    } catch (_) {}

    final base = tmp ?? Directory.systemTemp;

    // Current format: per-book directory.
    try {
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}lens_cache${Platform.pathSeparator}${_bookCacheKey(book)}',
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      debugPrint('[clean] cache dir delete error=$error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // Legacy / fallback: files named like "${book.id}_chunk_*.json" directly in temp.
    try {
      if (await base.exists()) {
        await for (final entity in base.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last;
          if (!name.endsWith('.json')) continue;
          if (!name.startsWith('${book.id}_chunk_')) continue;
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (error, stackTrace) {
      debugPrint('[clean] legacy cache scan error=$error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> deepClean(Book book) async {
    await deletePrefs(book);
    await deleteCaches(book);
  }
}
