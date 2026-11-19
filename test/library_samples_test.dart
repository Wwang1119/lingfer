import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lingfer/main.dart';
import 'package:lingfer/models/book.dart';
import 'package:lingfer/models/vocabulary_level.dart';
import 'package:lingfer/services/asset_books_service.dart';
import 'package:lingfer/services/book_text_service.dart';
import 'package:lingfer/services/imported_file_store.dart';
import 'package:lingfer/features/companion/vocabulary_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const level = VocabularyLevel.cet4;
  final reader = BookTextService();

  test(
    'All bundled English originals are complete and available offline',
    () async {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/licenses/public-domain-books.json',
                ),
              )
              as Map<String, dynamic>;
      final evidence = manifest['books'] as List;
      final minimumWords = [25000, 100000, 120000];
      final endings = [
        'THE END',
        'considerable success.',
        'CHANCERY LANE, LONDON.',
      ];
      for (var i = 0; i < AssetBooksService.publicDomainCatalog.length; i++) {
        final entry = AssetBooksService.publicDomainCatalog[i];
        final text = await reader.readBookText(entry.toBook(level));
        expect(
          text.split(RegExp(r'\s+')).length,
          greaterThan(minimumWords[i]),
          reason: entry.title,
        );
        expect(
          text.trimRight().endsWith(endings[i]),
          isTrue,
          reason: '${entry.title}: original ending retained',
        );
        expect(text.toLowerCase(), isNot(contains('project gutenberg')));
        expect(utf8.encode(text).length, evidence[i]['assetBytes']);
        expect(
          evidence[i]['modification'].toString().toLowerCase(),
          contains('complete literary text'),
        );
        expect(text, isNot(contains('\r')), reason: 'Use LF in bundled text');
        expect(
          RegExp(r'\n(?:[ \t]*\n){3}').hasMatch(text),
          isFalse,
          reason: '${entry.title}: at most two consecutive blank lines',
        );
        expect(
          RegExp(r'^\s*\[Illustration\]\s*$', multiLine: true).hasMatch(text),
          isFalse,
          reason: 'Standalone non-text illustration placeholders are removed',
        );
        expect(
          text.trim().split(RegExp(r'\s+')).length,
          evidence[i]['bodyWords'],
        );
        if (i == 0) {
          expect(text, startsWith('Alice’s Adventures in Wonderland\n'));
        }
      }
      final all = await AssetBooksService().loadBundledBooks(
        defaultLevel: level,
      );
      for (final entry in AssetBooksService.publicDomainCatalog) {
        expect(
          all.where((book) => book.locator == entry.assetPath).single.title,
          entry.title,
        );
      }
    },
  );

  test(
    'EPUB without NCX follows OPF spine order and skips its navigation document',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lingfer-epub-spine-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final archive = Archive();
      void add(String name, String text) {
        final bytes = utf8.encode(text);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add('mimetype', 'application/epub+zip');
      add(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
      );
      add(
        'OPS/book.opf',
        '''<package><manifest>
      <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
      <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
      <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
      </manifest><spine><itemref idref="nav"/><itemref idref="b"/><itemref idref="a"/></spine></package>''',
      );
      add(
        'OPS/a.xhtml',
        '<html><body><p>The second reading passage is still present.</p></body></html>',
      );
      add(
        'OPS/b.xhtml',
        '<html><body><p>The first reading passage opens this book.</p></body></html>',
      );
      add(
        'OPS/nav.xhtml',
        '<html><body>Navigation that should not become the first page</body></html>',
      );
      final file = File('${directory.path}/no-ncx.epub');
      await file.writeAsBytes(ZipEncoder().encode(archive)!);
      final text = await reader.readBookText(
        Book.fromLocalPath(file.path, defaultLevel: level),
      );
      expect(
        text.indexOf('first reading'),
        lessThan(text.indexOf('second reading')),
      );
      expect(text, isNot(contains('Navigation that')));
      expect(text, contains('still present.'));
    },
  );

  test(
    'Missing and empty imports produce readable errors without deleting files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lingfer-book-errors-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final missing = Book.fromLocalPath(
        '${directory.path}/missing.txt',
        defaultLevel: level,
      );
      await expectLater(
        reader.readBookText(missing),
        throwsA(
          isA<BookReadException>().having(
            (e) => e.message,
            'missing explanation',
            contains('重新导入'),
          ),
        ),
      );
      final empty = File('${directory.path}/empty.txt');
      await empty.writeAsString('  \n\n');
      await expectLater(
        reader.readBookText(
          Book.fromLocalPath(empty.path, defaultLevel: level),
        ),
        throwsA(
          isA<BookReadException>().having(
            (e) => e.message,
            'empty explanation',
            contains('正文'),
          ),
        ),
      );
      expect(await empty.readAsString(), '  \n\n');
      final broken = File('${directory.path}/broken.epub');
      await broken.writeAsString('not a ZIP');
      await expectLater(
        reader.readBookText(
          Book.fromLocalPath(broken.path, defaultLevel: level),
        ),
        throwsA(isA<BookReadException>()),
      );
    },
  );

  test(
    'An updated app resolves its own old import path without searching other files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lingfer-moved-container-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File(
        '${directory.path}/Lingfer/ImportedBooks/stable_book.txt',
      );
      await target.parent.create(recursive: true);
      await target.writeAsString(
        'The imported book survives the container move.',
      );
      final oldLocator =
          '/previous-app-container/Lingfer/ImportedBooks/stable_book.txt';
      expect(
        await ImportedFileStore.resolveReadablePath(
          oldLocator,
          supportDirectory: directory,
        ),
        target.path,
      );
      expect(
        await ImportedFileStore.resolveReadablePath(
          '/outside/other-folder/stable_book.txt',
          supportDirectory: directory,
        ),
        '/outside/other-folder/stable_book.txt',
      );
      expect(
        await ImportedFileStore.resolveReadablePath(
          '/old/Lingfer/ImportedBooks/../stable_book.txt',
          supportDirectory: directory,
        ),
        '/old/Lingfer/ImportedBooks/../stable_book.txt',
      );
      expect(await target.readAsString(), contains('survives'));
      final original = Book.fromLocalPath(
        oldLocator,
        defaultLevel: level,
      ).withPinned(true);
      final resolved = original.withLocator(target.path);
      expect(resolved.stableKey, original.stableKey);
      expect(resolved.defaultLevel, original.defaultLevel);
      expect(resolved.isPinned, isTrue);
    },
  );

  testWidgets(
    'Fresh library keeps imports empty and separates three built-in originals',
    (tester) async {
      tester.view.physicalSize = const Size(344, 842);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('reading-home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('内置公版书'),
        260,
        scrollable: scrollable,
      );
      expect(find.text('0 份'), findsOneWidget);
      for (final entry in AssetBooksService.publicDomainCatalog) {
        expect(
          find.byKey(ValueKey('bundled-book-${entry.assetPath}')),
          findsOneWidget,
        );
      }
      expect(
        (await SharedPreferences.getInstance()).getString('lens_shelf_v2'),
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('书目与来源'),
        240,
        scrollable: scrollable,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('书目与来源')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('书目与来源'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不包含现代中文译本'), findsOneWidget);
      expect(find.text('https://www.gutenberg.org/ebooks/11'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android shelf switches from three covers to a list for large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await tester.pumpAndSettle();

      final shelf = find.text('内置公版书');
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('reading-home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(shelf, 220, scrollable: scrollable);
      List<Rect> tiles() => [
        for (final entry in AssetBooksService.publicDomainCatalog)
          tester.getRect(
            find.byKey(ValueKey('bundled-book-${entry.assetPath}')),
          ),
      ];
      final covers = tiles();
      expect(covers.map((rect) => rect.top).toSet(), hasLength(1));
      expect(covers[0].right, lessThan(covers[1].left));
      expect(covers[1].right, lessThan(covers[2].left));

      tester.view.physicalSize = const Size(320, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(shelf, 220, scrollable: scrollable);
      final rows = tiles();
      expect(rows.map((rect) => rect.left).toSet(), hasLength(1));
      expect(rows[0].bottom, lessThan(rows[1].top));
      expect(rows[1].bottom, lessThan(rows[2].top));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'A missing local file keeps its record and offers explicit recovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const book = Book(
        title: '缺失资料',
        author: '本地导入',
        defaultLevel: level,
        source: BookSource.localFile,
        locator: '/not-a-real-device-file/missing.txt',
      );
      SharedPreferences.setMockInitialValues({
        'lens_shelf_v2': jsonEncode([book.toJson()]),
        'progress_topChunk_${book.stableKey}': 7,
      });
      await tester.runAsync(VocabularyEngine.load);
      await tester.pumpWidget(const LingferRoot());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('缺失资料')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('缺失资料'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(find.text('找不到这份资料的文件'), findsOneWidget);
      expect(find.text('重新选择文件'), findsOneWidget);
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('lens_shelf_v2')!) as List)
            .single['locator'],
        book.locator,
      );
      expect(prefs.getInt('progress_topChunk_${book.stableKey}'), 7);
      expect(tester.takeException(), isNull);
    },
  );
}
