import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lingfer/app/app_state.dart';
import 'package:lingfer/models/book.dart';
import 'package:lingfer/models/vocabulary_level.dart';

const _shelfKey = 'lens_shelf_v2';
const _archiveKey = 'lens_archived_empty_examples_v1';

const _examples = [
  Book(
    title: '旧版空示例甲',
    author: '原作者信息',
    defaultLevel: VocabularyLevel.cet4,
    source: BookSource.mock,
    locator: 'mock://old/example-a',
    isPinned: true,
    coverAssetPath: 'assets/old-cover.png',
    blurb: '保留原有描述',
  ),
  Book(
    title: '旧版空示例乙',
    author: '旧版书架作者',
    defaultLevel: VocabularyLevel.ielts,
    source: BookSource.mock,
    locator: 'mock://old/example-b',
    coverFilePath: '/original/cover-b.jpg',
  ),
];

const _realBooks = [
  Book(
    title: '茶馆',
    author: '老舍',
    defaultLevel: VocabularyLevel.cet4,
    source: BookSource.asset,
    locator: 'assets/books/cha_guan.epub',
  ),
  Book(
    title: '爱丽丝梦游仙境',
    author: 'Lewis Carroll',
    defaultLevel: VocabularyLevel.cet6,
    source: BookSource.asset,
    locator: 'assets/books/alice_in_wonderland.txt',
  ),
  Book(
    title: '用户导入的完整书',
    author: '本地导入',
    defaultLevel: VocabularyLevel.gaokao,
    source: BookSource.localFile,
    locator: '/ApplicationSupport/ImportedBooks/full-novel.epub',
    isPinned: true,
    coverFilePath: '/ApplicationSupport/ImportedBooks/cover.jpg',
  ),
  Book(
    title: '用户的扫描文稿',
    author: '扫描导入',
    defaultLevel: VocabularyLevel.zhongkao,
    source: BookSource.localFile,
    locator: '/ApplicationSupport/scan/original.lingfer_scan.json',
  ),
  Book(
    title: '名字像旧版空示例的本地文件',
    author: '本地导入',
    defaultLevel: VocabularyLevel.toefl,
    source: BookSource.localFile,
    locator: '/ApplicationSupport/ImportedBooks/empty-sounding-title.pdf',
  ),
];

Map<String, Object> _protectedPreferences() => {
  for (final book in [..._examples, ..._realBooks]) ...{
    'progress_topChunk_${book.stableKey}': 17,
    'progress_page_${book.stableKey}_fs18_w390_h844': 9,
    'bookmark_page_${book.stableKey}': 8,
    'chunk_level_${book.stableKey}_0': 'cet4',
    'highlights_page_${book.stableKey}': '[{"start":12,"end":20}]',
  },
  'companion_saved_v1': '[{"word":"preserve","original":"保留我的原句"}]',
  'companion_known_v1': <String>['familiar', '已学会的词'],
  'companion_review_v1': '{"preserve":{"due":123456,"repetitions":3}}',
  'reader_theme': 'paper',
  'arbitrary_user_flag': true,
  'arbitrary_user_number': 1.25,
  'arbitrary_user_list': <String>['one', 'two'],
};

Map<String, Object?> _unrelatedPreferences(SharedPreferences prefs) => {
  for (final key in prefs.getKeys())
    if (key != _shelfKey && key != _archiveKey) key: prefs.get(key),
};

Map<String, Map<String, Object?>> _byId(Iterable<Book> books) => {
  for (final book in books) book.stableKey: book.toJson(),
};

