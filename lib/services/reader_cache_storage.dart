import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ReaderCacheUsage {
  const ReaderCacheUsage({this.bytes = 0, this.files = 0});

  final int bytes;
  final int files;

  ReaderCacheUsage operator +(ReaderCacheUsage other) =>
      ReaderCacheUsage(bytes: bytes + other.bytes, files: files + other.files);
}

/// Only owns the rebuildable translation cache inside the temporary directory.
/// Imported originals, OCR documents and preferences are outside this boundary.
class ReaderCacheStorage {
  ReaderCacheStorage({this.baseDirectory});

  /// Tests may supply a temporary-directory root, never an arbitrary cache path.
  final Directory? baseDirectory;

  Future<Directory?> _cacheDirectory() async {
    final base = baseDirectory ?? await getTemporaryDirectory();
    if (await FileSystemEntity.type(base.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    final cache = Directory('${base.path}${Platform.pathSeparator}lens_cache');
    if (await FileSystemEntity.type(cache.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    return cache;
  }

  Future<ReaderCacheUsage> inspect() async {
    final cache = await _cacheDirectory();
    return cache == null
        ? const ReaderCacheUsage()
        : _visit(cache, remove: false);
  }

  /// Keeps the cache container available to existing readers. Links inside it
  /// are unlinked themselves; no operation traverses their destinations.
  Future<ReaderCacheUsage> clear() async {
    final cache = await _cacheDirectory();
    return cache == null
        ? const ReaderCacheUsage()
        : _visit(cache, remove: true);
  }

  Future<ReaderCacheUsage> _visit(
    Directory directory, {
    required bool remove,
  }) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const ReaderCacheUsage();
    }
    var usage = const ReaderCacheUsage();
    await for (final entry in directory.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entry.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        final file = File(entry.path);
        final bytes = await file.length();
        if (remove) await file.delete();
        usage += ReaderCacheUsage(bytes: bytes, files: 1);
      } else if (type == FileSystemEntityType.directory) {
        final child = Directory(entry.path);
        usage += await _visit(child, remove: remove);
        if (remove &&
            await FileSystemEntity.type(child.path, followLinks: false) ==
                FileSystemEntityType.directory) {
          // Never use recursive delete: a concurrently written cache can stay
          // for the next sweep, and a link must never expand this boundary.
          if (await child.list(followLinks: false).isEmpty) {
            await child.delete();
          }
        }
      } else if (type == FileSystemEntityType.link && remove) {
        await Link(entry.path).delete();
      }
    }
    return usage;
  }
}
