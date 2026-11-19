import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingfer/services/reader_cache_storage.dart';

void main() {
  late Directory fixture;

  Future<File> write(String relativePath, String value) async {
    final file = File('${fixture.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(value));
    return file;
  }

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('lingfer-cache-boundary-');
  });

  tearDown(() async {
    if (await fixture.exists()) await fixture.delete(recursive: true);
  });

  test('Only rebuildable reading cache is measured and cleared', () async {
    final cache = {
      'lens_cache/book-a/chunks/0-cet4.json': '{"原文":"语渡","译文":"Lingfer"}',
      'lens_cache/book-a/chunks/1-cet6.json': '{"text":"second paragraph"}',
      'lens_cache/book-b/chunks/0-cet4.json': 'another cached translation',
    };
    final preserved = {
      'ApplicationSupport/ImportedBooks/source.pdf': 'original imported PDF',
      'ImportedBooks/source.epub': 'original imported EPUB',
      'scan_ocr.json': '{"recognized":"用户保存的扫描正文"}',
      'ApplicationSupport/preferences.json': '{"progress":12,"savedWords":7}',
      'lens_cache_old/keep.json': 'not the exact cache directory',
      'other.tmp': 'unrelated temporary file',
    };
    for (final entry in {...cache, ...preserved}.entries) {
      await write(entry.key, entry.value);
    }
    final storage = ReaderCacheStorage(baseDirectory: fixture);
    final expectedBytes = cache.values.fold<int>(
      0,
      (total, value) => total + utf8.encode(value).length,
    );

    final before = await storage.inspect();
    expect(before.bytes, expectedBytes);
    expect(before.files, cache.length);

    final cleared = await storage.clear();
    expect(cleared.bytes, expectedBytes);
    expect(cleared.files, cache.length);
    final after = await storage.inspect();
    expect(after.bytes, 0);
    expect(after.files, 0);
    final cacheRoot = Directory('${fixture.path}/lens_cache');
    expect(await cacheRoot.exists(), isTrue);
    expect(await cacheRoot.list(followLinks: false).toList(), isEmpty);
    for (final entry in preserved.entries) {
      expect(
        await File('${fixture.path}/${entry.key}').readAsString(),
        entry.value,
        reason: '${entry.key} is not reading cache',
      );
    }
  });

  test(
    'Nested file, directory, cyclic and broken links are never followed',
    () async {
      final original = await write(
        'ApplicationSupport/ImportedBooks/original.txt',
        'keep this original file',
      );
      final protectedFile = await write(
        'ApplicationSupport/scan/ocr.json',
        '{"original":"保留这份扫描文字"}',
      );
      final cached = await write('lens_cache/book/chunks/0.json', 'cached');
      final cacheRoot = Directory('${fixture.path}/lens_cache');
      final links = [
        Link('${cacheRoot.path}/linked-original'),
        Link('${cacheRoot.path}/linked-scan-directory'),
        Link('${cacheRoot.path}/book/chunks/loop'),
        Link('${cacheRoot.path}/broken-link'),
      ];
      await links[0].create(original.path);
      await links[1].create(protectedFile.parent.path);
      await links[2].create(cacheRoot.path);
      await links[3].create('${fixture.path}/missing-target');
      final storage = ReaderCacheStorage(baseDirectory: fixture);

      final before = await storage.inspect();
      expect(before.bytes, await cached.length());
      expect(before.files, 1);
      final cleared = await storage.clear();
      expect(cleared.bytes, utf8.encode('cached').length);
      expect(cleared.files, 1);
      expect(await original.readAsString(), 'keep this original file');
      expect(await protectedFile.readAsString(), '{"original":"保留这份扫描文字"}');
      for (final link in links) {
        expect(
          await FileSystemEntity.type(link.path, followLinks: false),
          FileSystemEntityType.notFound,
          reason: 'Only the link itself is removed',
        );
      }
      expect(await cacheRoot.list(followLinks: false).toList(), isEmpty);
    },
    skip: Platform.isWindows ? 'Requires symlink creation permission' : false,
  );

  test('A lens_cache root link does not permit entering its target', () async {
    final original = await write(
      'ApplicationSupport/ImportedBooks/valuable.txt',
      'preserve this target',
    );
    final rootLink = Link('${fixture.path}/lens_cache');
    await rootLink.create(original.parent.path);
    final storage = ReaderCacheStorage(baseDirectory: fixture);

    final before = await storage.inspect();
    final cleared = await storage.clear();
    expect(before.bytes, 0);
    expect(before.files, 0);
    expect(cleared.bytes, 0);
    expect(cleared.files, 0);
    expect(await original.readAsString(), 'preserve this target');
    expect(
      await FileSystemEntity.type(rootLink.path, followLinks: false),
      FileSystemEntityType.link,
    );
  }, skip: Platform.isWindows ? 'Requires symlink creation permission' : false);

  test(
    'A linked base directory does not redirect cache inspection or deletion',
    () async {
      final target = await write('real-base/lens_cache/chunk.json', 'keep me');
      final baseLink = Link('${fixture.path}/base-alias');
      await baseLink.create('${fixture.path}/real-base');
      final storage = ReaderCacheStorage(
        baseDirectory: Directory(baseLink.path),
      );

      final before = await storage.inspect();
      final cleared = await storage.clear();
      expect(before.bytes, 0);
      expect(before.files, 0);
      expect(cleared.bytes, 0);
      expect(cleared.files, 0);
      expect(await target.readAsString(), 'keep me');
      expect(
        await FileSystemEntity.type(baseLink.path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
    skip: Platform.isWindows ? 'Requires symlink creation permission' : false,
  );

  test('Missing and empty cache cleanup is idempotent', () async {
    final storage = ReaderCacheStorage(baseDirectory: fixture);
    final cacheRoot = Directory('${fixture.path}/lens_cache');
    expect((await storage.inspect()).bytes, 0);
    expect((await storage.clear()).files, 0);
    expect(await cacheRoot.exists(), isFalse);

    await Directory(
      '${cacheRoot.path}/empty-book/chunks',
    ).create(recursive: true);
    expect((await storage.inspect()).files, 0);
    expect((await storage.clear()).bytes, 0);
    expect(await cacheRoot.exists(), isTrue);
    expect(await cacheRoot.list(followLinks: false).toList(), isEmpty);
    final repeated = await storage.clear();
    expect(repeated.bytes, 0);
    expect(repeated.files, 0);
  });
}