List<dynamic> _storedBooks(SharedPreferences prefs, String key) =>
    jsonDecode(prefs.getString(key)!) as List<dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Archiving only mock entries preserves every real record and preference',
    () async {
      final all = [..._examples, ..._realBooks];
      SharedPreferences.setMockInitialValues({
        _shelfKey: jsonEncode(all.map((book) => book.toJson()).toList()),
        ..._protectedPreferences(),
      });
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final prefs = await SharedPreferences.getInstance();
      final protectedBefore = _unrelatedPreferences(prefs);
      final originals = state.shelf
          .where((book) => book.source == BookSource.mock)
          .toList();

      final removed = await state.archiveEmptyExamples();

      expect(removed.length, _examples.length);
      for (var i = 0; i < originals.length; i++) {
        expect(identical(removed[i], originals[i]), isTrue);
        expect(removed[i].toJson(), _examples[i].toJson());
      }
      expect(_byId(state.shelf), _byId(_realBooks));
      expect(
        _storedBooks(prefs, _shelfKey),
        _realBooks.map((book) => book.toJson()).toList(),
      );
      expect(
        _storedBooks(prefs, _archiveKey),
        _examples.map((book) => book.toJson()).toList(),
      );
      expect(_unrelatedPreferences(prefs), protectedBefore);
      expect(prefs.getKeys(), {
        ...protectedBefore.keys,
        _shelfKey,
        _archiveKey,
      });

      final reloaded = AppState();
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(_byId(reloaded.shelf), _byId(_realBooks));
      expect(reloaded.shelf.any((book) => book.isScanDocument), isTrue);
    },
  );

  test(
    'Returned original metadata can be restored through addToShelf',
    () async {
      final all = [..._examples, ..._realBooks];
      SharedPreferences.setMockInitialValues({
        _shelfKey: jsonEncode(all.map((book) => book.toJson()).toList()),
        ..._protectedPreferences(),
      });
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final prefs = await SharedPreferences.getInstance();
      final protectedBefore = _unrelatedPreferences(prefs);
      final removed = await state.archiveEmptyExamples();

      for (final book in removed) {
        await state.addToShelf(book);
      }

      expect(state.shelf.length, all.length);
      expect(_byId(state.shelf), _byId(all));
      expect(_unrelatedPreferences(prefs), protectedBefore);
      for (final book in all) {
        expect(state.progressTopChunk(book), 17);
      }
      final reloaded = AppState();
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(_byId(reloaded.shelf), _byId(all));
    },
  );

  test(
    'Repeated archiving merges backup metadata without duplicates',
    () async {
      const archivedEarlier = Book(
        title: '更早的空示例',
        author: '保留的历史元数据',
        defaultLevel: VocabularyLevel.kaoyan,
        source: BookSource.mock,
        locator: 'mock://old/archive-only',
      );
      SharedPreferences.setMockInitialValues({
        _shelfKey: jsonEncode(
          [..._examples, ..._realBooks].map((book) => book.toJson()).toList(),
        ),
        _archiveKey: jsonEncode([
          archivedEarlier.toJson(),
          _examples.first.toJson(),
        ]),
      });
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final prefs = await SharedPreferences.getInstance();
      final removed = await state.archiveEmptyExamples();
      final firstBackup = prefs.getString(_archiveKey);
      expect(await state.archiveEmptyExamples(), isEmpty);
      expect(prefs.getString(_archiveKey), firstBackup);

      for (final book in removed) {
        await state.addToShelf(book);
      }
      expect((await state.archiveEmptyExamples()).length, _examples.length);
      final backup = _storedBooks(prefs, _archiveKey);
      final expected = _byId([archivedEarlier, ..._examples]);
      final restoredBackup = backup
          .map((raw) => Book.fromJson(Map<String, Object?>.from(raw as Map))!)
          .toList();
      expect(backup.length, expected.length);
      expect(_byId(restoredBackup), expected);
      expect(_byId(state.shelf), _byId(_realBooks));
    },
  );

  test('A shelf without mock entries leaves all storage untouched', () async {
    SharedPreferences.setMockInitialValues({
      _shelfKey: jsonEncode(_realBooks.map((book) => book.toJson()).toList()),
      _archiveKey: 'keep an existing archive unchanged when there is no work',
      ..._protectedPreferences(),
    });
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};

    expect(await state.archiveEmptyExamples(), isEmpty);

    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(_byId(state.shelf), _byId(_realBooks));
  });
}
